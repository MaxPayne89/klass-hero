defmodule KlassHero.Enrollment.ListOutstandingInvitesForProviderTest do
  @moduledoc """
  Covers the provider-wide "not yet accepted" invite query behind the Overview
  card (#1073).
  """
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Enrollment
  alias KlassHero.Enrollment.BulkEnrollmentInvite
  alias KlassHero.Repo

  setup do
    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id, title: "Chess Club")

    %{provider: provider, program: program}
  end

  defp invite(program, provider, attrs \\ %{}) do
    {status, attrs} = Map.pop(attrs, :status)

    {:ok, invite} =
      Enrollment.create_invite(
        Map.merge(
          %{
            program_id: program.id,
            provider_id: provider.id,
            child_first_name: "Jane",
            child_last_name: "Smith",
            child_date_of_birth: ~D[2015-06-15],
            guardian_email: "guardian@test.com"
          },
          attrs
        )
      )

    # Status is set after insert: the import changeset owns the initial value, and
    # every later transition is the state machine's, not a caller's.
    case status do
      nil -> invite
      status -> invite |> Ecto.Changeset.change(%{status: status}) |> Repo.update!()
    end
  end

  describe "list_outstanding_invites_for_provider/1" do
    # "Outstanding" is exactly BulkEnrollmentInvite.outstanding_statuses/0 — an
    # invite still awaiting an answer. :registered and :enrolled were answered.
    @status_cases [
      {:pending, true},
      {:invite_sent, true},
      {:failed, true},
      {:registered, false},
      {:enrolled, false}
    ]

    for {status, outstanding?} <- @status_cases do
      verdict = if outstanding?, do: "listed", else: "excluded"

      test "#{status} invite is #{verdict}", %{provider: provider, program: program} do
        invite = invite(program, provider, %{status: unquote(status)})

        ids = provider.id |> Enrollment.list_outstanding_invites_for_provider() |> Enum.map(& &1.id)

        assert to_string(invite.id) in ids == unquote(outstanding?),
               "expected #{unquote(status)} invite to be #{unquote(verdict)}, got ids: #{inspect(ids)}"
      end
    end

    test "excludes another provider's invites", %{provider: provider, program: program} do
      other_provider = insert(:provider_profile_schema)
      other_program = insert(:program_schema, provider_id: other_provider.id)

      mine = invite(program, provider)
      theirs = invite(other_program, other_provider)

      ids = provider.id |> Enrollment.list_outstanding_invites_for_provider() |> Enum.map(& &1.id)

      assert to_string(mine.id) in ids
      refute to_string(theirs.id) in ids
    end

    test "carries the program title the invite row does not store", %{
      provider: provider,
      program: program
    } do
      invite(program, provider)

      assert [row] = Enrollment.list_outstanding_invites_for_provider(provider.id)
      assert row.program_title == "Chess Club"
      assert row.program_id == to_string(program.id)
    end

    test "returns the longest-unanswered invite first", %{provider: provider, program: program} do
      older = invite(program, provider, %{guardian_email: "older@test.com"})
      newer = invite(program, provider, %{guardian_email: "newer@test.com"})

      # create_invite/1 stamps second-granularity timestamps, so two invites made in
      # the same test tick are indistinguishable by insertion alone — age has to be
      # forced for the ordering assertion to mean anything.
      three_days_ago =
        DateTime.utc_now() |> DateTime.add(-3, :day) |> DateTime.truncate(:second)

      older
      |> Ecto.Changeset.change(%{inserted_at: three_days_ago})
      |> Repo.update!()

      assert [first, second] = Enrollment.list_outstanding_invites_for_provider(provider.id)
      assert first.id == to_string(older.id)
      assert second.id == to_string(newer.id)
    end

    test "aggregates across every program the provider runs", %{
      provider: provider,
      program: program
    } do
      second_program = insert(:program_schema, provider_id: provider.id, title: "Art Club")

      invite(program, provider)
      invite(second_program, provider)

      titles =
        provider.id
        |> Enrollment.list_outstanding_invites_for_provider()
        |> Enum.map(& &1.program_title)
        |> Enum.sort()

      assert titles == ["Art Club", "Chess Club"]
    end

    test "returns [] for a provider with no invites", %{provider: provider} do
      assert Enrollment.list_outstanding_invites_for_provider(provider.id) == []
    end

    # No test pins the nil-`program_title` branch: `bulk_enrollment_invites_program_id_fkey`
    # is RESTRICT, so a program holding invites cannot be deleted and the branch is
    # unreachable. It is still handled rather than asserted away — `get_titles/1` omits
    # unknown ids, so a title that ever goes missing costs the invite its program name
    # but never drops the row, which would hide work the provider still owes.

    test "excludes registered and enrolled while listing the rest", %{
      provider: provider,
      program: program
    } do
      for status <- [:pending, :invite_sent, :failed, :registered, :enrolled] do
        invite(program, provider, %{status: status, guardian_email: "#{status}@test.com"})
      end

      statuses =
        provider.id
        |> Enrollment.list_outstanding_invites_for_provider()
        |> Enum.map(& &1.status)
        |> Enum.sort()

      assert statuses == Enum.sort(BulkEnrollmentInvite.outstanding_statuses())
    end
  end
end
