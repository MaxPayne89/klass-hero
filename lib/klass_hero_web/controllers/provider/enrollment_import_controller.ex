defmodule KlassHeroWeb.Provider.EnrollmentImportController do
  @moduledoc """
  Handles CSV-based bulk enrollment imports for providers.

  Accepts a CSV file upload, delegates to the Enrollment context for parsing,
  validation, and persistence, then returns a JSON response.
  """
  use KlassHeroWeb, :controller

  alias KlassHero.Accounts.Scope
  alias KlassHero.Enrollment

  require Logger

  # Trigger: CSV files from real enrollment rosters are typically under 500KB.
  # Why: 2MB gives generous headroom while preventing abuse from multi-MB uploads
  #   that would consume memory during parsing. Checked here rather than at the
  #   endpoint level because this is the only route accepting file uploads.
  # Outcome: requests with oversized files get a 413 before any CSV processing.
  @max_file_size 2_000_000

  def create(conn, params) do
    with {:ok, provider_id} <- resolve_provider(conn),
         {:ok, csv_binary} <- read_upload(params) do
      Logger.info("[EnrollmentImport] Starting CSV import",
        provider_id: provider_id,
        file_size: byte_size(csv_binary)
      )

      case Enrollment.import_enrollment_csv(provider_id, csv_binary) do
        {:ok, report} ->
          Logger.info("[EnrollmentImport] Import complete",
            provider_id: provider_id,
            created: report.created,
            failed: length(report.failed)
          )

          conn |> put_status(:ok) |> json(format_report(report))

        {:error, %{parse_errors: _} = error_report} ->
          Logger.warning("[EnrollmentImport] Import failed (whole-file fatal)",
            provider_id: provider_id
          )

          conn
          |> put_status(:unprocessable_entity)
          |> json(%{errors: format_fatal(error_report)})
      end
    else
      {:error, :not_provider} ->
        conn |> put_status(:forbidden) |> json(%{error: "Provider profile required"})

      {:error, :no_file} ->
        conn |> put_status(:bad_request) |> json(%{error: "No file uploaded"})

      {:error, :file_too_large} ->
        conn
        |> put_status(:request_entity_too_large)
        |> json(%{error: "File too large (max 2MB)"})
    end
  end

  # -- private helpers -------------------------------------------------------

  # Trigger: the current user may or may not have a provider profile.
  # Why: we resolve roles inline instead of a dedicated plug because this is
  #   currently the only provider controller endpoint — YAGNI on a plug until
  #   we have multiple endpoints that need the same check.
  # Outcome: returns the provider's UUID or a tagged error for the `with` chain.
  defp resolve_provider(conn) do
    scope =
      conn.assigns.current_scope
      |> Scope.resolve_roles()

    if Scope.provider?(scope) do
      {:ok, scope.provider.id}
    else
      {:error, :not_provider}
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp read_upload(%{"file" => %Plug.Upload{path: path}}) do
    stat = File.stat!(path)

    if stat.size > @max_file_size do
      {:error, :file_too_large}
    else
      {:ok, File.read!(path)}
    end
  end

  defp read_upload(_params), do: {:error, :no_file}

  # Trigger: the use case now returns {:ok, %{created: n, failed: [...]}} for
  #   all row-level outcomes (full success, mixed, all-failed).
  # Why: partial success is the normal case — we must serialise the structured
  #   failed list so the client knows which rows to remediate.
  # Outcome: a flat map with integer `created` and a list of failed-row maps.
  defp format_report(%{created: created, failed: failed}) do
    %{
      created: created,
      failed:
        Enum.map(failed, fn %{row: row, category: category, errors: errors} ->
          %{
            row: row,
            category: Atom.to_string(category),
            errors: format_errors_field(errors)
          }
        end)
    }
  end

  defp format_errors_field(errors) when is_binary(errors), do: errors
  defp format_errors_field(errors) when is_list(errors), do: Map.new(errors)

  # Trigger: whole-file fatals carry `parse_errors` tuples that Jason cannot encode.
  # Why: tuples are not JSON-serializable; convert to maps for the HTTP response.
  # Outcome: `%{"parse_errors" => [%{row: n, message: "..."}]}`.
  defp format_fatal(%{parse_errors: errors}) do
    %{
      "parse_errors" => Enum.map(errors, fn {row, msg} -> %{row: row, message: msg} end)
    }
  end
end
