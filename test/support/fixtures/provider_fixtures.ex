defmodule KlassHero.ProviderFixtures do
  @moduledoc """
  Test helpers for creating entities in the Provider bounded context.
  """

  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.ProviderProgramProjectionSchema
  alias KlassHero.Provider.IncidentReport
  alias KlassHero.Provider.ProviderProfile
  alias KlassHero.Provider.StaffMember
  alias KlassHero.Provider.VerificationDocument
  alias KlassHero.Repo

  @doc """
  Creates a provider profile for testing.

  Inserts a provider profile via its changeset and returns the struct.
  """
  def provider_profile_fixture(attrs \\ %{}) do
    attrs_map = Map.new(attrs)

    # Trigger: identity_id references users table via FK
    # Why: consolidated migrations enforce referential integrity
    # Outcome: every provider profile is linked to a real user record
    identity_id =
      attrs_map[:identity_id] ||
        KlassHero.AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider]).id

    defaults = %{
      identity_id: identity_id,
      business_name: "Test Provider #{System.unique_integer([:positive])}"
    }

    merged = Map.merge(defaults, attrs_map)

    {:ok, profile} =
      %ProviderProfile{}
      |> ProviderProfile.changeset(merged)
      |> Repo.insert()

    profile
  end

  @doc """
  Creates a staff member for testing.

  Uses the schema directly to insert into database, then maps to domain model.
  Supports invitation fields: invitation_status, invitation_token_hash, invitation_sent_at, user_id.

  Also accepts `:inserted_at` and `:last_selected_at` timestamp overrides for
  selection-ordering tests — applied AFTER insert via `update_all`, since both
  fields are deliberately absent from every changeset cast list.
  """
  def staff_member_fixture(attrs \\ %{}) do
    defaults = %{
      provider_id: attrs[:provider_id] || provider_profile_fixture().id,
      first_name: "Staff #{System.unique_integer([:positive])}",
      last_name: "Member"
    }

    merged = Map.merge(defaults, Map.new(attrs))

    # Timestamp overrides bypass changesets entirely — applied last via update_all.
    timestamp_keys = [:inserted_at, :last_selected_at]
    timestamp_overrides = Map.take(merged, timestamp_keys)
    merged = Map.drop(merged, timestamp_keys)

    # Invitation fields are applied via invitation_changeset after initial insert
    invitation_keys = [:invitation_status, :invitation_token_hash, :invitation_sent_at, :user_id]
    create_attrs = Map.drop(merged, invitation_keys)

    {:ok, schema} =
      %StaffMember{}
      |> StaffMember.create_changeset(create_attrs)
      |> Repo.insert()

    # Apply invitation fields if provided (these go through invitation_changeset, not create)
    invitation_fields = Map.take(merged, invitation_keys)

    schema =
      if map_size(invitation_fields) > 0 do
        {:ok, updated} =
          schema
          |> StaffMember.invitation_changeset(invitation_fields)
          |> Repo.update()

        updated
      else
        schema
      end

    schema = apply_timestamp_overrides(schema, timestamp_overrides)

    StaffMember.load_pay_rate(schema)
  end

  defp apply_timestamp_overrides(schema, overrides) when map_size(overrides) == 0, do: schema

  defp apply_timestamp_overrides(schema, overrides) do
    import Ecto.Query, only: [from: 2]

    {1, _} =
      Repo.update_all(
        from(s in StaffMember, where: s.id == ^schema.id),
        set: Map.to_list(overrides)
      )

    Repo.get!(StaffMember, schema.id)
  end

  @doc """
  Creates a pending verification document for testing.

  Returns the unwrapped domain model (not {:ok, doc}).
  Accepts optional `provider_id`; if omitted, creates a new provider profile.
  """
  def verification_document_fixture(attrs \\ %{}) do
    attrs_map = Map.new(attrs)

    {:ok, persisted} =
      %{
        provider_profile_id: attrs_map[:provider_id] || provider_profile_fixture().id,
        document_type: attrs_map[:document_type] || "business_registration",
        file_url: attrs_map[:file_url] || "verification-docs/#{Ecto.UUID.generate()}.pdf",
        original_filename: attrs_map[:original_filename] || "doc.pdf"
      }
      |> VerificationDocument.create_changeset()
      |> Repo.insert()

    persisted
  end

  @doc """
  Creates an approved verification document for testing.

  Composes: pending -> approve -> persist.
  Requires `reviewer_id`. Accepts optional `provider_id`.
  """
  def approved_verification_document_fixture(attrs \\ %{}) do
    attrs_map = Map.new(attrs)
    reviewer_id = attrs_map[:reviewer_id] || raise "reviewer_id is required"

    doc = verification_document_fixture(attrs)
    {:ok, approved} = VerificationDocument.approve(doc, reviewer_id)
    {:ok, persisted} = persist_review(doc, approved)
    persisted
  end

  @doc """
  Creates a rejected verification document for testing.

  Composes: pending -> reject -> persist.
  Requires `reviewer_id`. Accepts optional `provider_id` and `rejection_reason`.
  """
  def rejected_verification_document_fixture(attrs \\ %{}) do
    attrs_map = Map.new(attrs)
    reviewer_id = attrs_map[:reviewer_id] || raise "reviewer_id is required"
    reason = attrs_map[:rejection_reason] || "Invalid document"

    doc = verification_document_fixture(attrs)
    {:ok, rejected} = VerificationDocument.reject(doc, reviewer_id, reason)
    {:ok, persisted} = persist_review(doc, rejected)
    persisted
  end

  defp persist_review(%VerificationDocument{} = original, %VerificationDocument{} = updated) do
    original
    |> VerificationDocument.review_changeset(
      Map.take(updated, [:status, :rejection_reason, :reviewed_by_id, :reviewed_at])
    )
    |> Repo.update()
  end

  @doc """
  Inserts a `provider_programs` projection row for testing.

  Accepts `program_id`, `provider_id`, `name`, `status`. Defaults provided.
  Returns the inserted schema struct.
  """
  def provider_program_projection_fixture(attrs \\ %{}) do
    attrs_map = Map.new(attrs)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert!(%ProviderProgramProjectionSchema{
      program_id: attrs_map[:program_id] || Ecto.UUID.generate(),
      provider_id: attrs_map[:provider_id] || raise("provider_id is required"),
      name: attrs_map[:name] || "Test Program #{System.unique_integer([:positive])}",
      status: attrs_map[:status] || "active",
      inserted_at: now,
      updated_at: now
    })
  end

  @doc """
  Creates an incident report for testing.

  Accepts overrides via `attrs`. Defaults provide a safety_concern/high
  report dated 2026-04-20. Caller must supply `provider_profile_id`,
  `reporter_user_id`, and either `program_id` or `session_id`.

  Returns the persisted domain model.
  """
  def incident_report_fixture(attrs \\ %{}) do
    attrs_map = Map.new(attrs)

    defaults = %{
      id: Ecto.UUID.generate(),
      category: :safety_concern,
      severity: :high,
      description: "A child slipped near the play area but is unharmed.",
      occurred_at: ~U[2026-04-20 14:30:00Z],
      reporter_display_name: "Test Reporter"
    }

    {:ok, persisted} =
      defaults
      |> Map.merge(attrs_map)
      |> IncidentReport.create_changeset()
      |> Repo.insert()

    persisted
  end

  @doc """
  Creates a dual-role user with both provider profile and staff member.

  Returns `%{user: user, provider: provider, staff: staff}`.
  """
  def dual_role_user_fixture(attrs \\ %{}) do
    attrs_map = Map.new(attrs)

    user =
      KlassHero.AccountsFixtures.user_fixture(intended_roles: attrs_map[:intended_roles] || [:staff, :provider])

    provider = provider_profile_fixture(identity_id: attrs_map[:identity_id] || user.id)

    staff =
      staff_member_fixture(
        provider_id: provider.id,
        user_id: user.id,
        invitation_status: :accepted
      )

    %{user: user, provider: provider, staff: staff}
  end
end
