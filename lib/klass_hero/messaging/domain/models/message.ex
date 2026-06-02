defmodule KlassHero.Messaging.Domain.Models.Message do
  @moduledoc """
  Pure domain entity representing a message in the Messaging bounded context.

  Supports two message types:
  - `:text` - Regular user message
  - `:system` - System-generated message (e.g., "User joined conversation")

  A message must have non-empty `content` or at least one attachment.
  Content is optional when attachments are present.
  """

  alias KlassHero.Messaging.Domain.Models.Attachment
  alias KlassHero.Shared.Domain.Validation

  @enforce_keys [:id, :conversation_id, :sender_id]

  defstruct [
    :id,
    :conversation_id,
    :sender_id,
    :content,
    :deleted_at,
    :inserted_at,
    :updated_at,
    message_type: :text,
    attachments: []
  ]

  @type message_type :: :text | :system

  @type t :: %__MODULE__{
          id: String.t(),
          conversation_id: String.t(),
          sender_id: String.t(),
          content: String.t() | nil,
          message_type: message_type(),
          attachments: [Attachment.t()],
          deleted_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @valid_message_types [:text, :system]
  @max_content_length 10_000
  @max_attachments 5

  @doc """
  Creates a new Message with validation.

  Required:
  - id (UUID string)
  - conversation_id (UUID string)
  - sender_id (UUID string)

  Content or attachments:
  - content (string, max 10,000 chars) - optional when attachments present
  - attachments (list of Attachment structs, max #{@max_attachments}) - defaults to `[]`

  A message must have non-empty content or at least one attachment.

  Optional:
  - message_type (:text or :system, defaults to :text)

  Returns:
  - `{:ok, message}` if valid
  - `{:error, [reasons]}` with list of validation errors
  """
  @spec new(map()) :: {:ok, t()} | {:error, [String.t()]}
  def new(attrs) when is_map(attrs) do
    attrs =
      attrs
      |> Map.put_new(:message_type, :text)
      |> Map.put_new(:attachments, [])

    case build_struct(attrs) do
      {:ok, message} ->
        case validate(message) do
          [] -> {:ok, message}
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

  @doc "Returns true if the message is a text message"
  @spec text?(t()) :: boolean()
  def text?(%__MODULE__{message_type: :text}), do: true
  def text?(%__MODULE__{}), do: false

  @doc "Returns true if the message is a system message"
  @spec system?(t()) :: boolean()
  def system?(%__MODULE__{message_type: :system}), do: true
  def system?(%__MODULE__{}), do: false

  @doc "Returns true if the message is deleted"
  @spec deleted?(t()) :: boolean()
  def deleted?(%__MODULE__{deleted_at: nil}), do: false
  def deleted?(%__MODULE__{deleted_at: _}), do: true

  @doc "Soft deletes the message"
  @spec delete(t(), DateTime.t()) :: {:ok, t()}
  def delete(%__MODULE__{} = message, now \\ DateTime.utc_now()) do
    {:ok, %{message | deleted_at: now}}
  end

  @doc "Returns valid message types"
  @spec valid_message_types() :: [message_type()]
  def valid_message_types, do: @valid_message_types

  defp validate(%__MODULE__{} = message) do
    []
    |> Validation.validate_required_string(:id, message.id)
    |> Validation.validate_required_string(:conversation_id, message.conversation_id)
    |> Validation.validate_required_string(:sender_id, message.sender_id)
    |> validate_content(message.content, message.attachments)
    |> validate_message_type(message.message_type)
    |> validate_attachments_count(message.attachments)
  end

  defp validate_content(errors, content, attachments) when is_binary(content) do
    trimmed = String.trim(content)

    cond do
      trimmed == "" and attachments == [] ->
        ["content cannot be empty" | errors]

      trimmed == "" ->
        errors

      String.length(content) > @max_content_length ->
        ["content cannot exceed #{@max_content_length} characters" | errors]

      true ->
        errors
    end
  end

  defp validate_content(errors, nil, []), do: ["message must have content or attachments" | errors]

  defp validate_content(errors, nil, _attachments), do: errors
  defp validate_content(errors, _, _), do: ["content must be a string or nil" | errors]

  defp validate_attachments_count(errors, attachments) when length(attachments) > @max_attachments do
    ["attachments cannot exceed #{@max_attachments} per message" | errors]
  end

  defp validate_attachments_count(errors, _attachments), do: errors

  defp validate_message_type(errors, type) when type in @valid_message_types, do: errors

  defp validate_message_type(errors, _) do
    valid = @valid_message_types |> Enum.map_join(", ", &to_string/1)
    ["message_type must be one of: #{valid}" | errors]
  end
end
