defmodule KlassHero.Messaging.Domain.Models.Conversation do
  @moduledoc """
  Pure domain entity representing a conversation in the Messaging bounded context.

  Supports two types of conversations:
  - `:direct` - 1-on-1 conversation between a provider and a parent
  - `:program_broadcast` - Broadcast from provider to all enrolled parents

  ## Lifecycle

  Active → Archived (soft delete) → Hard deleted (after retention period)

  Archiving happens when a program ends. Retention policy then controls
  when the conversation data is permanently deleted.
  """

  alias KlassHero.Messaging.Domain.Models.Message
  alias KlassHero.Messaging.Participant
  alias KlassHero.Shared.Domain.Validation

  @enforce_keys [:id, :type, :provider_id]

  defstruct [
    :id,
    :type,
    :provider_id,
    :program_id,
    :subject,
    :archived_at,
    :retention_until,
    :lock_version,
    :inserted_at,
    :updated_at,
    participants: [],
    messages: []
  ]

  @type conversation_type :: :direct | :program_broadcast

  @type t :: %__MODULE__{
          id: String.t(),
          type: conversation_type(),
          provider_id: String.t(),
          program_id: String.t() | nil,
          subject: String.t() | nil,
          archived_at: DateTime.t() | nil,
          retention_until: DateTime.t() | nil,
          lock_version: integer(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil,
          participants: [Participant.t()],
          messages: [Message.t()]
        }

  @valid_types [:direct, :program_broadcast]

  @doc """
  Creates a new Conversation with validation.

  Required:
  - id (UUID string)
  - type (:direct or :program_broadcast)
  - provider_id (UUID string)

  Optional:
  - program_id (required for :program_broadcast type)
  - subject (for broadcasts)

  Returns:
  - `{:ok, conversation}` if valid
  - `{:error, [reasons]}` with list of validation errors
  """
  @spec new(map()) :: {:ok, t()} | {:error, [String.t()]}
  def new(attrs) when is_map(attrs) do
    attrs =
      attrs
      |> Map.put_new(:lock_version, 1)
      |> Map.put_new(:participants, [])
      |> Map.put_new(:messages, [])

    case build_struct(attrs) do
      {:ok, conversation} ->
        case validate(conversation) do
          [] -> {:ok, conversation}
          errors -> {:error, errors}
        end

      {:error, reason} ->
        {:error, [reason]}
    end
  end

  defp build_struct(attrs) do
    {:ok, struct!(__MODULE__, attrs)}
  rescue
    ArgumentError -> {:error, "Missing required fields"}
  end

  @doc "Returns true if the conversation is a direct message"
  @spec direct?(t()) :: boolean()
  def direct?(%__MODULE__{type: :direct}), do: true
  def direct?(%__MODULE__{}), do: false

  @doc "Returns true if the conversation is a program broadcast"
  @spec broadcast?(t()) :: boolean()
  def broadcast?(%__MODULE__{type: :program_broadcast}), do: true
  def broadcast?(%__MODULE__{}), do: false

  @doc "Returns true if the conversation is archived"
  @spec archived?(t()) :: boolean()
  def archived?(%__MODULE__{archived_at: nil}), do: false
  def archived?(%__MODULE__{archived_at: _}), do: true

  @doc "Returns true if the conversation is active (not archived)"
  @spec active?(t()) :: boolean()
  def active?(conversation), do: not archived?(conversation)

  @doc """
  Archives the conversation, setting archived_at and retention_until.

  Retention is set to 30 days after archiving by default.
  """
  @spec archive(t(), DateTime.t()) :: {:ok, t()}
  def archive(%__MODULE__{} = conversation, now \\ DateTime.utc_now()) do
    retention_until = DateTime.add(now, 30, :day)

    {:ok,
     %{
       conversation
       | archived_at: now,
         retention_until: retention_until,
         lock_version: conversation.lock_version + 1
     }}
  end

  @doc "Returns valid conversation types"
  @spec valid_types() :: [conversation_type()]
  def valid_types, do: @valid_types

  defp validate(%__MODULE__{} = conversation) do
    []
    |> Validation.validate_required_string(:id, conversation.id)
    |> Validation.validate_required_string(:provider_id, conversation.provider_id)
    |> validate_type(conversation.type)
    |> validate_program_id(conversation)
  end

  defp validate_type(errors, type) when type in @valid_types, do: errors

  defp validate_type(errors, _) do
    valid = @valid_types |> Enum.map_join(", ", &to_string/1)
    ["type must be one of: #{valid}" | errors]
  end

  defp validate_program_id(errors, %{type: :program_broadcast, program_id: nil}) do
    ["program_id is required for program_broadcast conversations" | errors]
  end

  defp validate_program_id(errors, _), do: errors
end
