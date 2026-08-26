defmodule KlassHero.Repo.Migrations.AddPrincipalPairToConversations do
  use Ecto.Migration

  alias KlassHero.Release.BackfillDirectConversationPrincipals

  @moduledoc """
  Makes "the thread between these two people" a stored fact on `:direct`
  conversations (#747, #1521).

  `conversation_participants` keeps membership — owner, parent, and any staff
  seated by `AddAssignedStaff` — while the principal pair carries identity. That
  separation is what lets an owner and a staff member each hold their own thread
  with the same parent, and lets a provider↔staff thread exist at all.

  The pair is stored ordered (a < b) so an unordered lookup is one indexed
  equality check, and so the partial unique index below is the first constraint
  this table has ever had on `:direct` rows — find-or-create was racy until now.

  Backfill runs before the index, in BackfillDirectConversationPrincipals so the
  transform is unit-tested. Deliberately NO "direct rows must have principals"
  check constraint yet: it would fail the deploy on the first unresolved row, and
  belongs in a follow-up once a clean backfill is confirmed in production.
  """

  def up do
    alter table(:conversations) do
      add :principal_a_id, references(:users, type: :binary_id, on_delete: :restrict)
      add :principal_b_id, references(:users, type: :binary_id, on_delete: :restrict)
    end

    # The backfill reads these columns, so it cannot run in the same DDL statement.
    flush()

    {:ok, _counts} = BackfillDirectConversationPrincipals.run(repo())

    # a < b implies a <> b, so no separate distinctness check is needed.
    create constraint(:conversations, :conversations_principals_ordered,
             check:
               "principal_a_id IS NULL OR principal_b_id IS NULL OR principal_a_id < principal_b_id"
           )

    create unique_index(:conversations, [:provider_id, :principal_a_id, :principal_b_id],
             where: "type = 'direct' AND archived_at IS NULL",
             name: :conversations_active_direct_per_pair
           )
  end

  def down do
    drop index(:conversations, [:provider_id, :principal_a_id, :principal_b_id],
           name: :conversations_active_direct_per_pair
         )

    drop constraint(:conversations, :conversations_principals_ordered)

    alter table(:conversations) do
      remove :principal_a_id
      remove :principal_b_id
    end
  end
end
