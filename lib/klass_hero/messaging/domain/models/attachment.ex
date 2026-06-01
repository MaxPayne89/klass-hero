defmodule KlassHero.Messaging.Domain.Models.Attachment do
  @moduledoc """
  Pure domain entity representing a file attachment on a message.

  Currently restricted to image types. The allowed content types list
  can be extended to support other file types in the future.
  """

  alias KlassHero.Shared.Domain.Validation

  @enforce_keys [:id, :message_id, :file_url, :original_filename, :content_type, :file_size_bytes]

  defstruct [
    :id,
    :message_id,
    :file_url,
    :original_filename,
    :content_type,
    :file_size_bytes,
    :inserted_at,
    :updated_at
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          message_id: String.t(),
          file_url: String.t(),
          original_filename: String.t(),
          content_type: String.t(),
          file_size_bytes: pos_integer(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @allowed_content_types ~w(image/jpeg image/png image/gif image/webp)
  @max_file_size_bytes 10_485_760
  @max_per_message 5

  @doc """
  Creates a new Attachment with validation.

  Required:
  - id (UUID string)
  - message_id (UUID string)
  - file_url (non-empty string)
  - original_filename (non-empty string)
  - content_type (one of #{inspect(@allowed_content_types)})
  - file_size_bytes (integer between 1 and #{@max_file_size_bytes})

  Returns:
  - `{:ok, attachment}` if valid
  - `{:error, [reasons]}` with list of validation errors
  """
  @spec new(map()) :: {:ok, t()} | {:error, [String.t()]}
  def new(attrs) when is_map(attrs) do
    case build_struct(attrs) do
      {:ok, attachment} ->
        case validate(attachment) do
          [] -> {:ok, attachment}
          errors -> {:error, errors}
        end

      {:error, reason} ->
        {:error, [reason]}
    end
  end

  @doc "Returns the list of allowed MIME content types for attachments."
  @spec allowed_content_types() :: [String.t()]
  def allowed_content_types, do: @allowed_content_types

  @doc "Returns the maximum file size in bytes (10 MB)."
  @spec max_file_size_bytes() :: pos_integer()
  def max_file_size_bytes, do: @max_file_size_bytes

  @doc "Returns the maximum number of attachments per message."
  @spec max_per_message() :: pos_integer()
  def max_per_message, do: @max_per_message

  defp build_struct(attrs) do
    {:ok, struct!(__MODULE__, attrs)}
  rescue
    ArgumentError -> {:error, "Missing required fields"}
  end

  defp validate(%__MODULE__{} = attachment) do
    []
    |> Validation.validate_required_string(:id, attachment.id)
    |> Validation.validate_required_string(:message_id, attachment.message_id)
    |> Validation.validate_required_string(:file_url, attachment.file_url)
    |> Validation.validate_required_string(:original_filename, attachment.original_filename)
    |> validate_content_type(attachment.content_type)
    |> validate_file_size(attachment.file_size_bytes)
  end

  defp validate_content_type(errors, type) when type in @allowed_content_types, do: errors

  defp validate_content_type(errors, _type) do
    allowed = Enum.join(@allowed_content_types, ", ")
    ["content_type must be one of: #{allowed}" | errors]
  end

  defp validate_file_size(errors, size) when is_integer(size) and size > 0 and size <= @max_file_size_bytes do
    errors
  end

  defp validate_file_size(errors, _size) do
    ["file_size_bytes must be between 1 and #{@max_file_size_bytes}" | errors]
  end
end
