defmodule KlassHero.Provider.AnonymizeUserData do
  @moduledoc """
  The Provider context's slice of the GDPR erasure cascade.

  Accounts anonymises the `users` row in place (it is never deleted), then
  publishes `:user_anonymized`. This use case scrubs the two Provider-owned
  surfaces that denormalise user-derived PII:

    * `staff_members` — name, email, bio, headshot; the row is also deactivated
      and any outstanding invitation revoked.
    * `incident_reports.reporter_display_name` — the report itself is a safety
      record and survives, de-identified.

  Both run in one transaction so a user can never end up half-anonymised.
  """

  import Ecto.Query, only: [from: 2]

  alias KlassHero.Provider.IncidentReport
  alias KlassHero.Provider.Staff
  alias KlassHero.Provider.StaffMember
  alias KlassHero.Repo

  require Logger

  @doc """
  Anonymises all Provider-owned data for a user.

  Returns `{:ok, :no_data}` when the user owns neither surface, otherwise
  `{:ok, %{incident_reports: n, staff_members: n}}`. Idempotent — re-running
  rewrites the same tombstones and reports the same counts.
  """
  @spec execute(binary()) :: {:ok, map()} | {:ok, :no_data} | {:error, term()}
  def execute(user_id) when is_binary(user_id) do
    case Repo.transaction(fn -> anonymize_all(user_id) end) do
      {:ok, :no_data} ->
        {:ok, :no_data}

      {:ok, counts} ->
        Logger.info("Anonymized provider data for user",
          user_id: user_id,
          incident_reports_anonymized: counts.incident_reports,
          staff_members_anonymized: counts.staff_members
        )

        {:ok, counts}

      {:error, reason} = error ->
        Logger.error("Failed to anonymize provider data for user", user_id: user_id, reason: inspect(reason))
        error
    end
  end

  defp anonymize_all(user_id) do
    reports = Repo.all(from r in IncidentReport, where: r.reporter_user_id == ^user_id)
    staff = Repo.all(from s in StaffMember, where: s.user_id == ^user_id)

    case {reports, staff} do
      {[], []} ->
        :no_data

      _ ->
        Enum.each(reports, &update!(IncidentReport.anonymize_changeset(&1)))
        Enum.each(staff, &erase_staff_member/1)

        %{incident_reports: length(reports), staff_members: length(staff)}
    end
  end

  # Erasure is an ending of employment plus a scrub, and the ordering is
  # load-bearing: deactivate_staff_member/1 short-circuits on an already-inactive
  # row, so scrubbing first (which sets active: false) would silently skip the
  # lead-instructor clearing and the event that clears the erased name from read
  # tables. Deactivate, then scrub.
  defp erase_staff_member(staff) do
    case Staff.deactivate_staff_member(staff) do
      {:ok, deactivated} -> update!(StaffMember.anonymize_changeset(deactivated))
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  # Rolls the transaction back on the first bad row rather than leaving a user
  # half-anonymised; execute/1 surfaces it as {:error, changeset}.
  defp update!(changeset) do
    case Repo.update(changeset) do
      {:ok, record} -> record
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end
end
