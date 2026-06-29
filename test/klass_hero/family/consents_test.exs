defmodule KlassHero.Family.ConsentsTest do
  @moduledoc """
  Context tests for consent grant/withdraw and queries through the
  `KlassHero.Family` public API, exercised against the real sandbox database.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Family
  alias KlassHero.Family.Consent

  @consent_type "provider_data_sharing"

  defp child_and_parent do
    {child, parent} = insert_child_with_guardian()
    %{child_id: child.id, parent_id: parent.id}
  end

  defp grant(%{child_id: child_id, parent_id: parent_id}, consent_type \\ @consent_type) do
    Family.grant_consent(%{parent_id: parent_id, child_id: child_id, consent_type: consent_type})
  end

  describe "grant_consent/1" do
    test "grants consent and returns the record" do
      ctx = child_and_parent()

      assert {:ok, %Consent{} = consent} = grant(ctx)
      assert consent.child_id == ctx.child_id
      assert consent.consent_type == @consent_type
      assert %DateTime{} = consent.granted_at
      assert is_nil(consent.withdrawn_at)
    end

    test "returns :already_active when an active consent of the type exists" do
      ctx = child_and_parent()
      assert {:ok, _} = grant(ctx)

      assert {:error, :already_active} = grant(ctx)
    end

    test "returns a changeset error for invalid input" do
      ctx = child_and_parent()
      assert {:error, %Ecto.Changeset{}} = grant(ctx, "")
    end
  end

  describe "withdraw_consent/2" do
    test "withdraws the active consent" do
      ctx = child_and_parent()
      {:ok, granted} = grant(ctx)

      assert {:ok, %Consent{} = withdrawn} = Family.withdraw_consent(ctx.child_id, @consent_type)
      assert withdrawn.id == granted.id
      assert %DateTime{} = withdrawn.withdrawn_at
    end

    test "returns :not_found when no active consent exists" do
      assert {:error, :not_found} = Family.withdraw_consent(Ecto.UUID.generate(), @consent_type)
    end

    test "returns :not_found when the consent was already withdrawn" do
      ctx = child_and_parent()
      {:ok, _} = grant(ctx)
      {:ok, _} = Family.withdraw_consent(ctx.child_id, @consent_type)

      assert {:error, :not_found} = Family.withdraw_consent(ctx.child_id, @consent_type)
    end
  end

  describe "child_has_active_consent?/2" do
    test "true after granting, false after withdrawing" do
      ctx = child_and_parent()
      refute Family.child_has_active_consent?(ctx.child_id, @consent_type)

      {:ok, _} = grant(ctx)
      assert Family.child_has_active_consent?(ctx.child_id, @consent_type)

      {:ok, _} = Family.withdraw_consent(ctx.child_id, @consent_type)
      refute Family.child_has_active_consent?(ctx.child_id, @consent_type)
    end
  end

  describe "children_with_active_consents/2" do
    test "returns the set of child ids with an active consent of the type" do
      a = child_and_parent()
      b = child_and_parent()
      c = child_and_parent()

      {:ok, _} = grant(a)
      {:ok, _} = grant(b)
      # c never granted; withdrawn consents must be excluded too
      {:ok, _} = grant(c)
      {:ok, _} = Family.withdraw_consent(c.child_id, @consent_type)

      result = Family.children_with_active_consents([a.child_id, b.child_id, c.child_id], @consent_type)

      assert MapSet.member?(result, a.child_id)
      assert MapSet.member?(result, b.child_id)
      refute MapSet.member?(result, c.child_id)
    end
  end
end
