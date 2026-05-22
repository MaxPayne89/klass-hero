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
  Inserts a single invite and returns the persisted domain struct.

  Runs `BulkEnrollmentInviteSchema.import_changeset/2`, which validates
  required fields and excludes lifecycle columns. Callers needing per-row
  outcomes (e.g. ImportEnrollmentCsv collecting partial-success results)
  invoke this in a loop.
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
  Returns existing invite keys for the given program IDs.

  Used for duplicate detection before batch insert. Keys are
  `{program_id, guardian_email, child_first_name, child_last_name}` tuples
  with email lowercased for case-insensitive comparison.

  Returns an empty MapSet when given an empty list.
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
  @doc """
  Retrieves a single invite by its ID.

  Returns `{:ok, invite}` when found, `{:error, :not_found}` otherwise.
  """
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
  @doc """
  Retrieves a single invite by its invite token.

  Returns `{:ok, invite}` when found, `{:error, :not_found}` otherwise.
  Short-circuits on `nil` input to avoid unnecessary queries.
  """
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
  @doc """
  Returns pending invites that have not yet been assigned an invite token.

  Filters by program IDs, status "pending", and nil invite_token.
  Returns an empty list when given an empty list of program IDs.
  """
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
  @doc """
  Returns all invites for a given program, ordered alphabetically
  by child last name then first name.
  """
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
  @doc """
  Returns the count of invites for a given program.
  """
  def count_by_program(program_id) when is_binary(program_id) do
    span do
      set_attributes("db", operation: "select", entity: "bulk_enrollment_invite")

      BulkEnrollmentInviteSchema
      |> where([i], i.program_id == ^program_id)
      |> Repo.aggregate(:count)
    end
  end

  @impl true
  @doc """
  Deletes an invite by its ID.

  Returns `:ok` on success, `{:error, :not_found}`, or `{:error, :delete_failed}`.
  """
  def delete(id) when is_binary(id) do
    span do
      set_attributes("db", operation: "delete", entity: "bulk_enrollment_invite")

      case Repo.get(BulkEnrollmentInviteSchema, id) do
        nil ->
          {:error, :not_found}

        schema ->
          # Trigger: Repo.delete can return {:error, changeset} on FK constraint violations
          # Why: bare match raises MatchError and crashes the caller
          # Outcome: log warning and surface :delete_failed to callers
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
  Assigns invite tokens to multiple invites in bulk.

  Accepts a list of `{invite_id, token}` tuples. Each invite is updated
  individually within a reduce. Returns `{:ok, count}` with the total
  number of rows updated.
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

      # Trigger: N pairs would cause N individual UPDATE queries (N+1 problem)
      # Why: single UPDATE + unnest batches all token assignments into one round-trip
      # Outcome: exactly 1 SQL statement regardless of batch size, fully static SQL
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
  @doc """
  Transitions an invite's status using the schema's state machine.

  Delegates to `BulkEnrollmentInviteSchema.transition_changeset/2` for
  validation, then persists the update.
  """
  def transition_status(%{id: id}, attrs) when is_map(attrs) do
    span do
      set_attributes("db", operation: "update", entity: "bulk_enrollment_invite")

      # Trigger: domain model passed in — must refetch schema for Ecto changeset
      # Why: domain models are pure structs without Ecto metadata
      # Outcome: load schema by ID, apply transition changeset, map result back
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
  Resets a resendable invite back to pending status, clearing its token and metadata.

  Bypasses the normal state machine (`transition_changeset`) intentionally —
  this is a dedicated reset operation with its own guard on `@resendable_statuses`,
  using a plain `change/2` since it clears fields rather than transitioning forward.
  """
  def reset_for_resend(%{id: id, status: status}) when status in @resendable_statuses do
    span do
      set_attributes("db", operation: "update", entity: "bulk_enrollment_invite")

      case Repo.get(BulkEnrollmentInviteSchema, id) do
        nil ->
          {:error, :not_found}

        schema ->
          # Trigger: invite needs to re-enter the email pipeline
          # Why: clearing token + invite_sent_at makes it eligible for list_pending_without_token
          # Outcome: existing EnqueueInviteEmails picks it up on next dispatch
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
