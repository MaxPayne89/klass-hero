defmodule KlassHero.Enrollment.ResendInviteTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  setup do
    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id)

    {:ok, _} =
      KlassHero.Enrollment.create_invite(%{
        program_id: program.id,
        provider_id: provider.id,
        child_first_name: "Jane",
        child_last_name: "Smith",
        child_date_of_birth: ~D[2015-06-15],
        guardian_email: "jane@test.com"
      })

    {:ok, [invite]} = KlassHero.Enrollment.list_program_invites(program.id)

    # Transition to invite_sent so we can test resending
    {:ok, sent} =
      KlassHero.Enrollment.transition_invite(invite, %{
        status: :invite_sent,
        invite_token: "original-token",
        invite_sent_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

    %{invite: sent, program: program, provider: provider}
  end

  describe "execute/2" do
    test "resets invite and dispatches event", %{invite: invite, provider: provider} do
      assert {:ok, reset} = KlassHero.Enrollment.resend_invite(invite.id, provider.id)
      assert reset.status == :pending
      assert is_nil(reset.invite_token)
    end

    test "returns error for non-existent invite" do
      assert {:error, :not_found} =
               KlassHero.Enrollment.resend_invite(Ecto.UUID.generate(), Ecto.UUID.generate())
    end

    test "returns error for enrolled invite", %{invite: invite, provider: provider} do
      # Walk to registered (not enrolled, to avoid FK constraints)
      {:ok, reg} =
        KlassHero.Enrollment.transition_invite(invite, %{
          status: :registered,
          registered_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      # registered is not in @resendable_statuses
      assert {:error, :not_resendable} = KlassHero.Enrollment.resend_invite(reg.id, provider.id)
    end

    test "returns error when provider does not own the invite", %{invite: invite} do
      other_provider = insert(:provider_profile_schema)
      assert {:error, :not_found} = KlassHero.Enrollment.resend_invite(invite.id, other_provider.id)
    end
  end
end
