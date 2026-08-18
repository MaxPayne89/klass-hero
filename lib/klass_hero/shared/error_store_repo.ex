defmodule KlassHero.Shared.ErrorStoreRepo do
  @moduledoc """
  The repo `error_tracker` writes through, so `reason` can be narrowed on its way to disk.

  `ErrorTracker.Repo` is not an Ecto repo — it is a dispatcher that calls
  `apply(Application.fetch_env!(:error_tracker, :repo), action, args ++ [opts])`. Every
  database call the dependency makes, reporting and dashboard alike, goes through it. Pointing
  `config :error_tracker, repo:` at this module therefore covers every report path at once —
  Phoenix, Oban, a manual `ErrorTracker.report/3`, and any integration a future version adds.

  That matters because the dependency offers no hook here: `ErrorTracker.Filter` sanitizes the
  *context* only, and `reason` — `Exception.message(exception)` — reaches storage unfiltered
  (#1398). This is the last point at which it can be narrowed.

  Everything other than `reason` on the two error-store schemas is delegated untouched. The set
  of functions below is not arbitrary: it is exactly what `ErrorTracker.Repo` dispatches, and
  `KlassHero.Shared.ErrorStoreRepoTest` fails if a dependency upgrade adds to that set.
  """

  alias Ecto.Changeset
  alias ErrorTracker.Error
  alias ErrorTracker.Occurrence
  alias KlassHero.Repo, as: AppRepo
  alias KlassHero.Shared.ErrorReasonFilter

  def insert!(%Error{reason: reason} = error, opts) when is_binary(reason) do
    AppRepo.insert!(%{error | reason: ErrorReasonFilter.sanitize(reason)}, opts)
  end

  def insert!(%Changeset{data: %Occurrence{}} = changeset, opts) do
    changeset
    |> Changeset.update_change(:reason, &ErrorReasonFilter.sanitize/1)
    |> AppRepo.insert!(opts)
  end

  def insert!(struct_or_changeset, opts), do: AppRepo.insert!(struct_or_changeset, opts)

  defdelegate update(changeset, opts), to: AppRepo
  defdelegate get(queryable, id, opts), to: AppRepo
  defdelegate get!(queryable, id, opts), to: AppRepo
  defdelegate one(queryable, opts), to: AppRepo
  defdelegate all(queryable, opts), to: AppRepo
  defdelegate delete_all(queryable, opts), to: AppRepo
  defdelegate aggregate(queryable, aggregate, opts), to: AppRepo
  defdelegate transaction(fun_or_multi, opts), to: AppRepo
  defdelegate __adapter__(), to: AppRepo
end
