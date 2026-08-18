defmodule KlassHeroWeb.Admin.ProviderLive do
  @moduledoc """
  Backpex LiveResource for managing provider profiles in the admin dashboard.

  Provides index, show, and edit views. Only verified status is
  editable — all other fields are provider-owned.

  Note: Backpex operates directly on Ecto schemas and Repo, bypassing
  the Ports & Adapters layering used elsewhere. This is a pragmatic
  exception scoped to admin-only read + limited edit operations.
  The `on_item_updated/2` callback bridges back into the domain layer by
  routing the verification change through the context, which is what the
  read-model projections depend on.
  """

  # Backpex requires FQ refs in `use` args — alias can't precede `use` per formatter rules
  # credo:disable-for-lines:10 Credo.Check.Design.AliasUsage
  use Backpex.LiveResource,
    adapter_config: [
      schema: KlassHero.Provider.ProviderProfile,
      repo: KlassHero.Repo,
      update_changeset: &KlassHero.Provider.ProviderProfile.admin_changeset/3,
      create_changeset: &KlassHero.Provider.ProviderProfile.admin_changeset/3
    ],
    pubsub: [server: KlassHero.PubSub],
    init_order: %{by: :inserted_at, direction: :desc},
    persist: [:columns]

  alias Backpex.Fields.Boolean
  alias Backpex.Fields.Text
  alias Backpex.Fields.Textarea
  alias KlassHero.Provider
  alias KlassHeroWeb.Admin.Filters.VerifiedFilter

  require KlassHeroWeb.BackpexCompat
  require Logger

  @impl Backpex.LiveResource
  def layout(_assigns), do: {KlassHeroWeb.Layouts, :admin}

  # Providers create their own profiles; deletion follows GDPR process — hides "New" button, denies create/delete.
  @impl Backpex.LiveResource
  def can?(_assigns, :new, _item), do: false
  def can?(_assigns, :delete, _item), do: false
  def can?(_assigns, :index, _item), do: true
  def can?(_assigns, :show, _item), do: true
  def can?(_assigns, :edit, _item), do: true
  def can?(_assigns, _action, _item), do: false

  @impl Backpex.LiveResource
  def filters do
    [verified: %{module: VerifiedFilter}]
  end

  @impl Backpex.LiveResource
  def singular_name, do: "Provider"

  @impl Backpex.LiveResource
  def plural_name, do: "Providers"

  @impl Backpex.LiveResource
  def fields do
    [
      business_name: %{
        module: Text,
        label: "Business Name",
        searchable: true,
        orderable: true,
        readonly: true
      },
      verified: %{
        module: Boolean,
        label: "Verified",
        orderable: true
      },
      description: %{
        module: Textarea,
        label: "Description",
        only: [:show],
        readonly: true
      },
      phone: %{
        module: Text,
        label: "Phone",
        only: [:show],
        readonly: true
      },
      website: %{
        module: Text,
        label: "Website",
        only: [:show],
        readonly: true
      },
      address: %{
        module: Text,
        label: "Address",
        only: [:show],
        readonly: true
      },
      categories: %{
        module: Text,
        label: "Categories",
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

  # admin_changeset bypasses the domain use cases, so route the change back
  # through the context, keeping `verified`, `verified_at` and `verified_by_id`
  # consistent and the write auditable like every other producer's (#1210).
  KlassHeroWeb.BackpexCompat.override :on_item_updated, 2 do
    @impl Backpex.LiveResource
    def on_item_updated(socket, item) do
      old_item = socket.assigns.item

      record_verification_change(old_item, item, socket)

      socket
    end
  end

  defp record_verification_change(%{verified: same}, %{verified: same}, _socket), do: :ok

  # Re-runs the write Backpex just did, through the context, so verification goes
  # through one path (#1210). Since #1195 nothing consumes `provider_verified`, so
  # what this preserves is the audit trail and the single mutator — program cards
  # read the `verified` fact directly via `Provider.get_trust_states/1`. Both facade
  # functions are idempotent, so re-persisting the same values is safe.
  defp record_verification_change(_old, %{verified: verified} = item, socket) do
    admin_id = socket.assigns.current_scope.user.id

    case verification_result(verified, item.id, admin_id) do
      {:ok, _profile} ->
        :ok

      {:error, reason} ->
        Logger.error("Admin verification change did not reach the domain: verified=#{verified}",
          provider_id: item.id,
          reason: inspect(reason)
        )

        :ok
    end
  end

  defp verification_result(true, provider_id, admin_id), do: Provider.verify_provider(provider_id, admin_id)
  defp verification_result(false, provider_id, admin_id), do: Provider.unverify_provider(provider_id, admin_id)
end
