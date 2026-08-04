defmodule KlassHero.Provider.SessionStats do
  @moduledoc """
  Read model for per-program completed-session counts — the
  `provider_session_stats` table.

  Conventional Phoenix read side: the Ecto schema *is* the display DTO. It is
  write-only from the projection's perspective (`ProviderSessionStats` maintains
  it from Participation events) and read-only from the context's perspective. No
  changeset — the projection controls all writes.

  Denormalized per `{provider_id, program_id}` so the dashboard's total-session
  count is a single aggregate rather than a cross-context roll-up.
  """

  use Ecto.Schema
  use KlassHero.Shared.ReadTable

  @primary_key {:id, :binary_id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "provider_session_stats" do
    field :provider_id, :binary_id
    field :program_id, :binary_id
    field :program_title, :string
    field :sessions_completed_count, :integer, default: 0

    timestamps()
  end

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          provider_id: Ecto.UUID.t() | nil,
          program_id: Ecto.UUID.t() | nil,
          program_title: String.t() | nil,
          sessions_completed_count: non_neg_integer(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }
end
