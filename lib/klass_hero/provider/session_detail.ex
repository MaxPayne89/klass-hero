defmodule KlassHero.Provider.SessionDetail do
  @moduledoc """
  Read model for the provider dashboard's per-session view — the
  `provider_session_details` table (issue #373).

  Conventional Phoenix read side: the Ecto schema *is* the display DTO. It is
  write-only from the projection's perspective (`ProviderSessionDetails`
  maintains it from Participation + Provider events) and read-only from the
  context's perspective. No changeset — the projection controls all writes.

  Staff names and counts are denormalized here at projection time so the
  dashboard renders a session without joining across contexts.
  """

  use Ecto.Schema

  @primary_key {:session_id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "provider_session_details" do
    field :program_id, :binary_id
    field :program_title, :string
    field :provider_id, :binary_id

    field :session_date, :date
    field :start_time, :time
    field :end_time, :time
    field :status, Ecto.Enum, values: [:scheduled, :in_progress, :completed, :cancelled]

    field :current_assigned_staff_id, :binary_id
    field :current_assigned_staff_name, :string
    field :cover_staff_id, :binary_id
    field :cover_staff_name, :string

    field :checked_in_count, :integer, default: 0
    field :total_count, :integer, default: 0

    timestamps()
  end

  @type status :: :scheduled | :in_progress | :completed | :cancelled

  @type t :: %__MODULE__{
          session_id: Ecto.UUID.t() | nil,
          program_id: Ecto.UUID.t() | nil,
          program_title: String.t() | nil,
          provider_id: Ecto.UUID.t() | nil,
          session_date: Date.t() | nil,
          start_time: Time.t() | nil,
          end_time: Time.t() | nil,
          status: status() | nil,
          current_assigned_staff_id: Ecto.UUID.t() | nil,
          current_assigned_staff_name: String.t() | nil,
          cover_staff_id: Ecto.UUID.t() | nil,
          cover_staff_name: String.t() | nil,
          checked_in_count: non_neg_integer(),
          total_count: non_neg_integer(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }
end
