defmodule KlassHero.Messaging.InboundEmail do
  @moduledoc """
  An email received from a parent via the Resend inbound webhook.

  Conventional Phoenix — the Ecto schema is the struct that flows through the
  `KlassHero.Messaging` context; changesets are the single validation gatekeeper.
  `status` and `content_status` are `Ecto.Enum`s, so they load/dump as atoms
  without a mapper.

  Ingestion is two-phase: the webhook delivers metadata (`content_status:
  :pending`); `FetchEmailContentWorker` later fills body/headers via the Resend
  API and flips `content_status` to `:fetched` or `:failed`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "inbound_emails" do
    field :resend_id, :string
    field :from_address, :string
    field :from_name, :string
    field :to_addresses, {:array, :string}, default: []
    field :cc_addresses, {:array, :string}, default: []
    field :subject, :string
    field :body_html, :string
    field :body_text, :string
    field :headers, {:array, :map}, default: []
    field :message_id, :string
    field :status, Ecto.Enum, values: [:unread, :read, :archived], default: :unread
    field :content_status, Ecto.Enum, values: [:pending, :fetched, :failed], default: :pending
    field :read_by_id, :binary_id
    field :read_at, :utc_datetime_usec
    field :received_at, :utc_datetime_usec

    timestamps()
  end

  @type status :: :unread | :read | :archived
  @type content_status :: :pending | :fetched | :failed

  @type t :: %__MODULE__{
          id: String.t(),
          resend_id: String.t(),
          from_address: String.t(),
          from_name: String.t() | nil,
          to_addresses: [String.t()],
          cc_addresses: [String.t()],
          subject: String.t(),
          body_html: String.t() | nil,
          body_text: String.t() | nil,
          headers: [map()],
          message_id: String.t() | nil,
          status: status(),
          content_status: content_status(),
          read_by_id: String.t() | nil,
          read_at: DateTime.t() | nil,
          received_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @required_fields ~w(resend_id from_address to_addresses subject received_at)a
  @optional_fields ~w(from_name cc_addresses body_html body_text headers status message_id content_status)a
  @content_fields ~w(body_html body_text headers content_status)a

  @doc "Changeset for storing a newly received inbound email."
  def create_changeset(schema \\ %__MODULE__{}, attrs) do
    schema
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:resend_id)
    |> foreign_key_constraint(:read_by_id)
  end

  @doc "Changeset for updating read/archive status."
  def status_changeset(schema, attrs) do
    schema
    |> cast(attrs, [:status, :read_by_id, :read_at])
    |> validate_required([:status])
  end

  @doc "Changeset for filling in fetched content (body, headers, content_status)."
  def content_changeset(schema, attrs) do
    schema
    |> cast(attrs, @content_fields)
    |> validate_required([:content_status])
    |> validate_content_status_transition()
  end

  # `:fetched` is absorbing. Marking a fetch permanently failed is replayable — by the
  # sweep over discarded jobs, and by a Lifeline duplicate racing the original — and a
  # replay must not bury content that was in fact fetched under `content_status:
  # :failed`, which would leave body_html populated next to a status saying it is not.
  # Only that one edge is closed; `:failed -> :fetched` stays open so a later successful
  # fetch still heals the row.
  defp validate_content_status_transition(changeset) do
    case {changeset.data.content_status, get_change(changeset, :content_status)} do
      {:fetched, target} when target not in [nil, :fetched] ->
        add_error(changeset, :content_status, "cannot transition from fetched to #{target}",
          validation: :content_status_transition,
          from: :fetched,
          to: target
        )

      _unchanged_or_permitted ->
        changeset
    end
  end
end
