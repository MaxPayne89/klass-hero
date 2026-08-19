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

  alias KlassHero.Enrollment.Enrollment
  alias KlassHero.Enrollment.Waiver
  alias KlassHero.Enrollment.WaiverAcceptance
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

  @doc """
  The waivers in force for an enrollment's program, each marked signed or not.

  Drives both the booking form's checkboxes and the standalone signing page.
  """
  @spec list_enrollment_waivers(binary()) :: [%{waiver: Waiver.t(), version: WaiverVersion.t(), signed?: boolean()}]
  def list_enrollment_waivers(enrollment_id) do
    case Repo.get(Enrollment, enrollment_id) do
      nil ->
        []

      enrollment ->
        signed = signed_waiver_ids(enrollment_id)

        for entry <- list_program_waivers(enrollment.program_id),
            do: Map.put(entry, :signed?, entry.waiver.id in signed)
    end
  end

  @doc """
  Records signatures on an enrollment that already exists — the deferred path.

  Only the enrolling parent may sign: `parent_id` must match `enrollment.parent_id`, else
  `{:error, :not_found}`. The enrollment's own `program_id` decides which versions are
  signable, so a version id from another program is ignored rather than trusted.
  """
  @spec sign_waivers(binary(), binary(), [binary()], map()) ::
          {:ok, [WaiverAcceptance.t()]} | {:error, :not_found | Ecto.Changeset.t()}
  def sign_waivers(enrollment_id, parent_id, version_ids, audit) do
    with {:ok, enrollment} <- fetch_enrollment_for_parent(enrollment_id, parent_id) do
      signable =
        Repo
        |> current_versions_for_program(enrollment.program_id)
        |> Enum.filter(&(&1.id in version_ids))
        |> Enum.map(& &1.version)

      record_acceptances(Repo, signable, %{enrollment_id: enrollment.id, parent_id: parent_id}, audit)
    end
  end

  @doc """
  Waiver status per enrollment, for the provider roster.

  `:not_required` when the program has no required waivers at all — distinct from `:signed`,
  because "nothing to sign" and "signed everything" mean different things to a provider
  looking for who still owes them a form.
  """
  @spec waiver_status_for_enrollments([binary()]) :: %{binary() => :signed | :unsigned | :not_required}
  def waiver_status_for_enrollments([]), do: %{}

  def waiver_status_for_enrollments(enrollment_ids) do
    enrollments =
      Enrollment
      |> where([e], e.id in ^enrollment_ids)
      |> select([e], {e.id, e.program_id})
      |> Repo.all()

    required_by_program =
      enrollments
      |> Enum.map(&elem(&1, 1))
      |> Enum.uniq()
      |> Map.new(&{&1, MapSet.new(list_required_waiver_versions(&1), fn v -> v.waiver_id end)})

    signed_by_enrollment = signed_waiver_ids_by_enrollment(enrollment_ids)

    Map.new(enrollments, fn {id, program_id} ->
      required = Map.get(required_by_program, program_id, MapSet.new())
      signed = Map.get(signed_by_enrollment, id, MapSet.new())

      cond do
        MapSet.size(required) == 0 -> {id, :not_required}
        MapSet.subset?(required, signed) -> {id, :signed}
        true -> {id, :unsigned}
      end
    end)
  end

  defp fetch_enrollment_for_parent(enrollment_id, parent_id) do
    case Repo.get(Enrollment, enrollment_id) do
      # Same shape as the create path's ownership guard: a foreign enrollment is
      # indistinguishable from a missing one, so probing tells an attacker nothing.
      %Enrollment{parent_id: ^parent_id} = enrollment -> {:ok, enrollment}
      _otherwise -> {:error, :not_found}
    end
  end

  # Signatures are counted per *waiver*, never per version — the `(enrollment_id, waiver_id)`
  # unique index says one signature per waiver is the whole obligation, and decision 8 says a
  # later version binds future enrollments only. Counting per version would both report a
  # signed parent as unsigned and invite a re-sign that index refuses.
  defp signed_waiver_ids(enrollment_id) do
    WaiverAcceptance
    |> where([a], a.enrollment_id == ^enrollment_id)
    |> select([a], a.waiver_id)
    |> Repo.all()
    |> MapSet.new()
  end

  defp signed_waiver_ids_by_enrollment(enrollment_ids) do
    WaiverAcceptance
    |> where([a], a.enrollment_id in ^enrollment_ids)
    |> select([a], {a.enrollment_id, a.waiver_id})
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {id, waiver_ids} -> {id, MapSet.new(waiver_ids)} end)
  end

  @doc """
  Validates the caller's waiver intent.

  There is deliberately no default. `[]` would read as both "signed nothing" and "don't
  care", so a caller that forgets the key would silently skip the gate — the same
  bypass-by-omission that putting the gate in the LiveView would produce. Missing intent is
  an error instead.
  """
  @spec validate_intent(map()) :: {:ok, :deferred | {:accepted, [binary()]}} | {:error, :waiver_intent_required}
  def validate_intent(%{waivers: :deferred}), do: {:ok, :deferred}

  def validate_intent(%{waivers: {:accepted, ids}}) when is_list(ids), do: {:ok, {:accepted, ids}}

  def validate_intent(_params), do: {:error, :waiver_intent_required}

  @doc """
  Resolves which waiver versions a signature set actually covers, failing if a required one
  is missing.

  Runs on the caller's transaction connection, because a provider publishing a required
  waiver between a pre-flight check and the insert would otherwise produce an enrollment
  with an unsigned required waiver — the same TOCTOU the capacity lock exists to prevent.

  Ids that do not belong to this program's active waivers are ignored rather than rejected;
  they cannot satisfy a requirement, and treating a stale id as a hard error would turn a
  harmless double-submit into a failed enrolment.
  """
  @spec resolve_acceptances(Ecto.Repo.t(), binary() | nil, :deferred | {:accepted, [binary()]}) ::
          {:ok, [WaiverVersion.t()]} | {:error, :waivers_unsigned}
  def resolve_acceptances(_repo, _program_id, :deferred), do: {:ok, []}

  def resolve_acceptances(_repo, nil, _intent), do: {:ok, []}

  def resolve_acceptances(repo, program_id, {:accepted, ids}) do
    current = current_versions_for_program(repo, program_id)
    accepted = Enum.filter(current, &(&1.id in ids))
    required_ids = for %{required: true, version: v} <- current, do: v.id

    if Enum.all?(required_ids, fn id -> Enum.any?(accepted, &(&1.version.id == id)) end) do
      {:ok, Enum.map(accepted, & &1.version)}
    else
      {:error, :waivers_unsigned}
    end
  end

  @doc """
  Inserts one acceptance per signed version, on the caller's transaction connection.
  """
  @spec record_acceptances(Ecto.Repo.t(), [WaiverVersion.t()], map(), map()) ::
          {:ok, [WaiverAcceptance.t()]} | {:error, Ecto.Changeset.t()}
  def record_acceptances(repo, versions, signer, audit) do
    Enum.reduce_while(versions, {:ok, []}, fn version, {:ok, acc} ->
      %WaiverAcceptance{}
      |> WaiverAcceptance.changeset(WaiverAcceptance.accept(version, signer, audit))
      |> repo.insert()
      |> case do
        {:ok, acceptance} -> {:cont, {:ok, [acceptance | acc]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  # Active waivers on the program paired with their current version, flattened so the gate
  # can filter on `required` and match on `version.id` in one pass.
  defp current_versions_for_program(repo, program_id) do
    waivers =
      Waiver
      |> where([w], w.program_id == ^program_id and is_nil(w.archived_at))
      |> repo.all()

    case waivers do
      [] ->
        []

      waivers ->
        versions =
          WaiverVersion
          |> where([v], v.waiver_id in ^Enum.map(waivers, & &1.id))
          |> distinct([v], v.waiver_id)
          |> order_by([v], asc: v.waiver_id, desc: v.version)
          |> repo.all()
          |> Map.new(&{&1.waiver_id, &1})

        for waiver <- waivers,
            version = Map.get(versions, waiver.id),
            do: %{id: version.id, required: waiver.required, version: version}
    end
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
