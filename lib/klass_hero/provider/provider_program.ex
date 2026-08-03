defmodule KlassHero.Provider.ProviderProgram do
  @moduledoc """
  Read model for a provider's programs — the `provider_programs` table.

  Conventional Phoenix read side: the Ecto schema *is* the display DTO. It is
  write-only from the projection's perspective (`ProviderPrograms` maintains it
  from Program Catalog events) and read-only from the context's perspective. No
  changeset — the projection controls all writes.

  Mirrors program ownership + display metadata so Provider's list and display
  reads need no cross-context call. Not an authorization source: being
  event-driven it is eventually consistent, so write-path ownership guards read
  `ProgramCatalog` directly instead (see `KlassHero.Provider.Assignments`).
  """

  use Ecto.Schema

  @primary_key {:program_id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "provider_programs" do
    field :provider_id, :binary_id
    field :name, :string

    timestamps()
  end

  @type t :: %__MODULE__{
          program_id: Ecto.UUID.t() | nil,
          provider_id: Ecto.UUID.t() | nil,
          name: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }
end
