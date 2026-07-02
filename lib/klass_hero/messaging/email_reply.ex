defmodule KlassHero.Messaging.EmailReply do
  @moduledoc """
  A reply an admin sends to an inbound email, delivered via Swoosh/Resend.

  Conventional Phoenix — the Ecto schema is the struct that flows through the
  `KlassHero.Messaging` context; changesets are the single validation gatekeeper.
  `status` is an `Ecto.Enum` (`:sending → :sent | :failed`), loaded/dumped as an
  atom without a mapper.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias KlassHero.Accounts.User
  alias KlassHero.Messaging.InboundEmail

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "email_replies" do
    field :body, :string
    field :status, Ecto.Enum, values: [:sending, :sent, :failed], default: :sending
    field :resend_message_id, :string
    field :sent_at, :utc_datetime_usec
    field :inbound_email_id, :binary_id
    field :sent_by_id, :binary_id

    belongs_to :inbound_email, InboundEmail, foreign_key: :inbound_email_id, define_field: false
    belongs_to :sent_by, User, foreign_key: :sent_by_id, define_field: false

    timestamps()
  end

  @type status :: :sending | :sent | :failed

  @type t :: %__MODULE__{
          id: String.t(),
          inbound_email_id: String.t(),
          body: String.t(),
          sent_by_id: String.t(),
          status: status(),
          resend_message_id: String.t() | nil,
          sent_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @required_fields ~w(inbound_email_id body sent_by_id)a
  @optional_fields ~w(status resend_message_id sent_at)a

  @doc "Changeset for creating an email reply (defaults to :sending)."
  def create_changeset(schema \\ %__MODULE__{}, attrs) do
    schema
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:inbound_email_id)
    |> foreign_key_constraint(:sent_by_id)
  end

  @doc "Changeset for transitioning delivery status (:sent / :failed)."
  def status_changeset(schema, attrs) do
    schema
    |> cast(attrs, [:status, :resend_message_id, :sent_at])
    |> validate_required([:status])
  end
end
