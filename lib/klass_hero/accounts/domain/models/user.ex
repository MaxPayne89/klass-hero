defmodule KlassHero.Accounts.Domain.Models.User do
  @moduledoc """
  User domain entity. Pure domain model — excludes auth infrastructure fields
  (password, hashed_password, authenticated_at) which live on the Ecto schema only.
  """

  @enforce_keys [:id, :email, :name]
  defstruct [
    :id,
    :email,
    :name,
    :avatar,
    :confirmed_at,
    :locale,
    :inserted_at,
    :updated_at,
    is_admin: false,
    intended_roles: []
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          email: String.t(),
          name: String.t(),
          avatar: String.t() | nil,
          confirmed_at: DateTime.t() | nil,
          is_admin: boolean(),
          locale: String.t() | nil,
          intended_roles: [atom()],
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @doc """
  Creates a new User with business validation.

  Returns `{:ok, user}` or `{:error, [reasons]}`.
  """
  def new(attrs) when is_map(attrs) do
    # Validate before struct!/2 to get field-level errors instead of a generic ArgumentError
    errors =
      []
      |> validate_id(attrs[:id])
      |> validate_email(attrs[:email])
      |> validate_name(attrs[:name])

    case errors do
      [] ->
        {:ok, struct!(__MODULE__, attrs)}

      errors ->
        {:error, errors}
    end
  rescue
    # id/email/name validated above; only remaining risk is missing @enforce_keys
    ArgumentError -> {:error, ["Missing required fields"]}
  end

  @doc """
  Reconstructs a User from persistence data, skipping business validation.
  """
  def from_persistence(attrs) when is_map(attrs) do
    {:ok, struct!(__MODULE__, attrs)}
  rescue
    e in ArgumentError ->
      # Narrow catch: only handle missing @enforce_keys; let type errors crash to surface mapper bugs
      if String.contains?(e.message, "the following keys must also be given") do
        {:error, :invalid_persistence_data}
      else
        reraise e, __STACKTRACE__
      end
  end

  @doc """
  Returns canonical GDPR anonymization values. Domain model owns what "anonymized" means.
  """
  def anonymized_attrs do
    %{
      name: "Deleted User",
      avatar: nil,
      email_fn: fn user_id -> "deleted_#{user_id}@anonymized.local" end
    }
  end

  defp validate_id(errors, id) when is_binary(id) do
    if String.trim(id) == "", do: ["ID cannot be empty" | errors], else: errors
  end

  defp validate_id(errors, id) when is_integer(id) and id > 0, do: errors
  defp validate_id(errors, _), do: ["ID must be a non-empty string or positive integer" | errors]

  defp validate_email(errors, email) when is_binary(email) do
    if String.trim(email) == "" do
      ["Email cannot be empty" | errors]
    else
      errors
    end
  end

  defp validate_email(errors, _), do: ["Email must be a string" | errors]

  defp validate_name(errors, name) when is_binary(name) do
    if String.trim(name) == "" do
      ["Name cannot be empty" | errors]
    else
      errors
    end
  end

  defp validate_name(errors, _), do: ["Name must be a string" | errors]
end
