defmodule KlassHeroWeb.Telemetry do
  use Supervisor

  import Telemetry.Metrics

  alias KlassHero.Shared.Interaction.TelemetryLogger
  alias KlassHero.Shared.Tracing.EctoSpanBridge

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    TelemetryLogger.attach()
    EctoSpanBridge.attach()

    children = [
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.start.system_time",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.socket_connected.duration",
        unit: {:native, :millisecond}
      ),
      sum("phoenix.socket_drain.count"),
      summary("phoenix.channel_joined.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: {:native, :millisecond}
      ),
      summary("klass_hero.repo.query.total_time",
        unit: {:native, :millisecond},
        description: "The sum of the other measurements"
      ),
      summary("klass_hero.repo.query.decode_time",
        unit: {:native, :millisecond},
        description: "The time spent decoding the data received from the database"
      ),
      summary("klass_hero.repo.query.query_time",
        unit: {:native, :millisecond},
        description: "The time spent executing the query"
      ),
      summary("klass_hero.repo.query.queue_time",
        unit: {:native, :millisecond},
        description: "The time spent waiting for a database connection"
      ),
      summary("klass_hero.repo.query.idle_time",
        unit: {:native, :millisecond},
        description: "The time the connection spent waiting before being checked out for the query"
      ),
      summary("phoenix.live_view.mount.stop.duration",
        tags: [:view],
        tag_values: &live_view_tag_values/1,
        unit: {:native, :millisecond}
      ),
      summary("phoenix.live_view.handle_params.stop.duration",
        tags: [:view],
        tag_values: &live_view_tag_values/1,
        unit: {:native, :millisecond}
      ),
      summary("phoenix.live_view.handle_event.stop.duration",
        tags: [:view],
        tag_values: &live_view_tag_values/1,
        unit: {:native, :millisecond}
      ),
      summary("phoenix.live_view.render.stop.duration",
        tags: [:view],
        tag_values: &live_view_tag_values/1,
        unit: {:native, :millisecond}
      ),
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io"),

      # Outbound adapter I/O envelope (KlassHero.Shared.Interaction)
      summary("klass_hero.interaction.stop.duration_us",
        unit: :microsecond,
        tags: [:io_kind, :operation, :status]
      ),
      counter("klass_hero.interaction.stop.count",
        tags: [:io_kind, :operation, :status]
      ),
      counter("klass_hero.interaction.exception.count",
        tags: [:io_kind, :operation]
      )
    ]
  end

  defp live_view_tag_values(metadata) do
    %{view: inspect(metadata.socket.view)}
  end

  defp periodic_measurements do
    []
  end
end
