defmodule KlassHero.Provider.Adapters.Driven.Persistence.Repositories.StaffMemberRepository do
  @moduledoc """
  Repository implementation for storing and retrieving staff members.

  Implements the ForStoringStaffMembers port.
  """

  @behaviour KlassHero.Provider.Domain.Ports.ForQueryingStaffMembers
  @behaviour KlassHero.Provider.Domain.Ports.ForStoringStaffMembers

  use KlassHero.Shared.Tracing

  import Ecto.Query

  alias KlassHero.Provider.Adapters.Driven.Persistence.Mappers.StaffMemberMapper
  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.ProgramStaffAssignmentSchema
  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.ProviderProfileSchema
  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.StaffMemberSchema
  alias KlassHero.Provider.Domain.ReadModels.StaffMembership
  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Persistence.MapperHelpers
  alias KlassHero.Shared.Adapters.Driven.Persistence.RepositoryHelpers
  alias KlassHero.Shared.ErrorIds

  @impl true
  def create(attrs) when is_map(attrs) do
    span do
      set_attributes("db", operation: "insert", entity: "staff_member")

      %StaffMemberSchema{}
      |> StaffMemberSchema.create_changeset(attrs)
      |> Repo.insert()
      |> case do
        {:ok, schema} ->
          {:ok, StaffMemberMapper.to_domain(schema)}

        {:error, changeset} ->
          RepositoryHelpers.log_validation_error(changeset, ErrorIds.staff_member_create_failed())
          {:error, changeset}
      end
    end
  end

  @impl true
  def get(id) when is_binary(id) do
    span do
      set_attributes("db", operation: "select", entity: "staff_member")

      RepositoryHelpers.get_by_id(StaffMemberSchema, id, StaffMemberMapper)
    end
  end

  @impl true
  def list_by_provider(provider_id) when is_binary(provider_id) do
    span do
      set_attributes("db", operation: "select", entity: "staff_member")

      members =
        StaffMemberSchema
        |> where([s], s.provider_id == ^provider_id)
        |> order_by([s], asc: s.inserted_at)
        |> Repo.all()
        |> MapperHelpers.to_domain_list(StaffMemberMapper)

      {:ok, members}
    end
  end

  @impl true
  def list_active_by_provider(provider_id) when is_binary(provider_id) do
    span do
      set_attributes("db", operation: "select", entity: "staff_member")

      members =
        StaffMemberSchema
        |> where([s], s.provider_id == ^provider_id and s.active == true)
        |> order_by([s], asc: s.inserted_at)
        |> Repo.all()
        |> MapperHelpers.to_domain_list(StaffMemberMapper)

      {:ok, members}
    end
  end

  @impl true
  def list_active_by_program(program_id) when is_binary(program_id) do
    span do
      set_attributes("db", operation: "select", entity: "staff_member")

      members =
        from(s in StaffMemberSchema,
          join: a in ProgramStaffAssignmentSchema,
          on: a.staff_member_id == s.id and a.provider_id == s.provider_id,
          where: a.program_id == ^program_id and is_nil(a.unassigned_at) and s.active == true,
          order_by: [asc: a.assigned_at],
          select: s
        )
        |> Repo.all()
        |> MapperHelpers.to_domain_list(StaffMemberMapper)

      {:ok, members}
    end
  end

  @impl true
  def update(staff_member) do
    span do
      set_attributes("db", operation: "update", entity: "staff_member")

      with {:ok, schema} <-
             RepositoryHelpers.get_schema_by_uuid(StaffMemberSchema, staff_member.id),
           attrs = StaffMemberMapper.to_schema(staff_member),
           {:ok, updated} <-
             schema |> StaffMemberSchema.edit_changeset(attrs) |> Repo.update() do
        {:ok, StaffMemberMapper.to_domain(updated)}
      end
    end
  end

  @impl true
  def delete(id) when is_binary(id) do
    span do
      set_attributes("db", operation: "delete", entity: "staff_member")

      case Repo.get(StaffMemberSchema, id) do
        nil ->
          {:error, :not_found}

        schema ->
          {:ok, _} = Repo.delete(schema)
          :ok
      end
    end
  end

  @impl true
  def get_by_token_hash(token_hash) when is_binary(token_hash) do
    span do
      set_attributes("db", operation: "select", entity: "staff_member")

      query =
        from s in StaffMemberSchema,
          where: s.invitation_token_hash == ^token_hash and s.invitation_status == "sent"

      case Repo.one(query) do
        nil -> {:error, :not_found}
        schema -> {:ok, StaffMemberMapper.to_domain(schema)}
      end
    end
  end

  @impl true
  def get_active_by_user(user_id) when is_binary(user_id) do
    span do
      set_attributes("db", operation: "select", entity: "staff_member")

      query = from [s, _p] in active_memberships_query(user_id), limit: 1, select: s

      case Repo.one(query) do
        nil -> {:error, :not_found}
        schema -> {:ok, StaffMemberMapper.to_domain(schema)}
      end
    end
  end

  @impl true
  def list_active_memberships_by_user(user_id) when is_binary(user_id) do
    span do
      set_attributes("db", operation: "select", entity: "staff_member")

      memberships =
        from([s, p] in active_memberships_query(user_id),
          select: %StaffMembership{
            staff_member_id: type(s.id, :string),
            provider_id: type(s.provider_id, :string),
            business_name: p.business_name
          }
        )
        |> Repo.all()

      {:ok, memberships}
    end
  end

  # Selection ordering for the staff-context switcher (#969): the row the user
  # last selected wins; users who never selected default to an employer row
  # over their own business (a founder reaches their own business through the
  # provider dashboard — the staff surfaces should default to who employs them).
  defp active_memberships_query(user_id) do
    from s in StaffMemberSchema,
      join: p in ProviderProfileSchema,
      on: p.id == s.provider_id,
      where: s.user_id == ^user_id and s.active == true,
      order_by: [
        desc_nulls_last: s.last_selected_at,
        asc: p.identity_id == type(^user_id, :binary_id),
        desc: s.inserted_at,
        # Unique tiebreaker: inserted_at is second-precision, so same-second
        # rows would otherwise order nondeterministically across executions —
        # the limit-1 scope row and the memberships head could disagree.
        desc: s.id
      ]
  end

  @impl true
  def touch_last_selected(user_id, provider_id) when is_binary(user_id) and is_binary(provider_id) do
    span do
      set_attributes("db", operation: "update", entity: "staff_member")

      query =
        from s in StaffMemberSchema,
          where: s.user_id == ^user_id and s.provider_id == ^provider_id and s.active == true

      case Repo.update_all(query, set: [last_selected_at: DateTime.utc_now()]) do
        {0, _} -> {:error, :not_staffed}
        {_count, _} -> {:ok, :selected}
      end
    end
  end

  @impl true
  def active_for_provider_and_user?(provider_id, user_id) when is_binary(provider_id) and is_binary(user_id) do
    span do
      set_attributes("db", operation: "exists", entity: "staff_member")

      from(s in StaffMemberSchema,
        where: s.provider_id == ^provider_id and s.user_id == ^user_id and s.active == true
      )
      |> Repo.exists?()
    end
  end
end
