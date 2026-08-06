defmodule KlassHeroWeb.Admin.UndeliveredEventLive do
  @moduledoc """
  Backpex LiveResource for viewing integration events that were never delivered.

  Strictly read-only — no create, edit, or delete. A row here is a terminal
  record: `EventDeliveryWorker.compensate/2` writes it once delivery has given up
  permanently, and nothing but the 90-day prune touches it again.

  Note: Backpex operates directly on Ecto schemas and Repo, bypassing
  the Ports & Adapters layering used elsewhere. This is a pragmatic
  exception scoped to admin-only read operations.

  ## Reads, not events

  There is no projection and no event behind this view. The failure it reports is
  the one place in the system where delivery has already stopped being reliable —
  making the record itself reliable is what PR #1250 did; this only shows it.

  ## Access

  Every admin (`is_admin: true`) can read every envelope, including whatever
  personal data the event carried — the same data `ErrorContextFilter` redacts
  from ErrorTracker. That exposure is deliberate rather than accidental: the
  envelope is what a replay would be built from, so redacting it here would leave
  the page unable to answer the question it exists for. There are no admin
  sub-roles to scope this to, and no record is kept of which admin read which
  envelope — identical to `KlassHeroWeb.Admin.IncidentLive`.
  """

  # Backpex requires FQ refs in `use` args — alias can't precede `use` per formatter rules
  # credo:disable-for-lines:10 Credo.Check.Design.AliasUsage
  use Backpex.LiveResource,
    adapter_config: [
      schema: KlassHero.Shared.Adapters.Driven.Persistence.Schemas.UndeliveredEvent,
      repo: KlassHero.Repo
    ],
    # Identity is `event_id`; the schema is `@primary_key false`. Backpex defaults this
    # to `:id` and threads it through URL building, row DOM ids, and the show query.
    primary_key: :event_id,
    pubsub: [server: KlassHero.PubSub],
    init_order: %{by: :discarded_at, direction: :desc}

  alias Backpex.Fields.Text

  @impl Backpex.LiveResource
  def layout(_assigns), do: {KlassHeroWeb.Layouts, :admin}

  # Written by the compensation sweep, pruned on a schedule — admins read only.
  @impl Backpex.LiveResource
  def can?(_assigns, :index, _item), do: true
  def can?(_assigns, :show, _item), do: true
  def can?(_assigns, _action, _item), do: false

  @impl Backpex.LiveResource
  def singular_name, do: "Undelivered Event"

  @impl Backpex.LiveResource
  def plural_name, do: "Undelivered Events"

  @impl Backpex.LiveResource
  def render_resource_slot(assigns, :index, :before_main) do
    ~H"""
    <div class="mb-4 rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900">
      Reactions that never ran. Each row is one integration event delivery gave up on —
      replaying it means re-inserting its delivery job, and records are pruned 90 days
      after they are recorded.
    </div>
    """
  end

  @impl Backpex.LiveResource
  def fields do
    [
      topic: %{
        module: Text,
        label: "Topic",
        searchable: true,
        orderable: true
      },
      # Registry order is delivery order, and `EventDeliveryWorker` preserves it —
      # the list tells you which consumer ran last and where the failure stopped.
      # One per line, because a joined cell squeezed the timestamp column to nothing.
      missed_consumers: %{
        module: Text,
        label: "Missed Consumers",
        orderable: false,
        # The wrapping <div> is required, not cosmetic: Backpex.Fields.Text is a
        # stateful LiveComponent, so its root must be a single static HTML tag.
        render: fn assigns ->
          ~H"""
          <div class="font-mono text-xs">
            <div :for={consumer <- @value}>{short_consumer(consumer)}</div>
          </div>
          """
        end
      },
      # Age is rendered here rather than added as a virtual column. Backpex's
      # `orderable` default is `true` and it validates `order_by` against the
      # orderable list, so a virtual `age` would let `?order_by=age` through to
      # `ORDER BY u0."age"` — a column that does not exist (42703).
      discarded_at: %{
        module: Text,
        label: "Discarded At",
        orderable: true,
        render: fn assigns ->
          ~H"""
          <div>
            {Calendar.strftime(@value, "%Y-%m-%d %H:%M UTC")}
            <span class="text-gray-400">({age(@value)})</span>
          </div>
          """
        end
      },
      job_id: %{
        module: Text,
        label: "Oban Job",
        only: [:show],
        orderable: false
      },
      payload: %{
        module: Text,
        label: "Envelope",
        only: [:show],
        orderable: false,
        render: fn assigns ->
          ~H"""
          <div>
            <pre
              phx-no-curly-interpolation
              class="overflow-x-auto rounded bg-gray-50 p-3 text-xs"
            ><%= Jason.encode!(@value, pretty: true) %></pre>
          </div>
          """
        end
      }
    ]
  end

  # `EventDeliveryWorker` stores a fully-qualified handler ref
  # ("Elixir.KlassHero.Family.Adapters.Driving.Events.FamilyEventHandler:handle_event").
  # The context and the handler name are the signal; the fixed `Adapters.Driving.Events`
  # path in between is boilerplate that pushed every other column off the table.
  defp short_consumer(ref) when is_binary(ref) do
    ref
    |> String.replace_prefix("Elixir.KlassHero.", "")
    |> String.replace(".Adapters.Driving.Events.", ".")
  end

  # No relative-time helper exists app-wide, and the only consumer is this column.
  # Days are the unit that matters: the record is pruned at 90 of them.
  defp age(%DateTime{} = discarded_at) do
    case DateTime.diff(DateTime.utc_now(), discarded_at, :second) do
      seconds when seconds < 3600 -> "#{div(seconds, 60)}m ago"
      seconds when seconds < 86_400 -> "#{div(seconds, 3600)}h ago"
      seconds -> "#{div(seconds, 86_400)}d ago"
    end
  end
end
