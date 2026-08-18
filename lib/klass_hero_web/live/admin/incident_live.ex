defmodule KlassHeroWeb.Admin.IncidentLive do
  @moduledoc """
  Backpex LiveResource for viewing incident reports across all providers.

  Strictly read-only — no create, edit, or delete. Incident reports are filed by
  providers and staff; the platform's interest is visibility (spotting safety
  patterns, responding to serious incidents), not authorship. Actioning an
  incident remains the provider's responsibility.

  Note: Backpex operates directly on Ecto schemas and Repo, bypassing
  the Ports & Adapters layering used elsewhere. This is a pragmatic
  exception scoped to admin-only read operations.

  ## Reads, not events

  Reports are queried directly. The row and its provider-notification Oban job
  already commit in one transaction (`SubmitIncidentReport`), so the data is
  durable before this view ever runs — there is no delivery to make reliable and
  therefore no integration event or projection here.

  ## Access and audit

  Every admin (`is_admin: true`) can read every report, including the free-text
  description and any photo. There are no admin sub-roles to scope this to, and
  no record is kept of which admin viewed which report. Photo links are signed
  with a short TTL but are bearer URLs for their lifetime.
  """

  # Backpex requires FQ refs in `use` args — alias can't precede `use` per formatter rules
  # credo:disable-for-lines:11 Credo.Check.Design.AliasUsage
  use Backpex.LiveResource,
    adapter_config: [
      schema: KlassHero.Provider.IncidentReport,
      repo: KlassHero.Repo,
      update_changeset: &KlassHero.Provider.IncidentReport.admin_changeset/3,
      create_changeset: &KlassHero.Provider.IncidentReport.admin_changeset/3,
      item_query: &__MODULE__.item_query/3
    ],
    pubsub: [server: KlassHero.PubSub],
    init_order: %{by: :occurred_at, direction: :desc},
    persist: [:columns]

  import Ecto.Query

  alias Backpex.Fields.Text
  alias Backpex.Fields.Textarea
  alias KlassHero.Provider.IncidentReport
  alias KlassHero.Shared.Storage
  alias KlassHeroWeb.Admin.Filters.IncidentCategoryFilter
  alias KlassHeroWeb.Admin.Filters.IncidentSeverityFilter
  alias KlassHeroWeb.Presenters.IncidentReportPresenter

  require Logger

  # Matches the admin verification-document viewer (`Provider.Verification`):
  # long enough to open and inspect in a browser, short enough to expire fast.
  @photo_url_ttl_seconds 900

  @impl Backpex.LiveResource
  def layout(_assigns), do: {KlassHeroWeb.Layouts, :admin}

  # Reports are filed by providers/staff and are an audit record — admins read only.
  @impl Backpex.LiveResource
  def can?(_assigns, :new, _item), do: false
  def can?(_assigns, :edit, _item), do: false
  def can?(_assigns, :delete, _item), do: false
  def can?(_assigns, :index, _item), do: true
  def can?(_assigns, :show, _item), do: true
  def can?(_assigns, _action, _item), do: false

  @impl Backpex.LiveResource
  def singular_name, do: "Incident Report"

  @impl Backpex.LiveResource
  def plural_name, do: "Incident Reports"

  @impl Backpex.LiveResource
  def filters do
    [
      severity: %{module: IncidentSeverityFilter},
      category: %{module: IncidentCategoryFilter}
    ]
  end

  @doc """
  Resolves the owning provider's and program's names into virtual fields.

  Joined on raw table names rather than through another context's schemas, so
  this stays a column-level read and imports nothing from Program Catalog.
  `programs` is a LEFT join because a report is polymorphic: exactly one of
  `program_id` / `session_id` is set (DB CHECK `one_of_program_or_session`), so
  session-scoped reports carry a NULL `program_id` and would vanish from an
  inner join.
  """
  def item_query(query, _live_action, _assigns) do
    from r in query,
      join: p in "providers",
      on: p.id == r.provider_id,
      left_join: prog in "programs",
      on: prog.id == r.program_id,
      select_merge: %{provider_name: p.business_name, program_title: prog.title}
  end

  @impl Backpex.LiveResource
  def render_resource_slot(assigns, :index, :before_main) do
    ~H"""
    <div class="mb-4 rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900">
      Read-only safety record. Reports contain child-safety details and are actioned
      by the provider, who is notified by email when a report is filed.
    </div>
    """
  end

  @impl Backpex.LiveResource
  def fields do
    [
      # `orderable: false` is load-bearing on both virtual fields. Backpex's
      # orderable default is `true`, and it validates `order_by` against the
      # orderable list — so leaving it out lets `?order_by=provider_name` through
      # to `ORDER BY i0."provider_name"`, a column that does not exist (42703).
      provider_name: %{
        module: Text,
        label: "Provider",
        only: [:index, :show],
        orderable: false
      },
      program_title: %{
        module: Text,
        label: "Target",
        only: [:index, :show],
        orderable: false,
        render: fn assigns ->
          ~H"""
          <span>
            <%= if @value do %>
              {@value}
            <% else %>
              <span class="text-gray-400 italic">Session report</span>
            <% end %>
          </span>
          """
        end
      },
      category: %{
        module: Text,
        label: "Category",
        orderable: true,
        render: fn assigns ->
          ~H"""
          <span>{IncidentReport.category_label(@value)}</span>
          """
        end
      },
      severity: %{
        module: Text,
        label: "Severity",
        orderable: true,
        render: fn assigns ->
          ~H"""
          <span class={[
            "inline-flex items-center rounded-full px-2 py-1 text-xs font-medium",
            severity_badge_class(@value)
          ]}>
            {IncidentReport.severity_label(@value)}
          </span>
          """
        end
      },
      reporter_display_name: %{
        module: Text,
        label: "Reported By",
        searchable: true,
        orderable: true
      },
      occurred_at: %{
        module: Backpex.Fields.DateTime,
        label: "Occurred At",
        orderable: true
      },
      description: %{
        module: Textarea,
        label: "Description",
        only: [:show]
      },
      photo_url: %{
        module: Text,
        label: "Photo",
        only: [:show],
        # The wrapping <div> is required, not cosmetic: Backpex.Fields.Text is a
        # stateful LiveComponent, so its root must be a single static HTML tag —
        # a bare component call or a top-level `if` raises at render time.
        render: fn assigns ->
          ~H"""
          <div>
            <.photo_preview storage_key={@value} />
          </div>
          """
        end
      }
    ]
  end

  # Signing happens at render time because Backpex owns mount/3, so there is no
  # earlier hook to stash the URL in. S3 presigning is local URL math, not a
  # round-trip, so re-signing per render is cheap.
  #
  # No `attr` declaration: `use Backpex.LiveResource` only *imports*
  # Phoenix.Component, and `attr/3` requires `use`.
  defp photo_preview(assigns) do
    assigns = assign(assigns, :signed_url, signed_photo_url(assigns.storage_key))

    ~H"""
    <%= if @signed_url do %>
      <a href={@signed_url} target="_blank" rel="noopener noreferrer">
        <img
          src={@signed_url}
          alt="Incident photo"
          class="max-h-64 rounded-lg border border-gray-200"
        />
      </a>
    <% else %>
      <span class="text-gray-400 italic">No photo</span>
    <% end %>
    """
  end

  defp signed_photo_url(nil), do: nil

  # Degrade to no photo rather than crash the page — mirrors
  # `NotifyIncidentReported.maybe_sign_photo/2`, which sends the email regardless.
  defp signed_photo_url(key) when is_binary(key) do
    case Storage.signed_url(:private, key, @photo_url_ttl_seconds) do
      {:ok, url} ->
        url

      {:error, reason} ->
        Logger.warning("[Admin.IncidentLive] photo signing failed, rendering without photo",
          photo_url: key,
          reason: inspect(reason)
        )

        nil
    end
  end

  defp severity_badge_class(severity) do
    case IncidentReportPresenter.severity_color(severity) do
      "error" -> "bg-red-100 text-red-800"
      "warning" -> "bg-amber-100 text-amber-800"
      "info" -> "bg-blue-100 text-blue-800"
      "success" -> "bg-green-100 text-green-800"
    end
  end
end
