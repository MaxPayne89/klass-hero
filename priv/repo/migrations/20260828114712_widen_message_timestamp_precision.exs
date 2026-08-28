defmodule KlassHero.Repo.Migrations.WidenMessageTimestampPrecision do
  @moduledoc """
  Gives the unread comparison a total order.

  Every unread read in Messaging is `messages.inserted_at > participants.last_read_at`,
  and both columns were `timestamp(0)`. Two messages in the same second are therefore
  indistinguishable, which has three consequences: the inbox previews whichever of them
  has the higher *random* UUID; a message arriving in the same second a participant is
  seated is never counted; and neither is one arriving in the second they read the
  thread. Message ids are `binary_id`, so there is no tiebreak to fall back on.

  None of this was visible while the badge came from `conversation_summaries`, whose
  counter was incremented per event and never compared timestamps at all. Reading the
  same fact live (ADR-0023) requires the ordering to be real.

  Scope is exactly the two sides of that comparison. `conversation_participants`'
  `joined_at`, `left_at` and row timestamps stay at `timestamp(0)` — nothing compares
  them to a message — as do `messages.deleted_at` and every column on `conversations`.
  """

  use Ecto.Migration

  def up do
    alter table(:messages) do
      modify :inserted_at, :utc_datetime_usec
      modify :updated_at, :utc_datetime_usec
    end

    alter table(:conversation_participants) do
      modify :last_read_at, :utc_datetime_usec
    end
  end

  def down do
    alter table(:messages) do
      modify :inserted_at, :utc_datetime
      modify :updated_at, :utc_datetime
    end

    alter table(:conversation_participants) do
      modify :last_read_at, :utc_datetime
    end
  end
end
