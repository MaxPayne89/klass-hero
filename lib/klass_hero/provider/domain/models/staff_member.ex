defmodule KlassHero.Provider.Domain.Models.StaffMember do
  @moduledoc """
  Pure domain entity representing a staff/team member in the Provider bounded context.

  Staff members belong to a provider and are visible to parents on program pages.
  Contains only business logic and validation rules, no database dependencies.

  Tags use the same vocabulary as program categories (ProgramCategories.program_categories/0).
  Qualifications are freeform text entries (e.g., "First Aid", "UEFA B License").
  """

  alias KlassHero.Provider.Domain.Models.PayRate
  alias KlassHero.Shared.Categories
  alias KlassHero.Shared.NameUtils

  @enforce_keys [:id, :provider_id, :first_name, :last_name]

  defstruct [
    :id,
    :provider_id,
    :first_name,
    :last_name,
    :role,
    :email,
    :bio,
    :headshot_url,
    :user_id,
    :invitation_status,
    :invitation_token_hash,
    :invitation_sent_at,
    :pay_rate,
    tags: [],
    qualifications: [],
    active: true,
    inserted_at: nil,
    updated_at: nil
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          provider_id: String.t(),
          first_name: String.t(),
          last_name: String.t(),
          role: String.t() | nil,
          email: String.t() | nil,
          bio: String.t() | nil,
          headshot_url: String.t() | nil,
          user_id: String.t() | nil,
          invitation_status: :pending | :sent | :failed | :accepted | :expired | nil,
          invitation_token_hash: binary() | nil,
          invitation_sent_at: DateTime.t() | nil,
          pay_rate: PayRate.t() | nil,
          tags: [String.t()],
          qualifications: [String.t()],
          active: boolean(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @doc """
  Creates a new StaffMember with validation.

  Returns:
  - `{:ok, staff_member}` if all validations pass
  - `{:error, [reasons]}` with list of validation errors
  """
  def new(attrs) do
    attrs_with_defaults = apply_defaults(attrs)
    staff = struct!(__MODULE__, attrs_with_defaults)

    case validate(staff) do
      [] -> {:ok, staff}
      errors -> {:error, errors}
    end
  end

  @doc """
  Reconstructs a StaffMember from persistence data.

  Unlike `new/1`, this skips business validation since data was validated
  on write. Uses `struct!/2` to enforce `@enforce_keys`.

  Returns:
  - `{:ok, staff_member}` if all required keys are present
  - `{:error, :invalid_persistence_data}` if required keys are missing
  """
  def from_persistence(attrs) when is_map(attrs) do
    {:ok, struct!(__MODULE__, attrs)}
  rescue
    ArgumentError -> {:error, :invalid_persistence_data}
  end

  def valid?(%__MODULE__{} = staff), do: validate(staff) == []

  def full_name(%__MODULE__{first_name: first, last_name: last}), do: "#{first} #{last}"

  def initials(%__MODULE__{} = staff), do: NameUtils.initials_from_name(full_name(staff))

  defp apply_defaults(attrs) do
    attrs
    |> Map.put_new(:tags, [])
    |> Map.put_new(:qualifications, [])
    |> Map.put_new(:active, true)
  end

  defp validate(%__MODULE__{} = staff) do
    []
    |> validate_provider_id(staff.provider_id)
    |> validate_first_name(staff.first_name)
    |> validate_last_name(staff.last_name)
    |> validate_role(staff.role)
    |> validate_email(staff.email)
    |> validate_bio(staff.bio)
    |> validate_headshot_url(staff.headshot_url)
    |> validate_tags(staff.tags)
    |> validate_qualifications(staff.qualifications)
    |> validate_pay_rate(staff.pay_rate)
  end

  defp validate_provider_id(errors, id) when is_binary(id) do
    if String.trim(id) == "", do: ["Provider ID cannot be empty" | errors], else: errors
  end

  defp validate_provider_id(errors, _), do: ["Provider ID must be a string" | errors]

  defp validate_first_name(errors, name) when is_binary(name) do
    trimmed = String.trim(name)

    cond do
      trimmed == "" -> ["First name cannot be empty" | errors]
      String.length(trimmed) > 100 -> ["First name must be 100 characters or less" | errors]
      true -> errors
    end
  end

  defp validate_first_name(errors, _), do: ["First name must be a string" | errors]

  defp validate_last_name(errors, name) when is_binary(name) do
    trimmed = String.trim(name)

    cond do
      trimmed == "" -> ["Last name cannot be empty" | errors]
      String.length(trimmed) > 100 -> ["Last name must be 100 characters or less" | errors]
      true -> errors
    end
  end

  defp validate_last_name(errors, _), do: ["Last name must be a string" | errors]

  defp validate_role(errors, nil), do: errors

  defp validate_role(errors, role) when is_binary(role) do
    if String.length(role) > 100,
      do: ["Role must be 100 characters or less" | errors],
      else: errors
  end

  defp validate_role(errors, _), do: ["Role must be a string" | errors]

  defp validate_email(errors, nil), do: errors

  defp validate_email(errors, email) when is_binary(email) do
    trimmed = String.trim(email)

    cond do
      trimmed == "" -> ["Email cannot be empty if provided" | errors]
      not String.contains?(trimmed, "@") -> ["Email must contain @" | errors]
      String.length(trimmed) > 255 -> ["Email must be 255 characters or less" | errors]
      true -> errors
    end
  end

  defp validate_email(errors, _), do: ["Email must be a string" | errors]

  defp validate_bio(errors, nil), do: errors

  defp validate_bio(errors, bio) when is_binary(bio) do
    if String.length(bio) > 2000,
      do: ["Bio must be 2000 characters or less" | errors],
      else: errors
  end

  defp validate_bio(errors, _), do: ["Bio must be a string" | errors]

  defp validate_headshot_url(errors, nil), do: errors

  defp validate_headshot_url(errors, url) when is_binary(url) do
    if String.length(url) > 500,
      do: ["Headshot URL must be 500 characters or less" | errors],
      else: errors
  end

  defp validate_headshot_url(errors, _), do: ["Headshot URL must be a string" | errors]

  defp validate_tags(errors, tags) when is_list(tags) do
    valid = Categories.categories()
    invalid = Enum.reject(tags, &(&1 in valid))

    if invalid == [],
      do: errors,
      else: ["Invalid tags: #{Enum.join(invalid, ", ")}" | errors]
  end

  defp validate_tags(errors, _), do: ["Tags must be a list" | errors]

  defp validate_qualifications(errors, quals) when is_list(quals) do
    if Enum.all?(quals, &is_binary/1),
      do: errors,
      else: ["Qualifications must be a list of strings" | errors]
  end

  defp validate_qualifications(errors, _), do: ["Qualifications must be a list" | errors]

  defp validate_pay_rate(errors, nil), do: errors

  defp validate_pay_rate(errors, %PayRate{} = pay_rate) do
    if PayRate.valid?(pay_rate),
      do: errors,
      else: ["Pay rate is invalid" | errors]
  end

  defp validate_pay_rate(errors, _), do: ["Pay rate must be a %PayRate{} struct or nil" | errors]

  @doc """
  Generates a URL-safe invitation token and its SHA-256 hash.
  Returns `{raw_token, token_hash}`.
  """
  @spec generate_invitation_token() :: {String.t(), binary()}
  def generate_invitation_token do
    raw_bytes = :crypto.strong_rand_bytes(32)
    raw_token = Base.url_encode64(raw_bytes, padding: false)
    token_hash = :crypto.hash(:sha256, raw_bytes)
    {raw_token, token_hash}
  end

  @valid_invitation_transitions %{
    nil => [:pending],
    :pending => [:sent, :failed, :accepted],
    :sent => [:accepted, :expired],
    :failed => [:pending],
    :expired => [:pending]
  }

  @doc """
  Returns the list of valid invitation status atoms.
  Derived from the state machine transitions to keep a single source of truth.
  """
  @spec valid_invitation_statuses() :: [atom()]
  def valid_invitation_statuses do
    @valid_invitation_transitions
    |> Map.values()
    |> List.flatten()
    |> Enum.uniq()
  end

  @invitation_expiry_days 7

  @doc """
  Checks whether a staff member's invitation has expired (#{@invitation_expiry_days} days from sending).
  """
  @spec invitation_expired?(t()) :: boolean()
  def invitation_expired?(%__MODULE__{invitation_sent_at: nil}), do: false

  def invitation_expired?(%__MODULE__{invitation_sent_at: sent_at}) do
    DateTime.diff(DateTime.utc_now(), sent_at, :day) >= @invitation_expiry_days
  end

  @spec transition_invitation(t(), atom()) ::
          {:ok, t()} | {:error, :invalid_invitation_transition}
  def transition_invitation(%__MODULE__{} = staff_member, new_status) do
    allowed = Map.get(@valid_invitation_transitions, staff_member.invitation_status, [])

    if new_status in allowed do
      {:ok, %{staff_member | invitation_status: new_status}}
    else
      {:error, :invalid_invitation_transition}
    end
  end
end
