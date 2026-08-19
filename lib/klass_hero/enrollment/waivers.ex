defmodule KlassHero.Enrollment.Waivers do
  @moduledoc """
  Authoring and lookup for program waivers, reached through the `KlassHero.Enrollment` facade.

  A context-root query submodule in the shape of `Provider.Programs` — not a repository. It
  owns the three waiver tables' read and write paths so `enrollment.ex` stays the shell.

  ## Ownership

  Waivers hang off a program, and programs belong to Program Catalog. Every authoring call
  therefore proves ownership through `ProgramCatalog.get_program_for_provider/2` before
  touching anything, because `program_id` here is a bare correlation id: the database will
  happily accept a waiver pointing at someone else's program.

  ## Latest version

  "The waiver's current wording" is the highest-numbered row in `waiver_versions`, resolved
  with a `DISTINCT ON` rather than by storing a pointer on the waiver — a pointer would be a
  second source of truth to keep in step, and versions are append-only anyway.
  """

  use KlassHero.Shared.Tracing

  import Ecto.Query

  alias KlassHero.Enrollment.Waiver
  alias KlassHero.Enrollment.WaiverVersion
  alias KlassHero.ProgramCatalog
  alias KlassHero.Repo

  @doc """
  Creates a waiver and publishes its first version in one transaction.

  Returns `{:ok, %{waiver: Waiver.t(), version: WaiverVersion.t()}}`, `{:error, :not_found}`
  when the provider does not own the program, or `{:error, changeset | keyword}`.
  """
  def create_waiver(provider_id, %{program_id: program_id} = attrs) do
    with :ok <- ensure_program_owned(provider_id, program_id),
         {:ok, version_attrs} <- WaiverVersion.publish(nil, attrs[:body], nil) do
      insert_waiver_with_version(attrs, version_attrs)
    end
  end

  @doc """
  Appends a new version of a waiver's text. The previous version is left untouched.

  Returns `{:ok, WaiverVersion.t()}`, `{:error, :not_found}` when the provider does not own
  the waiver's program, or `{:error, changeset | keyword}`.
  """
  def publish_waiver_version(provider_id, waiver_id, body) do
    with {:ok, waiver} <- fetch_owned_waiver(provider_id, waiver_id),
         {:ok, attrs} <- WaiverVersion.publish(waiver.id, body, latest_version(waiver.id)) do
      %WaiverVersion{}
      |> WaiverVersion.changeset(attrs)
      |> Repo.insert()
    end
  end

  @doc """
  Retires a waiver from future enrollments. Signed acceptances under it are unaffected.
  """
  def archive_waiver(provider_id, waiver_id) do
    with {:ok, waiver} <- fetch_owned_waiver(provider_id, waiver_id) do
      waiver
      |> Waiver.archive_changeset(DateTime.utc_now())
      |> Repo.update()
    end
  end

  @doc """
  Lists a program's active waivers, each paired with its current version.

  Returns `[%{waiver: Waiver.t(), version: WaiverVersion.t()}]`, ordered by title.
  """
  def list_program_waivers(program_id) do
    waivers =
      Waiver
      |> where([w], w.program_id == ^program_id and is_nil(w.archived_at))
      |> order_by([w], asc: w.title)
      |> Repo.all()

    pair_with_versions(waivers)
  end

  @doc """
  The current version of every *required*, active waiver on a program.

  This is what the enrollment gate compares a parent's signatures against.
  """
  def list_required_waiver_versions(program_id) do
    Waiver
    |> where([w], w.program_id == ^program_id and is_nil(w.archived_at) and w.required)
    |> Repo.all()
    |> pair_with_versions()
    |> Enum.map(& &1.version)
  end

  defp pair_with_versions([]), do: []

  defp pair_with_versions(waivers) do
    versions = latest_versions_by_waiver(Enum.map(waivers, & &1.id))

    for waiver <- waivers, version = Map.get(versions, waiver.id), do: %{waiver: waiver, version: version}
  end

  # DISTINCT ON (waiver_id) with a descending version order = the newest row per waiver.
  defp latest_versions_by_waiver(waiver_ids) do
    WaiverVersion
    |> where([v], v.waiver_id in ^waiver_ids)
    |> distinct([v], v.waiver_id)
    |> order_by([v], asc: v.waiver_id, desc: v.version)
    |> Repo.all()
    |> Map.new(&{&1.waiver_id, &1})
  end

  defp latest_version(waiver_id) do
    WaiverVersion
    |> where([v], v.waiver_id == ^waiver_id)
    |> order_by([v], desc: v.version)
    |> limit(1)
    |> Repo.one()
  end

  defp insert_waiver_with_version(attrs, version_attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:waiver, Waiver.changeset(%Waiver{}, attrs))
    |> Ecto.Multi.insert(:version, fn %{waiver: waiver} ->
      WaiverVersion.changeset(%WaiverVersion{}, %{version_attrs | waiver_id: waiver.id})
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{waiver: waiver, version: version}} -> {:ok, %{waiver: waiver, version: version}}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  defp fetch_owned_waiver(provider_id, waiver_id) do
    case Repo.get(Waiver, waiver_id) do
      nil ->
        {:error, :not_found}

      waiver ->
        with :ok <- ensure_program_owned(provider_id, waiver.program_id), do: {:ok, waiver}
    end
  end

  # Program Catalog owns programs; Enrollment reads ownership off its facade (ADR 0015),
  # with the hop kept visible in traces.
  defp ensure_program_owned(provider_id, program_id) do
    acl_span source: "enrollment", target: "program_catalog" do
      case ProgramCatalog.get_program_for_provider(provider_id, program_id) do
        {:ok, _program} -> :ok
        {:error, :not_found} -> {:error, :not_found}
      end
    end
  end
end
