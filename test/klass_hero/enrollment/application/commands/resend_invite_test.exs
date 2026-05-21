defmodule KlassHero.Enrollment.Application.Commands.ResendInviteTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Enrollment.Adapters.Driven.Persistence.Repositories.BulkEnrollmentInviteRepository
  alias KlassHero.Enrollment.Application.Commands.ResendInvite

  setup do
    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id)

    {:ok, _} =
      BulkEnrollmentInviteRepository.create_one(%{
        program_id: program.id,
        provider_id: provider.id,
        child_first_name: "Jane",
        child_last_name: "Smith",
        child_date_of_birth: ~D[2015-06-15],
        guardian_email: "jane@test.com"
      })

    [invite] = BulkEnrollmentInviteRepository.list_by_program(program.id)

    # Transition to invite_sent so we can test resending
    {:ok, sent} =
      BulkEnrollmentInviteRepository.transition_status(invite, %{
        status: :invite_sent,
        invite_token: "original-token",
        invite_sent_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

    %{invite: sent, program: program, provider: provider}
  end

  describe "execute/2" do
    test "resets invite and dispatches event", %{invite: invite, provider: provider} do
      assert {:ok, reset} = ResendInvite.execute(invite.id, provider.id)
      assert reset.status == :pending
      assert is_nil(reset.invite_token)
    end

    test "returns error for non-existent invite" do
      assert {:error, :not_found} =
               ResendInvite.execute(Ecto.UUID.generate(), Ecto.UUID.generate())
    end

    test "returns error for enrolled invite", %{invite: invite, provider: provider} do
      # Walk to registered (not enrolled, to avoid FK constraints)
      {:ok, reg} =
        BulkEnrollmentInviteRepository.transition_status(invite, %{
          status: :registered,
          registered_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      # registered is not in @resendable_statuses
      assert {:error, :not_resendable} = ResendInvite.execute(reg.id, provider.id)
    end

    test "returns error when provider does not own the invite", %{invite: invite} do
      other_provider = insert(:provider_profile_schema)
      assert {:error, :not_found} = ResendInvite.execute(invite.id, other_provider.id)
    end
  end
end
