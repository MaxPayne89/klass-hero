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

  # 2MB: headroom over typical <500KB rosters; only this route accepts uploads so checked here.
  @max_file_size 2_000_000

  def create(conn, params) do
    with {:ok, provider_id} <- resolve_provider(conn),
         {:ok, csv_binary} <- read_upload(params) do
      Logger.info("[EnrollmentImport] Starting CSV import",
        provider_id: provider_id,
        file_size: byte_size(csv_binary)
      )

      case Enrollment.import_enrollment_csv(provider_id, csv_binary) do
        {:ok, %{created: _, failed: []} = report} ->
          Logger.info("[EnrollmentImport] Import complete",
            provider_id: provider_id,
            created: report.created,
            failed: 0
          )

          # 201 reserved for full success; pre-refactor clients branch on this.
          conn |> put_status(:created) |> json(format_report(report))

        {:ok, report} ->
          Logger.info("[EnrollmentImport] Import complete",
            provider_id: provider_id,
            created: report.created,
            failed: length(report.failed)
          )

          # 200 (not 201) signals partial/all-failed; caller inspects `failed` to remediate.
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

  # Inline role check rather than a plug — only one provider controller endpoint (YAGNI).
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

  # Group by field: `Map.new/1` would drop duplicate-field tuples, losing messages.
  defp format_errors_field(errors) when is_list(errors) do
    errors
    |> Enum.group_by(fn {field, _msg} -> field end, fn {_field, msg} -> msg end)
    |> Map.new()
  end

  # Tuples are not JSON-serializable; convert parse_error tuples to maps.
  defp format_fatal(%{parse_errors: errors}) do
    %{
      "parse_errors" => Enum.map(errors, fn {row, msg} -> %{row: row, message: msg} end)
    }
  end
end
