defmodule KlassHeroWeb.Admin.ConsentLive do
  @moduledoc """
  Backpex LiveResource for viewing consent records in the admin dashboard.

  Read-only overview — no grant, withdraw, or delete actions. Consent records
  are append-only for compliance; withdrawals are recorded with timestamps
  and records are never deleted.

  Note: Backpex operates directly on Ecto schemas and Repo, bypassing
  the Ports & Adapters layering used elsewhere. This is a pragmatic
  exception scoped to admin-only read operations.
  """

  # Backpex requires FQ refs in `use` args — alias can't precede `use` per formatter rules
  # credo:disable-for-lines:11 Credo.Check.Design.AliasUsage
  use Backpex.LiveResource,
    adapter_config: [
      schema: KlassHero.Family.Consent,
      repo: KlassHero.Repo,
      update_changeset: &KlassHero.Family.Consent.admin_changeset/3,
      create_changeset: &KlassHero.Family.Consent.admin_changeset/3,
      item_query: &__MODULE__.item_query/3
    ],
    pubsub: [server: KlassHero.PubSub],
    init_order: %{by: :inserted_at, direction: :desc}

  import Ecto.Query

  alias Backpex.Fields.BelongsTo
  alias Backpex.Fields.Text
  alias KlassHeroWeb.Admin.Filters.ConsentStatusFilter
  alias KlassHeroWeb.Admin.Filters.ConsentTypeFilter

  @impl Backpex.LiveResource
  def layout(_assigns), do: {KlassHeroWeb.Layouts, :admin}

  # Read-only compliance view: consents are granted/withdrawn by parents, not admins.
  @impl Backpex.LiveResource
  def can?(_assigns, :new, _item), do: false
  def can?(_assigns, :edit, _item), do: false
  def can?(_assigns, :delete, _item), do: false
  def can?(_assigns, :index, _item), do: true
  def can?(_assigns, :show, _item), do: true
  def can?(_assigns, _action, _item), do: false

  @impl Backpex.LiveResource
  def singular_name, do: "Consent"

  @impl Backpex.LiveResource
  def plural_name, do: "Consents"

  @impl Backpex.LiveResource
  def filters do
    [
      consent_type: %{module: ConsentTypeFilter},
      withdrawn_at: %{module: ConsentStatusFilter}
    ]
  end

  @doc false
  def item_query(query, _live_action, _assigns) do
    from c in query, preload: [:child, :parent]
  end

  @impl Backpex.LiveResource
  def render_resource_slot(assigns, :index, :before_main) do
    ~H"""
    <div class="mb-4 rounded-lg border border-blue-200 bg-blue-50 p-3 text-sm text-blue-800">
      Consent records are append-only for compliance. Withdrawals are recorded
      with timestamps — records are never deleted.
    </div>
    """
  end

  @impl Backpex.LiveResource
  def fields do
    [
      child: %{
        module: BelongsTo,
        label: "Child",
        display_field: :first_name,
        searchable: true,
        only: [:index, :show],
        render: fn assigns ->
          ~H"""
          <span>
            <%= if @value do %>
              {@value.first_name} {@value.last_name}
            <% else %>
              <span class="text-gray-400 italic">Deleted</span>
            <% end %>
          </span>
          """
        end
      },
      parent: %{
        module: BelongsTo,
        label: "Parent",
        display_field: :display_name,
        searchable: true,
        only: [:index, :show],
        render: fn assigns ->
          ~H"""
          <span>
            <%= if @value do %>
              {@value.display_name}
            <% else %>
              <span class="text-gray-400 italic">Deleted</span>
            <% end %>
          </span>
          """
        end
      },
      consent_type: %{
        module: Text,
        label: "Type",
        searchable: true,
        orderable: true,
        render: fn assigns ->
          ~H"""
          <span>{humanize_consent_type(@value)}</span>
          """
        end
      },
      status: %{
        module: Text,
        label: "Status",
        only: [:index, :show],
        render: fn assigns ->
          ~H"""
          <span class={[
            "inline-flex items-center rounded-full px-2 py-1 text-xs font-medium",
            status_badge_class(@item)
          ]}>
            {status_label(@item)}
          </span>
          """
        end
      },
      granted_at: %{
        module: Backpex.Fields.DateTime,
        label: "Granted At",
        orderable: true
      },
      withdrawn_at: %{
        module: Backpex.Fields.DateTime,
        label: "Withdrawn At",
        only: [:show]
      }
    ]
  end

  @doc """
  Converts a snake_case consent type string to Title Case for display.
  Shared with `ConsentTypeFilter`.
  """
  def humanize_consent_type(type) when is_binary(type) do
    type
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  def humanize_consent_type(_), do: "—"

  defp status_badge_class(%{withdrawn_at: nil}), do: "bg-green-100 text-green-800"
  defp status_badge_class(%{withdrawn_at: _}), do: "bg-amber-100 text-amber-800"

  defp status_label(%{withdrawn_at: nil}), do: "Active"
  defp status_label(%{withdrawn_at: _}), do: "Withdrawn"
end
