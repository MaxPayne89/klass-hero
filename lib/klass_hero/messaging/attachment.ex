defmodule KlassHero.Messaging.Attachment do
  @moduledoc """
  Immutable image attachment on a message.

  Conventional Phoenix — the Ecto schema is the struct that flows through the
  `KlassHero.Messaging` context. Attachments are created once and never updated;
  deletion is handled by ON DELETE CASCADE from the messages table. The
  `create_changeset/2` is the single validation gatekeeper.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias KlassHero.Messaging.Message

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "message_attachments" do
    field :file_url, :string
    field :storage_path, :string
    field :original_filename, :string
    field :content_type, :string
    field :file_size_bytes, :integer

    belongs_to :message, Message

    timestamps()
  end

  @type t :: %__MODULE__{
          id: String.t(),
          message_id: String.t(),
          file_url: String.t(),
          storage_path: String.t() | nil,
          original_filename: String.t(),
          content_type: String.t(),
          file_size_bytes: pos_integer(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @allowed_content_types ~w(image/jpeg image/png image/gif image/webp)
  @max_file_size_bytes 10_485_760
  @max_per_message 5

  @required_fields ~w(message_id file_url storage_path original_filename content_type file_size_bytes)a

  @doc "Changeset for creating a new attachment (the single validation gatekeeper)."
  def create_changeset(schema \\ %__MODULE__{}, attrs) do
    schema
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:content_type, @allowed_content_types,
      message: "must be one of: #{Enum.join(@allowed_content_types, ", ")}"
    )
    |> validate_number(:file_size_bytes,
      greater_than: 0,
      less_than_or_equal_to: @max_file_size_bytes,
      message: "must be between 1 and #{@max_file_size_bytes}"
    )
    |> foreign_key_constraint(:message_id)
  end

  @doc "Allowed MIME content types for attachments."
  @spec allowed_content_types() :: [String.t()]
  def allowed_content_types, do: @allowed_content_types

  @doc "Maximum file size in bytes (10 MB)."
  @spec max_file_size_bytes() :: pos_integer()
  def max_file_size_bytes, do: @max_file_size_bytes

  @doc "Maximum number of attachments per message."
  @spec max_per_message() :: pos_integer()
  def max_per_message, do: @max_per_message
end
