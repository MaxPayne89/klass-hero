defmodule KlassHero.Enrollment.EnqueueInviteEmailsTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Enrollment.BulkEnrollmentInvite
  alias KlassHero.Enrollment.EnqueueInviteEmails
  alias KlassHero.Repo

  defp create_pending_invites(_context) do
    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id, title: "Dance Class")

    rows = [
      %{
        program_id: program.id,
        provider_id: provider.id,
        child_first_name: "Emma",
        child_last_name: "Schmidt",
        child_date_of_birth: ~D[2016-03-15],
        guardian_email: "parent@example.com",
        guardian_first_name: "Hans"
      },
      %{
        program_id: program.id,
        provider_id: provider.id,
        child_first_name: "Liam",
        child_last_name: "Mueller",
        child_date_of_birth: ~D[2017-01-10],
        guardian_email: "other@example.com",
        guardian_first_name: "Maria"
      }
    ]

    Enum.each(rows, fn attrs ->
      {:ok, _} = KlassHero.Enrollment.create_invite(attrs)
    end)

    %{provider: provider, program: program}
  end

  describe "execute/2" do
    setup :create_pending_invites

    test "returns {:ok, []} when no pending invites exist", %{
      provider: provider,
      program: program
    } do
      Repo.update_all(BulkEnrollmentInvite, set: [status: :failed, error_details: "test"])

      assert {:ok, []} = EnqueueInviteEmails.execute([program.id], provider.id)
    end

    test "returns pairs with correct length and shape", %{
      provider: provider,
      program: program
    } do
      assert {:ok, pairs} = EnqueueInviteEmails.execute([program.id], provider.id)

      assert length(pairs) == 2
      assert Enum.all?(pairs, fn {id, name} -> is_binary(id) and is_binary(name) end)
    end

    test "assigns unique tokens to all invites in DB", %{
      provider: provider,
      program: program
    } do
      {:ok, _pairs} = EnqueueInviteEmails.execute([program.id], provider.id)

      invites = Repo.all(BulkEnrollmentInvite)
      tokens = Enum.map(invites, & &1.invite_token)

      assert Enum.all?(tokens, &(not is_nil(&1)))
      assert length(Enum.uniq(tokens)) == 2
    end

    test "resolves program name correctly", %{provider: provider, program: program} do
      assert {:ok, pairs} = EnqueueInviteEmails.execute([program.id], provider.id)

      assert Enum.all?(pairs, fn {_id, name} -> name == "Dance Class" end)
    end

    test "falls back to 'Program' when program not in catalog", %{provider: provider} do
      # Trigger: invite has a program_id belonging to a different provider
      # Why: ACL only returns programs for the queried provider
      # Outcome: use case falls back to generic "Program" label
      other_provider = insert(:provider_profile_schema)
      orphan_program = insert(:program_schema, provider_id: other_provider.id, title: "Other")

      {:ok, _} =
        KlassHero.Enrollment.create_invite(%{
          program_id: orphan_program.id,
          provider_id: provider.id,
          child_first_name: "Orphan",
          child_last_name: "Child",
          child_date_of_birth: ~D[2016-01-01],
          guardian_email: "orphan@example.com"
        })

      # Move existing invites to non-pending so only the orphan gets picked up
      from(s in BulkEnrollmentInvite,
        where: s.program_id != ^orphan_program.id
      )
      |> Repo.update_all(set: [status: :failed, error_details: "test"])

      assert {:ok, [{_id, "Program"}]} =
               EnqueueInviteEmails.execute([orphan_program.id], provider.id)
    end

    test "second call returns {:ok, []} (idempotent)", %{
      provider: provider,
      program: program
    } do
      {:ok, pairs} = EnqueueInviteEmails.execute([program.id], provider.id)
      assert length(pairs) == 2

      assert {:ok, []} = EnqueueInviteEmails.execute([program.id], provider.id)
    end
  end
end
