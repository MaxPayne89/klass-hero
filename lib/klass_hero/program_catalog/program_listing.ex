defmodule KlassHero.ProgramCatalog.ProgramListing do
  @moduledoc """
  Read model for program listings — the denormalized `program_listings` table.

  Conventional Phoenix read side: the Ecto schema *is* the display DTO. It is
  write-only from the projection's perspective (`ProgramListings` maintains it
  from program events) and read-only from the context's perspective. No
  user-facing changeset — the projection controls all writes.

  Provider facts are deliberately absent: surfaces needing a provider's name or
  vetting state read Provider's facade per render (`KlassHeroWeb.Helpers.ProviderDisplay`)
  rather than having them denormalised here (#1195).
  """

  use Ecto.Schema
  use KlassHero.Shared.ReadTable

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "program_listings" do
    field :title, :string
    field :description, :string
    field :category, :string
    field :age_range, :string
    field :price, :decimal
    field :pricing_period, :string
    field :location, :string
    field :cover_image_url, :string
    field :start_date, :date
    field :end_date, :date
    field :meeting_days, {:array, :string}, default: []
    field :meeting_start_time, :time
    field :meeting_end_time, :time
    field :season, :string
    field :registration_start_date, :date
    field :registration_end_date, :date
    field :provider_id, :binary_id

    timestamps()
  end

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          title: String.t() | nil,
          description: String.t() | nil,
          category: String.t() | nil,
          age_range: String.t() | nil,
          price: Decimal.t() | nil,
          pricing_period: String.t() | nil,
          location: String.t() | nil,
          cover_image_url: String.t() | nil,
          start_date: Date.t() | nil,
          end_date: Date.t() | nil,
          meeting_days: [String.t()],
          meeting_start_time: Time.t() | nil,
          meeting_end_time: Time.t() | nil,
          season: String.t() | nil,
          registration_start_date: Date.t() | nil,
          registration_end_date: Date.t() | nil,
          provider_id: Ecto.UUID.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }
end
