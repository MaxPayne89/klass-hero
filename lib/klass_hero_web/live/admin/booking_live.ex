defmodule KlassHeroWeb.Admin.BookingLive do
  @moduledoc """
  Backpex LiveResource for viewing bookings in the admin dashboard.

  Provides index and show views. Enrollments are read-only — the only
  mutation is the cancel item action which goes through the
  CancelEnrollmentByAdmin use case.

  Note: Backpex operates directly on Ecto schemas and Repo, bypassing
  the Ports & Adapters layering used elsewhere. This is a pragmatic
  exception scoped to admin-only read operations.
  """

  # Backpex requires FQ refs in `use` args — alias can't precede `use` per formatter rules
  # credo:disable-for-lines:10 Credo.Check.Design.AliasUsage
  use Backpex.LiveResource,
    adapter_config: [
      schema: KlassHero.Enrollment.Adapters.Driven.Persistence.Schemas.EnrollmentSchema,
      repo: KlassHero.Repo,
      update_changeset: &KlassHero.Enrollment.Adapters.Driven.Persistence.Schemas.EnrollmentSchema.admin_changeset/3,
      create_changeset: &KlassHero.Enrollment.Adapters.Driven.Persistence.Schemas.EnrollmentSchema.admin_changeset/3
    ],
    pubsub: [server: KlassHero.PubSub],
    init_order: %{by: :enrolled_at, direction: :desc}

  alias Backpex.Fields.BelongsTo
  alias Backpex.Fields.Text
  alias Backpex.Fields.Textarea
  alias KlassHeroWeb.Admin.Actions.CancelBookingAction
  alias KlassHeroWeb.Admin.Filters.StatusFilter

  @impl Backpex.LiveResource
  def layout(_assigns), do: {KlassHeroWeb.Layouts, :admin}

  # Trigger: :new, :edit, and :delete are not valid operations for bookings in admin
  # Why: bookings are created by parents; cancellation goes through the cancel item action
  # Outcome: hides "New" button, denies edit/delete actions
  @impl Backpex.LiveResource
  def can?(_assigns, :new, _item), do: false
  def can?(_assigns, :edit, _item), do: false
  def can?(_assigns, :delete, _item), do: false
  def can?(_assigns, :index, _item), do: true
  def can?(_assigns, :show, _item), do: true
  # Trigger: cancel action should only be available for cancellable statuses
  # Why: completed and cancelled enrollments cannot be cancelled again
  # Outcome: cancel button only appears for pending/confirmed enrollments
  def can?(_assigns, :cancel_booking, item), do: item.status in [:pending, :confirmed]
  def can?(_assigns, _action, _item), do: false

  @impl Backpex.LiveResource
  def filters do
    [status: %{module: StatusFilter}]
  end

  @impl Backpex.LiveResource
  def singular_name, do: "Booking"

  @impl Backpex.LiveResource
  def plural_name, do: "Bookings"

  @impl Backpex.LiveResource
  def item_actions(default_actions) do
    # Trigger: override default actions to add custom cancel action
    # Why: the cancel action calls through a domain use case, not a simple Backpex edit
    # Outcome: cancel button appears per-row for eligible bookings
    Keyword.put(default_actions, :cancel_booking, %{
      module: CancelBookingAction,
      only: [:row, :show]
    })
  end

  @impl Backpex.LiveResource
  def fields do
    [
      program: %{
        module: BelongsTo,
        label: "Program",
        display_field: :title,
        searchable: true,
        orderable: true,
        only: [:index, :show]
      },
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
        only: [:index, :show]
      },
      status: %{
        module: Text,
        label: "Status",
        orderable: true,
        render: fn assigns ->
          ~H"""
          <span class={[
            "inline-flex items-center rounded-full px-2 py-1 text-xs font-medium",
            status_badge_class(@value)
          ]}>
            {@value |> to_string() |> String.capitalize()}
          </span>
          """
        end
      },
      total_amount: %{
        module: Text,
        label: "Total",
        orderable: true,
        render: fn assigns ->
          ~H"""
          <span>
            <%= if @value do %>
              &euro;{Decimal.round(@value, 2)}
            <% else %>
              &mdash;
            <% end %>
          </span>
          """
        end
      },
      payment_method: %{
        module: Text,
        label: "Payment",
        only: [:show],
        render: fn assigns ->
          ~H"""
          <span>{String.capitalize(@value || "—")}</span>
          """
        end
      },
      enrolled_at: %{
        module: Text,
        label: "Enrolled At",
        orderable: true,
        render: fn assigns ->
          ~H"""
          <span>{if @value, do: Calendar.strftime(@value, "%b %d, %Y"), else: "—"}</span>
          """
        end
      },
      special_requirements: %{
        module: Textarea,
        label: "Special Requirements",
        only: [:show]
      },
      cancellation_reason: %{
        module: Text,
        label: "Cancellation Reason",
        only: [:show]
      },
      confirmed_at: %{
        module: Backpex.Fields.DateTime,
        label: "Confirmed At",
        only: [:show]
      },
      cancelled_at: %{
        module: Backpex.Fields.DateTime,
        label: "Cancelled At",
        only: [:show]
      }
    ]
  end

  defp status_badge_class(:pending), do: "bg-yellow-100 text-yellow-800"
  defp status_badge_class(:confirmed), do: "bg-green-100 text-green-800"
  defp status_badge_class(:completed), do: "bg-blue-100 text-blue-800"
  defp status_badge_class(:cancelled), do: "bg-red-100 text-red-800"
  defp status_badge_class(_), do: "bg-gray-100 text-gray-800"
end
