defmodule KlassHero.Messaging.Domain.Models.Participant do
  @moduledoc """
  Pure domain entity representing a participant in a conversation.

  Tracks membership and read receipts for conversation participants.
  """

  alias KlassHero.Shared.Domain.Validation

  @enforce_keys [:id, :conversation_id, :user_id, :joined_at]

  defstruct [
    :id,
    :conversation_id,
    :user_id,
    :last_read_at,
    :joined_at,
    :left_at,
    :inserted_at,
    :updated_at
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          conversation_id: String.t(),
          user_id: String.t(),
          last_read_at: DateTime.t() | nil,
          joined_at: DateTime.t(),
          left_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @doc """
  Creates a new Participant with validation.

  Required:
  - id (UUID string)
  - conversation_id (UUID string)
  - user_id (UUID string)
  - joined_at (DateTime)

  Returns:
  - `{:ok, participant}` if valid
  - `{:error, [reasons]}` with list of validation errors
  """
  @spec new(map()) :: {:ok, t()} | {:error, [String.t()]}
  def new(attrs) when is_map(attrs) do
    attrs = Map.put_new(attrs, :joined_at, DateTime.utc_now())

    case build_struct(attrs) do
      {:ok, participant} ->
        case validate(participant) do
          [] -> {:ok, participant}
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

  @doc "Returns true if the participant is active (has joined and not left)"
  @spec active?(t()) :: boolean()
  def active?(%__MODULE__{left_at: nil}), do: true
  def active?(%__MODULE__{}), do: false

  @doc "Returns true if the participant has left the conversation"
  @spec left?(t()) :: boolean()
  def left?(%__MODULE__{left_at: nil}), do: false
  def left?(%__MODULE__{}), do: true

  @doc """
  Marks messages as read up to the given timestamp.

  Returns updated participant with last_read_at set.
  """
  @spec mark_as_read(t(), DateTime.t()) :: {:ok, t()}
  def mark_as_read(%__MODULE__{} = participant, read_at \\ DateTime.utc_now()) do
    {:ok, %{participant | last_read_at: read_at}}
  end

  @doc """
  Removes participant from conversation by setting left_at.
  """
  @spec leave(t(), DateTime.t()) :: {:ok, t()}
  def leave(%__MODULE__{} = participant, left_at \\ DateTime.utc_now()) do
    {:ok, %{participant | left_at: left_at}}
  end

  @doc """
  Checks if participant has unread messages based on the latest message timestamp.
  """
  @spec has_unread?(t(), DateTime.t() | nil) :: boolean()
  def has_unread?(%__MODULE__{last_read_at: nil}, nil), do: false
  def has_unread?(%__MODULE__{last_read_at: nil}, _latest_message_at), do: true

  def has_unread?(%__MODULE__{last_read_at: last_read_at}, latest_message_at) when not is_nil(latest_message_at) do
    DateTime.before?(last_read_at, latest_message_at)
  end

  def has_unread?(_, _), do: false

  defp validate(%__MODULE__{} = participant) do
    []
    |> Validation.validate_required_string(:id, participant.id)
    |> Validation.validate_required_string(:conversation_id, participant.conversation_id)
    |> Validation.validate_required_string(:user_id, participant.user_id)
    |> validate_datetime(:joined_at, participant.joined_at)
  end

  defp validate_datetime(errors, _field, %DateTime{}), do: errors
  defp validate_datetime(errors, field, _), do: ["#{field} must be a DateTime" | errors]
end
