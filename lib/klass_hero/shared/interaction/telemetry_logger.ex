defmodule KlassHero.Shared.Interaction.TelemetryLogger do
  @moduledoc """
  Logs failed interactions from the `[:klass_hero, :interaction, _]` telemetry
  family.

  Metric definitions in `KlassHeroWeb.Telemetry` are inert without a reporter in
  the tree; this handler gives immediate, structured visibility into errors and
  exceptions in the meantime. Attached once at boot via `attach/0`.

  Telemetry detaches any handler that raises, so `handle_event/4` is defensive
  and never lets an exception escape.
  """

  require Logger

  @stop_event [:klass_hero, :interaction, :stop]
  @exception_event [:klass_hero, :interaction, :exception]
  @handler_id "klass-hero-interaction-logger"

  @doc "Attaches the handler. Idempotent — a duplicate id is ignored."
  @spec attach() :: :ok
  def attach do
    case :telemetry.attach_many(@handler_id, [@stop_event, @exception_event], &__MODULE__.handle_event/4, %{}) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
    end
  end

  @doc false
  def handle_event(@exception_event, measurements, metadata, _config) do
    Logger.error(
      "interaction raised " <>
        fields(
          io_kind: metadata[:io_kind],
          operation: metadata[:operation],
          adapter: inspect(metadata[:adapter]),
          error_class: metadata[:kind],
          reason: inspect(metadata[:reason], limit: 200),
          duration_us: us(measurements)
        )
    )
  rescue
    _ -> :ok
  end

  def handle_event(@stop_event, measurements, %{status: :error} = metadata, _config) do
    Logger.warning(
      "interaction failed " <>
        fields(
          io_kind: metadata[:io_kind],
          operation: metadata[:operation],
          adapter: inspect(metadata[:adapter]),
          error: inspect(metadata[:error], limit: 200),
          duration_us: measurements[:duration_us]
        )
    )
  rescue
    _ -> :ok
  end

  def handle_event(_event, _measurements, _metadata, _config), do: :ok

  # Structured fields go in the message, not Logger metadata: the project's
  # metadata whitelist is explicit, so unlisted keys would be dropped silently.
  defp fields(pairs) do
    Enum.map_join(pairs, " ", fn {key, value} -> "#{key}=#{value}" end)
  end

  defp us(%{duration: native}), do: System.convert_time_unit(native, :native, :microsecond)
  defp us(_), do: nil
end
