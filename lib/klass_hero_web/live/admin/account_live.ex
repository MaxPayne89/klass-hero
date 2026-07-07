defmodule KlassHeroWeb.Admin.AccountLive do
  @moduledoc """
  Backpex LiveResource for the admin account overview.

  Provides index, show, and edit views for user management.
  Creation and deletion are intentionally disabled — users register
  themselves, and account deletion follows the GDPR anonymization flow.

  Note: Backpex operates directly on Ecto schemas and Repo, bypassing
  the Ports & Adapters layering used elsewhere. This is a pragmatic
  exception scoped to admin-only read + limited edit operations.
  """

  # Backpex requires FQ refs in `use` args — alias can't precede `use` per formatter rules
  # credo:disable-for-lines:11 Credo.Check.Design.AliasUsage
  use Backpex.LiveResource,
    adapter_config: [
      schema: KlassHero.Accounts.User,
      repo: KlassHero.Repo,
      update_changeset: &KlassHero.Accounts.User.admin_update_changeset/3,
      # Required by Backpex even though :new is disabled via can?/3
      create_changeset: &KlassHero.Accounts.User.admin_update_changeset/3,
      item_query: &__MODULE__.item_query/3
    ],
    pubsub: [server: KlassHero.PubSub],
    init_order: %{by: :inserted_at, direction: :desc}

  import Ecto.Query

  alias Backpex.Fields.Boolean
  alias Backpex.Fields.Text

  @impl Backpex.LiveResource
  def layout(_assigns), do: {KlassHeroWeb.Layouts, :admin}

  # :new denied (users self-register); deletion uses GDPR anonymization flow.
  @impl Backpex.LiveResource
  def can?(_assigns, :new, _item), do: false
  def can?(_assigns, :index, _item), do: true
  def can?(_assigns, :show, _item), do: true

  # Prevent self-edit: toggling own is_admin would lock the admin out.
  def can?(assigns, :edit, item), do: item.id != assigns.current_scope.user.id

  def can?(_assigns, _action, _item), do: false

  @doc false
  # Edit only needs is_admin toggle; roles/subscription fields are index/show-only, so skip preloads.
  def item_query(query, :edit, _assigns), do: query

  def item_query(query, _live_action, _assigns) do
    from u in query, preload: [:parent_profile, :provider_profile]
  end

  @impl Backpex.LiveResource
  def singular_name, do: "Account"

  @impl Backpex.LiveResource
  def plural_name, do: "Accounts"

  @impl Backpex.LiveResource
  def fields do
    [
      email: %{
        module: Text,
        label: "Email",
        searchable: true,
        orderable: true,
        readonly: true
      },
      name: %{
        module: Text,
        label: "Name",
        searchable: true,
        orderable: true,
        readonly: true
      },
      roles: %{
        module: Text,
        label: "Roles",
        readonly: true,
        only: [:index, :show],
        render: fn assigns ->
          ~H"""
          <div class="flex flex-wrap gap-1">
            <%= if @item.parent_profile do %>
              <span class="inline-flex items-center rounded-full px-2 py-1 text-xs font-medium bg-blue-100 text-blue-700">
                Parent
              </span>
            <% end %>
            <%= if @item.provider_profile do %>
              <span class="inline-flex items-center rounded-full px-2 py-1 text-xs font-medium bg-purple-100 text-purple-700">
                Provider
              </span>
            <% end %>
            <%= if @item.is_admin do %>
              <span class="inline-flex items-center rounded-full px-2 py-1 text-xs font-medium bg-red-100 text-red-700">
                Admin
              </span>
            <% end %>
            <%= if !@item.parent_profile && !@item.provider_profile && !@item.is_admin do %>
              <span class="inline-flex items-center rounded-full px-2 py-1 text-xs font-medium bg-gray-100 text-gray-700">
                User
              </span>
            <% end %>
          </div>
          """
        end
      },
      is_admin: %{
        module: Boolean,
        label: "Admin",
        only: [:edit]
      },
      inserted_at: %{
        module: Backpex.Fields.DateTime,
        label: "Created At",
        only: [:index, :show],
        orderable: true
      }
    ]
  end
end
