defmodule KlassHeroWeb.Admin.StaffLive do
  @moduledoc """
  Backpex LiveResource for managing staff members in the admin dashboard.

  Read-only (index and show): every field is provider-owned.

  Employment status is changed through the `Deactivate` / `Activate` item
  actions, which call `KlassHero.Provider`'s commands. Backpex otherwise writes
  straight to `Repo`, and that is exactly what #1237 removed here: the old
  editable `active` checkbox cast the column with none of deactivation's
  consequences — no lead-instructor clearing, no event, so read tables kept
  naming the departed staff member.
  """

  # Backpex requires FQ refs in `use` args — alias can't precede `use` per formatter rules
  # credo:disable-for-lines:10 Credo.Check.Design.AliasUsage
  use Backpex.LiveResource,
    adapter_config: [
      schema: KlassHero.Provider.StaffMember,
      repo: KlassHero.Repo,
      update_changeset: &KlassHero.Provider.StaffMember.admin_changeset/3,
      create_changeset: &KlassHero.Provider.StaffMember.admin_changeset/3
    ],
    pubsub: [server: KlassHero.PubSub],
    init_order: %{by: :inserted_at, direction: :desc}

  alias Backpex.Fields.BelongsTo
  alias Backpex.Fields.Boolean
  alias Backpex.Fields.Text
  alias Backpex.Fields.Textarea
  alias KlassHeroWeb.Admin.Actions.ActivateStaffAction
  alias KlassHeroWeb.Admin.Actions.DeactivateStaffAction
  alias KlassHeroWeb.Admin.Filters.ActiveFilter

  @impl Backpex.LiveResource
  def layout(_assigns), do: {KlassHeroWeb.Layouts, :admin}

  # Staff members are created/deleted by their providers — hides "New" button, denies create/delete.
  # `:edit` is denied too since #1237: `active` was the only editable field, and it now
  # moves through Provider's domain command, so the form has nothing left to write.
  # The two employment actions are opposite-gated, so exactly one shows per row.
  @impl Backpex.LiveResource
  def can?(_assigns, :new, _item), do: false
  def can?(_assigns, :delete, _item), do: false
  def can?(_assigns, :edit, _item), do: false
  def can?(_assigns, :index, _item), do: true
  def can?(_assigns, :show, _item), do: true
  def can?(_assigns, :deactivate_staff, item), do: item.active
  def can?(_assigns, :activate_staff, item), do: not item.active
  def can?(_assigns, _action, _item), do: false

  @impl Backpex.LiveResource
  def item_actions(default_actions) do
    default_actions
    |> Keyword.put(:deactivate_staff, %{module: DeactivateStaffAction, only: [:row, :show]})
    |> Keyword.put(:activate_staff, %{module: ActivateStaffAction, only: [:row, :show]})
  end

  @impl Backpex.LiveResource
  def filters do
    [active: %{module: ActiveFilter}]
  end

  @impl Backpex.LiveResource
  def singular_name, do: "Staff Member"

  @impl Backpex.LiveResource
  def plural_name, do: "Staff Members"

  @impl Backpex.LiveResource
  def fields do
    [
      first_name: %{
        module: Text,
        label: "First Name",
        searchable: true,
        orderable: true,
        readonly: true
      },
      last_name: %{
        module: Text,
        label: "Last Name",
        searchable: true,
        orderable: true,
        readonly: true
      },
      provider: %{
        module: BelongsTo,
        label: "Provider",
        display_field: :business_name,
        searchable: true,
        orderable: true,
        only: [:index, :show]
      },
      role: %{
        module: Text,
        label: "Role",
        searchable: true,
        orderable: true,
        readonly: true
      },
      email: %{
        module: Text,
        label: "Email",
        searchable: true,
        readonly: true
      },
      # No `readonly:` — Backpex.Fields.Boolean rejects the option, and it would be
      # redundant: can?(:edit) is false, so no form ever renders this field.
      active: %{
        module: Boolean,
        label: "Active",
        orderable: true
      },
      bio: %{
        module: Textarea,
        label: "Bio",
        only: [:show],
        readonly: true
      },
      tags: %{
        module: Text,
        label: "Tags",
        only: [:show],
        readonly: true,
        render: fn assigns ->
          ~H"""
          <p>{Enum.join(@value || [], ", ")}</p>
          """
        end
      },
      qualifications: %{
        module: Text,
        label: "Qualifications",
        only: [:show],
        readonly: true,
        render: fn assigns ->
          ~H"""
          <p>{Enum.join(@value || [], ", ")}</p>
          """
        end
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
