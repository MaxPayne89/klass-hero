defmodule KlassHero.Participation.SessionNoteTest do
  @moduledoc """
  Tests for SessionNote domain entity.

  Covers creation, status transitions, predicates, and content validation.
  """

  use KlassHero.DataCase, async: true

  alias KlassHero.Participation.SessionNote

  defp valid_attrs do
    %{
      id: Ecto.UUID.generate(),
      participation_record_id: Ecto.UUID.generate(),
      child_id: Ecto.UUID.generate(),
      provider_id: Ecto.UUID.generate(),
      content: "Child was very engaged and helpful today"
    }
  end

  describe "new/1" do
    test "creates a valid session note with required fields" do
      attrs = valid_attrs()

      assert {:ok, note} = SessionNote.new(attrs)
      assert note.id == attrs.id
      assert note.participation_record_id == attrs.participation_record_id
      assert note.child_id == attrs.child_id
      assert note.provider_id == attrs.provider_id
      assert note.content == attrs.content
      assert note.status == :pending_approval
      assert %DateTime{} = note.submitted_at
    end

    test "creates note with optional parent_id" do
      parent_id = Ecto.UUID.generate()
      attrs = Map.put(valid_attrs(), :parent_id, parent_id)

      assert {:ok, note} = SessionNote.new(attrs)
      assert note.parent_id == parent_id
    end

    test "returns error when required field is missing" do
      for field <- [:id, :participation_record_id, :child_id, :provider_id, :content] do
        attrs = Map.delete(valid_attrs(), field)
        assert {:error, :missing_required_fields} = SessionNote.new(attrs)
      end
    end

    test "returns error for blank content" do
      attrs = %{valid_attrs() | content: "   "}
      assert {:error, :blank_content} = SessionNote.new(attrs)
    end

    test "returns error for empty string content" do
      attrs = %{valid_attrs() | content: ""}
      assert {:error, :blank_content} = SessionNote.new(attrs)
    end

    test "returns error for content exceeding 1000 characters" do
      long_content = String.duplicate("a", 1001)
      attrs = %{valid_attrs() | content: long_content}
      assert {:error, :content_too_long} = SessionNote.new(attrs)
    end

    test "accepts content at exactly 1000 characters" do
      content = String.duplicate("a", 1000)
      attrs = %{valid_attrs() | content: content}
      assert {:ok, _note} = SessionNote.new(attrs)
    end

    test "trims whitespace from content" do
      attrs = %{valid_attrs() | content: "  hello world  "}
      assert {:ok, note} = SessionNote.new(attrs)
      assert note.content == "hello world"
    end
  end

  describe "approve/1" do
    test "transitions :pending_approval to :approved" do
      {:ok, note} = SessionNote.new(valid_attrs())

      assert {:ok, approved} = SessionNote.approve(note)
      assert approved.status == :approved
      assert %DateTime{} = approved.reviewed_at
    end

    test "returns error when approving :approved note" do
      {:ok, note} = SessionNote.new(valid_attrs())
      {:ok, approved} = SessionNote.approve(note)

      assert {:error, :invalid_status_transition} = SessionNote.approve(approved)
    end

    test "returns error when approving :rejected note" do
      {:ok, note} = SessionNote.new(valid_attrs())
      {:ok, rejected} = SessionNote.reject(note, "Not accurate")

      assert {:error, :invalid_status_transition} = SessionNote.approve(rejected)
    end
  end

  describe "reject/2" do
    test "transitions :pending_approval to :rejected with reason" do
      {:ok, note} = SessionNote.new(valid_attrs())

      assert {:ok, rejected} = SessionNote.reject(note, "Not accurate")
      assert rejected.status == :rejected
      assert rejected.rejection_reason == "Not accurate"
      assert %DateTime{} = rejected.reviewed_at
    end

    test "transitions :pending_approval to :rejected without reason" do
      {:ok, note} = SessionNote.new(valid_attrs())

      assert {:ok, rejected} = SessionNote.reject(note)
      assert rejected.status == :rejected
      assert rejected.rejection_reason == nil
    end

    test "returns error when rejecting :approved note" do
      {:ok, note} = SessionNote.new(valid_attrs())
      {:ok, approved} = SessionNote.approve(note)

      assert {:error, :invalid_status_transition} = SessionNote.reject(approved, "reason")
    end

    test "returns error when rejecting already :rejected note" do
      {:ok, note} = SessionNote.new(valid_attrs())
      {:ok, rejected} = SessionNote.reject(note, "reason")

      assert {:error, :invalid_status_transition} = SessionNote.reject(rejected, "again")
    end
  end

  describe "revise/2" do
    test "transitions :rejected to :pending_approval with new content" do
      {:ok, note} = SessionNote.new(valid_attrs())
      {:ok, rejected} = SessionNote.reject(note, "Please rephrase")

      assert {:ok, revised} = SessionNote.revise(rejected, "Updated observation")
      assert revised.status == :pending_approval
      assert revised.content == "Updated observation"
      assert revised.rejection_reason == nil
      assert %DateTime{} = revised.submitted_at
      assert revised.reviewed_at == nil
    end

    test "trims whitespace from revised content" do
      {:ok, note} = SessionNote.new(valid_attrs())
      {:ok, rejected} = SessionNote.reject(note, "Please rephrase")

      assert {:ok, revised} = SessionNote.revise(rejected, "  Updated observation  ")
      assert revised.content == "Updated observation"
    end

    test "returns error when revising :pending_approval note" do
      {:ok, note} = SessionNote.new(valid_attrs())

      assert {:error, :invalid_status_transition} = SessionNote.revise(note, "new content")
    end

    test "returns error when revising :approved note" do
      {:ok, note} = SessionNote.new(valid_attrs())
      {:ok, approved} = SessionNote.approve(note)

      assert {:error, :invalid_status_transition} = SessionNote.revise(approved, "new content")
    end

    test "returns error for blank revised content" do
      {:ok, note} = SessionNote.new(valid_attrs())
      {:ok, rejected} = SessionNote.reject(note, "reason")

      assert {:error, :blank_content} = SessionNote.revise(rejected, "   ")
    end

    test "returns error for revised content exceeding 1000 characters" do
      {:ok, note} = SessionNote.new(valid_attrs())
      {:ok, rejected} = SessionNote.reject(note, "reason")

      long_content = String.duplicate("a", 1001)
      assert {:error, :content_too_long} = SessionNote.revise(rejected, long_content)
    end
  end

  describe "predicates" do
    test "pending?/1 returns true for :pending_approval" do
      {:ok, note} = SessionNote.new(valid_attrs())
      assert SessionNote.pending?(note)
      refute SessionNote.approved?(note)
      refute SessionNote.rejected?(note)
    end

    test "approved?/1 returns true for :approved" do
      {:ok, note} = SessionNote.new(valid_attrs())
      {:ok, approved} = SessionNote.approve(note)
      refute SessionNote.pending?(approved)
      assert SessionNote.approved?(approved)
      refute SessionNote.rejected?(approved)
    end

    test "rejected?/1 returns true for :rejected" do
      {:ok, note} = SessionNote.new(valid_attrs())
      {:ok, rejected} = SessionNote.reject(note)
      refute SessionNote.pending?(rejected)
      refute SessionNote.approved?(rejected)
      assert SessionNote.rejected?(rejected)
    end
  end
end
