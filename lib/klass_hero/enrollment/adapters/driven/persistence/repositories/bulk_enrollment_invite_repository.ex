defmodule KlassHero.Enrollment.Adapters.Driven.Persistence.Repositories.BulkEnrollmentInviteRepository do
  @moduledoc """
  Repository implementation for bulk enrollment invite persistence.

  Implements the ForStoringBulkEnrollmentInvites port with:
  - Per-row insert via `create_one/1` for partial-success import flows
  - Duplicate-detection query returning MapSet of natural keys
  """

  @behaviour KlassHero.Enrollment.Domain.Ports.ForQueryingBulkEnrollmentInvites
  @behaviour KlassHero.Enrollment.Domain.Ports.ForStoringBulkEnrollmentInvites

  use KlassHero.Shared.Tracing

  import Ecto.Query

  alias KlassHero.Enrollment.Adapters.Driven.Persistence.Mappers.BulkEnrollmentInviteMapper,
    as: Mapper

  alias KlassHero.Enrollment.Adapters.Driven.Persistence.Schemas.BulkEnrollmentInviteSchema
  alias KlassHero.Enrollment.Domain.Models.BulkEnrollmentInvite
  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Persistence.MapperHelpers

  require Logger

  @resendable_statuses [:pending, :invite_sent, :failed]

  @impl true
  @doc """
  Inserts a single invite via `import_changeset/2`, returning the persisted domain struct.
  """
  def create_one(attrs) when is_map(attrs) do
    span do
      set_attributes("db", operation: "insert", entity: "bulk_enrollment_invite")

      %BulkEnrollmentInviteSchema{}
      |> BulkEnrollmentInviteSchema.import_changeset(attrs)
      |> Repo.insert()
      |> case do
        {:ok, schema} ->
          Logger.info("[BulkEnrollmentInvite.Repository] Single invite created",
            invite_id: schema.id
          )

          {:ok, Mapper.to_domain(schema)}

        {:error, changeset} ->
          Logger.error("[BulkEnrollmentInvite.Repository] Single invite insert failed",
            errors: inspect(changeset.errors)
          )

          {:error, changeset}
      end
    end
  end

  @impl true
  @doc """
  Returns a MapSet of dedup keys for all invites in the given programs (empty list → empty MapSet).
  """
  def list_existing_keys_for_programs([]), do: MapSet.new()

  def list_existing_keys_for_programs(program_ids) when is_list(program_ids) do
    span do
      set_attributes("db", operation: "select", entity: "bulk_enrollment_invite")

      BulkEnrollmentInviteSchema
      |> where([i], i.program_id in ^program_ids)
      |> select([i], {i.program_id, i.guardian_email, i.child_first_name, i.child_last_name})
      |> Repo.all()
      |> MapSet.new(fn {pid, email, first, last} ->
        BulkEnrollmentInvite.dedup_key(pid, email, first, last)
      end)
    end
  end

  @impl true
  def invite_exists?(program_id, guardian_email, child_first_name, child_last_name)
      when is_binary(program_id) and is_binary(guardian_email) and is_binary(child_first_name) and
             is_binary(child_last_name) do
    span do
      set_attributes("db", operation: "select", entity: "bulk_enrollment_invite")

      email_down = String.downcase(guardian_email)
      first_down = String.downcase(child_first_name)
      last_down = String.downcase(child_last_name)

      BulkEnrollmentInviteSchema
      |> where([i], i.program_id == ^program_id)
      |> where([i], fragment("lower(?)", i.guardian_email) == ^email_down)
      |> where([i], fragment("lower(?)", i.child_first_name) == ^first_down)
      |> where([i], fragment("lower(?)", i.child_last_name) == ^last_down)
      |> Repo.exists?()
    end
  end

  @impl true
  def get_by_id(id) when is_binary(id) do
    span do
      set_attributes("db", operation: "select", entity: "bulk_enrollment_invite")

      case Repo.get(BulkEnrollmentInviteSchema, id) do
        nil -> {:error, :not_found}
        schema -> {:ok, Mapper.to_domain(schema)}
      end
    end
  end

  @impl true
  def get_by_token(nil), do: {:error, :not_found}

  def get_by_token(token) when is_binary(token) do
    span do
      set_attributes("db", operation: "select", entity: "bulk_enrollment_invite")

      BulkEnrollmentInviteSchema
      |> where([i], i.invite_token == ^token)
      |> Repo.one()
      |> case do
        nil -> {:error, :not_found}
        schema -> {:ok, Mapper.to_domain(schema)}
      end
    end
  end

  @impl true
  def list_pending_without_token([]), do: []

  def list_pending_without_token(program_ids) when is_list(program_ids) do
    span do
      set_attributes("db", operation: "select", entity: "bulk_enrollment_invite")

      BulkEnrollmentInviteSchema
      |> where([i], i.program_id in ^program_ids)
      |> where([i], i.status == :pending)
      |> where([i], is_nil(i.invite_token))
      |> Repo.all()
      |> MapperHelpers.to_domain_list(Mapper)
    end
  end

  @impl true
  def list_by_program(program_id) when is_binary(program_id) do
    span do
      set_attributes("db", operation: "select", entity: "bulk_enrollment_invite")

      BulkEnrollmentInviteSchema
      |> where([i], i.program_id == ^program_id)
      |> order_by([i], asc: i.child_last_name, asc: i.child_first_name)
      |> Repo.all()
      |> MapperHelpers.to_domain_list(Mapper)
    end
  end

  @impl true
  def count_by_program(program_id) when is_binary(program_id) do
    span do
      set_attributes("db", operation: "select", entity: "bulk_enrollment_invite")

      BulkEnrollmentInviteSchema
      |> where([i], i.program_id == ^program_id)
      |> Repo.aggregate(:count)
    end
  end

  @impl true
  def delete(id) when is_binary(id) do
    span do
      set_attributes("db", operation: "delete", entity: "bulk_enrollment_invite")

      case Repo.get(BulkEnrollmentInviteSchema, id) do
        nil ->
          {:error, :not_found}

        schema ->
          # Repo.delete may return {:error, changeset} on FK violations; surface as :delete_failed.
          case Repo.delete(schema) do
            {:ok, _deleted} ->
              :ok

            {:error, changeset} ->
              Logger.warning("[BulkEnrollmentInvite] Delete failed for #{id}: #{inspect(changeset.errors)}")

              {:error, :delete_failed}
          end
      end
    end
  end

  @impl true
  @doc """
  Bulk-assigns tokens to invites. Returns `{:ok, count}` with the number of rows updated.
  """
  def bulk_assign_tokens([]), do: {:ok, 0}

  def bulk_assign_tokens(id_token_pairs) when is_list(id_token_pairs) do
    span do
      set_attributes("db", operation: "update", entity: "bulk_enrollment_invite")

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {ids, tokens} =
        Enum.reduce(id_token_pairs, {[], []}, fn {id, token}, {ids, tokens} ->
          {[id | ids], [token | tokens]}
        end)

      # Single UPDATE + unnest batches all assignments into one round-trip, avoiding N+1.
      sql = """
      UPDATE bulk_enrollment_invites AS b
      SET invite_token = v.token, updated_at = $3::timestamp
      FROM unnest($1::text[], $2::text[]) AS v(id, token)
      WHERE b.id = v.id::uuid
      """

      case Repo.query(sql, [Enum.reverse(ids), Enum.reverse(tokens), now]) do
        {:ok, %{num_rows: count}} -> {:ok, count}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @impl true
  def transition_status(%{id: id}, attrs) when is_map(attrs) do
    span do
      set_attributes("db", operation: "update", entity: "bulk_enrollment_invite")

      # Domain models lack Ecto metadata; refetch schema by ID before applying the changeset.
      case Repo.get(BulkEnrollmentInviteSchema, id) do
        nil ->
          {:error, :not_found}

        schema ->
          schema
          |> BulkEnrollmentInviteSchema.transition_changeset(attrs)
          |> Repo.update()
          |> case do
            {:ok, updated_schema} -> {:ok, Mapper.to_domain(updated_schema)}
            {:error, changeset} -> {:error, changeset}
          end
      end
    end
  end

  @impl true
  @doc """
  Resets a resendable invite to pending, clearing its token and sent metadata.

  Bypasses `transition_changeset` intentionally — this is a reverse reset, not a forward transition.
  """
  def reset_for_resend(%{id: id, status: status}) when status in @resendable_statuses do
    span do
      set_attributes("db", operation: "update", entity: "bulk_enrollment_invite")

      case Repo.get(BulkEnrollmentInviteSchema, id) do
        nil ->
          {:error, :not_found}

        schema ->
          # Clearing token + invite_sent_at makes the invite eligible for list_pending_without_token.
          changeset =
            Ecto.Changeset.change(schema, %{
              status: :pending,
              invite_token: nil,
              invite_sent_at: nil,
              error_details: nil
            })

          case Repo.update(changeset) do
            {:ok, updated} -> {:ok, Mapper.to_domain(updated)}
            {:error, changeset} -> {:error, changeset}
          end
      end
    end
  end

  def reset_for_resend(%{id: _id}), do: {:error, :not_resendable}
end
