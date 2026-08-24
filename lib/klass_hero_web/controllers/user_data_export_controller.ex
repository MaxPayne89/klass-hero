defmodule KlassHeroWeb.UserDataExportController do
  @moduledoc """
  Controller for GDPR data export functionality.

  Allows authenticated users to download all their personal data as JSON.
  """
  use KlassHeroWeb, :controller

  alias KlassHero.Accounts
  alias KlassHero.Family

  require Logger

  def export(conn, _params) do
    user = conn.assigns.current_scope.user
    account_data = Accounts.export_user_data(user)
    identity_data = Family.export_data_for_user(user.id)

    data = Map.merge(account_data, identity_data)

    case Jason.encode(data, pretty: true) do
      {:ok, json_data} ->
        filename = "klass_hero_data_export_#{Date.utc_today()}.json"

        send_download(conn, {:binary, json_data},
          filename: filename,
          content_type: "application/json"
        )

      {:error, reason} ->
        Logger.error("[UserDataExport] JSON encoding failed",
          user_id: user.id,
          reason: inspect(reason)
        )

        conn
        |> put_status(500)
        |> json(%{error: "export_failed"})
    end
  end
end
