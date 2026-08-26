defmodule KlassHero.Messaging.Conversation do
  @moduledoc """
  A messaging conversation: a direct 1-on-1 thread or a program broadcast.

  Conventional Phoenix — the Ecto schema is the struct that flows through the
  `KlassHero.Messaging` context; changesets are the single validation gatekeeper.
  `type` is an `Ecto.Enum`, so it loads/dumps as an atom without a mapper.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias KlassHero.Messaging.Message
  alias KlassHero.Messaging.Participant

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "conversations" do
    field :type, Ecto.Enum, values: [:direct, :program_broadcast]
    field :provider_id, :binary_id
    field :program_id, :binary_id

    # Identity, not membership. A :direct thread is between exactly these two;
    # staff seated by AddAssignedStaff are participants and never principals.
    # Stored ordered (a < b) so an unordered lookup is one indexed equality.
    field :principal_a_id, :binary_id
    field :principal_b_id, :binary_id
    field :subject, :string
    field :archived_at, :utc_datetime
    field :retention_until, :utc_datetime
    field :lock_version, :integer, default: 1

    # Virtual field populated by unread-count queries.
    field :unread_count, :integer, virtual: true, default: 0

    has_many :participants, Participant,
      foreign_key: :conversation_id,
      preload_order: [asc: :joined_at]

    has_many :messages, Message, foreign_key: :conversation_id

    timestamps()
  end

  @type conversation_type :: :direct | :program_broadcast

  @type t :: %__MODULE__{
          id: String.t(),
          type: conversation_type() | nil,
          provider_id: String.t(),
          program_id: String.t() | nil,
          principal_a_id: String.t() | nil,
          principal_b_id: String.t() | nil,
          subject: String.t() | nil,
          archived_at: DateTime.t() | nil,
          retention_until: DateTime.t() | nil,
          lock_version: integer(),
          unread_count: integer(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @required_fields ~w(type provider_id)a
  @optional_fields ~w(program_id subject archived_at retention_until lock_version
                      principal_a_id principal_b_id)a

  @doc """
  Attrs for a direct conversation between two people.

  Carries `:program_id` only when there is one — a direct thread may or may not
  hang off a program — and always carries the ordered principal pair, which is
  what identifies the thread.
  """
  @spec direct_attrs(String.t(), String.t() | nil, String.t(), String.t()) :: map()
  def direct_attrs(provider_id, program_id, user_id_1, user_id_2) do
    {a, b} = principal_pair(user_id_1, user_id_2)

    %{type: :direct, provider_id: provider_id, principal_a_id: a, principal_b_id: b}
    |> maybe_put_program(program_id)
  end

  defp maybe_put_program(attrs, nil), do: attrs
  defp maybe_put_program(attrs, program_id), do: Map.put(attrs, :program_id, program_id)

  @doc """
  Orders a pair of user ids so the same two people always yield the same key.

  Canonical-form uuids compare identically as strings and as Postgres `uuid`
  values, so this agrees with the `conversations_principals_ordered` check.
  """
  @spec principal_pair(String.t(), String.t()) :: {String.t(), String.t()}
  def principal_pair(user_id_1, user_id_2) when user_id_1 < user_id_2, do: {user_id_1, user_id_2}
  def principal_pair(user_id_1, user_id_2), do: {user_id_2, user_id_1}

  @doc "Changeset for creating a conversation."
  def create_changeset(schema \\ %__MODULE__{}, attrs) do
    schema
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_broadcast_program_id()
    |> validate_length(:subject, max: 500)
    |> unique_constraint([:program_id],
      name: :conversations_active_broadcast_per_program,
      message: "Active broadcast already exists for this program"
    )
    |> unique_constraint([:principal_a_id],
      name: :conversations_active_direct_per_pair,
      message: "A direct conversation between these two already exists"
    )
    |> foreign_key_constraint(:provider_id)
    |> foreign_key_constraint(:program_id)
    |> optimistic_lock(:lock_version)
  end

  defp validate_broadcast_program_id(changeset) do
    type = get_field(changeset, :type)
    program_id = get_field(changeset, :program_id)

    if type == :program_broadcast and is_nil(program_id) do
      add_error(changeset, :program_id, "is required for program broadcasts")
    else
      changeset
    end
  end
end
