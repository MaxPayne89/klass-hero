defmodule KlassHero.Enrollment.Adapters.Driven.Persistence.Repositories.EnrollmentPolicyRepository do
  @moduledoc """
  Ecto-based implementation of the ForManagingEnrollmentPolicies port.

  Handles storing and retrieving enrollment capacity configuration (min/max
  enrollment) for programs. Uses upsert semantics so a program's policy can
  be created or updated in a single call.
  """

  @behaviour KlassHero.Enrollment.Domain.Ports.ForManagingEnrollmentPolicies
  @behaviour KlassHero.Enrollment.Domain.Ports.ForQueryingEnrollmentPolicies

  use KlassHero.Shared.Interaction

  import Ecto.Query

  alias KlassHero.Enrollment.Adapters.Driven.Persistence.Mappers.EnrollmentPolicyMapper
  alias KlassHero.Enrollment.Adapters.Driven.Persistence.Schemas.EnrollmentPolicySchema
  alias KlassHero.Enrollment.Adapters.Driven.Persistence.Schemas.EnrollmentSchema
  alias KlassHero.Repo

  require Logger

  @active_statuses ~w(pending confirmed)

  @impl true
  def upsert(attrs) do
    db_interaction operation: :upsert, entity: "enrollment_policy" do
      schema_attrs = EnrollmentPolicyMapper.to_schema_attrs(attrs)

      %EnrollmentPolicySchema{}
      |> EnrollmentPolicySchema.changeset(schema_attrs)
      |> Repo.insert(
        on_conflict: {:replace, [:min_enrollment, :max_enrollment, :updated_at]},
        conflict_target: :program_id,
        returning: true
      )
      |> case do
        {:ok, schema} ->
          Logger.info(
            "[Enrollment.PolicyRepository] Upserted enrollment policy " <>
              "program_id=#{schema.program_id} min=#{schema.min_enrollment} max=#{schema.max_enrollment}"
          )

          {:ok, EnrollmentPolicyMapper.to_domain(schema)}

        {:error, changeset} ->
          Logger.warning("[Enrollment.PolicyRepository] Failed to upsert policy",
            errors: inspect(changeset.errors)
          )

          {:error, changeset}
      end
    end
  end

  @impl true
  def get_by_program_id(program_id) do
    db_interaction operation: :get_by_program_id, entity: "enrollment_policy" do
      case Repo.get_by(EnrollmentPolicySchema, program_id: program_id) do
        nil -> {:error, :not_found}
        schema -> {:ok, EnrollmentPolicyMapper.to_domain(schema)}
      end
    end
  end

  @impl true
  def get_policies_by_program_ids([]), do: %{}

  def get_policies_by_program_ids(program_ids) when is_list(program_ids) do
    db_interaction operation: :get_policies_by_program_ids, entity: "enrollment_policy" do
      from(p in EnrollmentPolicySchema,
        where: p.program_id in ^program_ids
      )
      |> Repo.all()
      |> Map.new(fn schema ->
        {to_string(schema.program_id), EnrollmentPolicyMapper.to_domain(schema)}
      end)
    end
  end

  @impl true
  def count_active_enrollments(program_id) do
    db_interaction operation: :count_active_enrollments, entity: "enrollment_policy" do
      from(e in EnrollmentSchema,
        where: e.program_id == ^program_id and e.status in ^@active_statuses,
        select: count(e.id)
      )
      |> Repo.one()
    end
  end

  @impl true
  def count_active_enrollments_batch([]), do: %{}

  def count_active_enrollments_batch(program_ids) when is_list(program_ids) do
    db_interaction operation: :count_active_enrollments_batch, entity: "enrollment_policy" do
      from(e in EnrollmentSchema,
        where: e.program_id in ^program_ids and e.status in ^@active_statuses,
        group_by: e.program_id,
        select: {e.program_id, count(e.id)}
      )
      |> Repo.all()
      |> Map.new()
      |> then(fn counts ->
        # Programs with no enrollments are absent from the GROUP BY result; default to 0.
        Map.new(program_ids, fn id -> {id, Map.get(counts, id, 0)} end)
      end)
    end
  end
end
