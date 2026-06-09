defmodule KlassHero.Repo.Migrations.CleanupLegacyStaffInviteProfiles do
  @moduledoc """
  Blanket cleanup of the legacy staff→provider conflation (ADR-0005, #966).

  Deletes every `ProviderProfile` with `originated_from = "staff_invite"` and strips
  `:provider` from the owning users (they revert to staff-only; #968 lets them re-upgrade
  deliberately). The transform — and the count logging that precedes the destructive step
  (HITL gate) — lives in `KlassHero.Release.CleanupLegacyStaffInviteProfiles.run/1`, which
  is unit-tested directly.

  Runs after `20260608000001_rename_staff_provider_role_to_staff` — both touch
  `users.intended_roles`.

  Irreversible: deleted profiles cannot be reconstructed, so `down/0` is a no-op. Affected
  users keep `:staff` and re-acquire provider-hood only by deliberate registration.
  """
  use Ecto.Migration

  def up do
    {:ok, _counts} = KlassHero.Release.CleanupLegacyStaffInviteProfiles.run(repo())
  end

  def down do
    :ok
  end
end
