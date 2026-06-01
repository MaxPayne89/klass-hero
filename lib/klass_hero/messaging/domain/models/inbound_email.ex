defmodule KlassHero.Messaging.Domain.Models.InboundEmail do
  @moduledoc """
  Pure domain entity for an inbound email received via Resend webhook.

  Supports status transitions: unread → read → archived, and unread ← read.
  """

  alias KlassHero.Shared.Domain.Validation

  @enforce_keys [:id, :resend_id, :from_address, :to_addresses, :subject, :received_at]

  defstruct [
    :id,
    :resend_id,
    :from_address,
    :from_name,
    :to_addresses,
    :cc_addresses,
    :subject,
    :body_html,
    :body_text,
    :headers,
    :message_id,
    :read_by_id,
    :read_at,
    :received_at,
    :inserted_at,
    :updated_at,
    status: :unread,
    content_status: :pending
  ]

  @type status :: :unread | :read | :archived

  @type t :: %__MODULE__{
          id: String.t(),
          resend_id: String.t(),
          from_address: String.t(),
          from_name: String.t() | nil,
          to_addresses: [String.t()],
          cc_addresses: [String.t()] | nil,
          subject: String.t(),
          body_html: String.t() | nil,
          body_text: String.t() | nil,
          headers: [map()] | nil,
          message_id: String.t() | nil,
          status: status(),
          content_status: :pending | :fetched | :failed,
          read_by_id: String.t() | nil,
          read_at: DateTime.t() | nil,
          received_at: DateTime.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @valid_statuses [:unread, :read, :archived]

  @doc """
  Creates a new InboundEmail with validation.

  Required fields: id, resend_id, from_address, to_addresses, subject, received_at.
  Optional: from_name, cc_addresses, body_html, body_text, headers.
  Status defaults to :unread.

  Returns {:ok, email} if valid, {:error, [reasons]} with validation error list.
  """
  @spec new(map()) :: {:ok, t()} | {:error, [String.t()]}
  def new(attrs) when is_map(attrs) do
    attrs = Map.put_new(attrs, :status, :unread)

    case build_struct(attrs) do
      {:ok, email} ->
        case validate(email) do
          [] -> {:ok, email}
          errors -> {:error, errors}
        end

      {:error, reason} ->
        {:error, [reason]}
    end
  end

  @doc """
  Marks the email as read by the given reader.

  # Trigger: email is already :read
  # Why: idempotent — preserve the original reader_id and read_at timestamp
  # Outcome: returns the email unchanged
  """
  @spec mark_read(t(), String.t()) :: {:ok, t()}
  def mark_read(%__MODULE__{status: :read} = email, _reader_id), do: {:ok, email}
  def mark_read(%__MODULE__{status: :archived} = email, _reader_id), do: {:ok, email}

  def mark_read(%__MODULE__{} = email, reader_id) do
    {:ok, %{email | status: :read, read_by_id: reader_id, read_at: DateTime.utc_now()}}
  end

  @doc "Transitions the email back to :unread, clearing reader metadata."
  @spec mark_unread(t()) :: {:ok, t()}
  def mark_unread(%__MODULE__{} = email) do
    {:ok, %{email | status: :unread, read_by_id: nil, read_at: nil}}
  end

  @doc "Archives the email regardless of current status."
  @spec archive(t()) :: {:ok, t()}
  def archive(%__MODULE__{} = email) do
    {:ok, %{email | status: :archived}}
  end

  @doc "Resets content_status to :pending for retry."
  @spec reset_content_status(t()) :: t()
  def reset_content_status(%__MODULE__{} = email), do: %{email | content_status: :pending}

  @doc "Returns true if the email has not been read."
  @spec unread?(t()) :: boolean()
  def unread?(%__MODULE__{status: :unread}), do: true
  def unread?(%__MODULE__{}), do: false

  defp build_struct(attrs) do
    {:ok, struct!(__MODULE__, attrs)}
  rescue
    ArgumentError -> {:error, "Missing required fields"}
  end

  defp validate(%__MODULE__{} = email) do
    []
    |> Validation.validate_required_string(:id, email.id)
    |> validate_present(:resend_id, email.resend_id)
    |> validate_present(:from_address, email.from_address)
    |> validate_present(:subject, email.subject)
    |> validate_list(:to_addresses, email.to_addresses)
    |> validate_status(email.status)
  end

  defp validate_present(errors, field, value) when is_binary(value) do
    if String.trim(value) == "",
      do: ["#{field} cannot be empty" | errors],
      else: errors
  end

  defp validate_present(errors, field, _), do: ["#{field} must be a string" | errors]

  defp validate_list(errors, _field, value) when is_list(value) and value != [], do: errors

  defp validate_list(errors, field, _), do: ["#{field} must be a non-empty list" | errors]

  defp validate_status(errors, status) when status in @valid_statuses, do: errors

  defp validate_status(errors, _) do
    valid = @valid_statuses |> Enum.map_join(", ", &to_string/1)
    ["status must be one of: #{valid}" | errors]
  end
end
