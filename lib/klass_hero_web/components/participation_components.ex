defmodule KlassHeroWeb.ParticipationComponents do
  @moduledoc """
  Components for participation check-in/out workflows and session management.
  """
  use Phoenix.Component
  use Gettext, backend: KlassHeroWeb.Gettext

  import KlassHeroWeb.CoreComponents, only: [input: 1]
  import KlassHeroWeb.UIComponents

  alias KlassHero.Participation.Domain.Services.ParticipationCollection
  alias KlassHeroWeb.Theme
  alias Phoenix.HTML.Form

  @doc """
  Renders a session participation card with check-in status information.

  Displays session details including program name, date, time, location, and current
  check-in status. Supports customizable action buttons via the `:actions` slot.

  ## Examples

      <.participation_card session={@session} role={:provider}>
        <:actions>
          <button phx-click="start_session" class="btn-primary">
            Start Session
          </button>
        </:actions>
      </.participation_card>

      <.participation_card session={@session} role={:parent} />
  """
  attr :session, :map, required: true, doc: "Session map with participation details"

  attr :role, :atom,
    required: true,
    values: [:provider, :parent, :staff],
    doc: "User role viewing the card"

  attr :class, :string, default: "", doc: "Additional CSS classes"
  slot :actions, doc: "Action buttons for the session"

  def participation_card(assigns) do
    ~H"""
    <div class={[
      "bg-white border border-hero-grey-200 p-4 md:p-6",
      Theme.rounded(:lg),
      Theme.shadow(:md),
      @class
    ]}>
      <div class="flex items-start justify-between gap-4 mb-4">
        <div class="flex-1">
          <h3 class="text-lg font-semibold text-hero-black">
            {Map.get(@session, :program_name, gettext("Session"))}
          </h3>
          <p class="text-sm text-hero-black-100 mt-1">
            {format_session_datetime(@session)}
          </p>
        </div>
        <.participation_status status={@session.status} />
      </div>

      <div class="space-y-2 mb-4">
        <div class="flex items-center gap-2 text-sm text-hero-black-100">
          <.icon name="hero-map-pin" class="w-4 h-4 text-hero-grey-400" />
          <span>{Map.get(@session, :location, gettext("Location TBD"))}</span>
        </div>

        <%= if @role in [:provider, :staff] && Map.get(@session, :capacity) do %>
          <div class="flex items-center gap-2 text-sm text-hero-black-100">
            <.icon name="hero-user-group" class="w-4 h-4 text-hero-grey-400" />
            <span>
              {gettext("%{checked_in} / %{capacity} checked in",
                checked_in: Map.get(@session, :checked_in_count, 0),
                capacity: Map.get(@session, :capacity)
              )}
            </span>
          </div>
        <% end %>
      </div>

      <%= if @actions != [] do %>
        <div class="flex gap-2 flex-wrap">
          {render_slot(@actions)}
        </div>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders a status badge for sessions and participation records.

  Displays color-coded status indicators with icons for various states including
  session statuses (scheduled, in_progress, completed) and participation statuses
  (checked_in, checked_out, absent).

  ## Examples

      <.participation_status status={:scheduled} />
      <.participation_status status={:checked_in} size={:lg} />
      <.participation_status status={:absent} />
  """
  attr :status, :atom,
    required: true,
    values: [
      :registered,
      :scheduled,
      :in_progress,
      :completed,
      :checked_in,
      :checked_out,
      :absent,
      :cancelled
    ],
    doc: "Status to display"

  attr :size, :atom, default: :md, values: [:sm, :md, :lg], doc: "Badge size"
  attr :class, :string, default: "", doc: "Additional CSS classes"

  def participation_status(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center gap-1.5 font-medium whitespace-nowrap",
      size_classes(@size),
      status_color_classes(@status),
      Theme.rounded(:full),
      @class
    ]}>
      <.icon name={status_icon(@status)} class={icon_size_classes(@size)} />
      <span>{status_label(@status)}</span>
    </span>
    """
  end

  @doc """
  Renders a batch check-in form with roster and notes.

  Provides an interactive form for providers to check in multiple children at once
  with optional notes. Displays the session roster with child names and status.

  ## Examples

      <.check_in_form
        form={@form}
        participation_records={@participation_records}
        session={@session}
        on_submit="submit_participation"
      />
  """
  attr :form, Form, required: true, doc: "Form struct from to_form/2"

  attr :participation_records, :list,
    required: true,
    doc: "List of enriched participation record maps with child_first_name and child_last_name fields"

  attr :session, :map, required: true, doc: "Session map"
  attr :on_submit, :string, required: true, doc: "Phoenix event for form submission"
  attr :class, :string, default: "", doc: "Additional CSS classes"

  def check_in_form(assigns) do
    ~H"""
    <div class={[
      "bg-white border border-hero-grey-200 p-4 md:p-6",
      Theme.rounded(:lg),
      Theme.shadow(:md),
      @class
    ]}>
      <.form for={@form} id="participation-form" phx-submit={@on_submit}>
        <div class="mb-6">
          <h3 class="text-lg font-semibold text-hero-black mb-2">
            {gettext("Participation Check-In")}
          </h3>
          <p class="text-sm text-hero-grey-600">
            {format_session_datetime(@session)}
          </p>
        </div>

        <div class="space-y-3 mb-6">
          <h4 class="text-sm font-medium text-hero-black-100">{gettext("Session Roster")}</h4>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div
              :for={record <- @participation_records}
              class={[
                "border p-3",
                Theme.rounded(:md),
                if(record.status == :checked_in,
                  do: "border-green-300 bg-green-50",
                  else: "border-hero-grey-200 bg-white"
                )
              ]}
            >
              <label class="flex items-start gap-3 cursor-pointer">
                <input
                  type="checkbox"
                  name="participation[checked_in][]"
                  value={record.id}
                  checked={record.status == :checked_in}
                  class="mt-1 w-4 h-4 text-hero-blue-600 rounded border-hero-grey-300 focus:ring-hero-blue-500"
                />
                <div class="flex-1">
                  <div class="font-medium text-hero-black">
                    {record.child_first_name} {record.child_last_name}
                  </div>
                  <%!-- Consent-gated safety info --%>
                  <.safety_info_badges record={record} />
                  <%= if record.status == :checked_in && record.check_in_at do %>
                    <div class="text-xs text-hero-grey-500 mt-1">
                      {gettext("Checked in at %{time}", time: format_time(record.check_in_at))}
                    </div>
                  <% end %>
                </div>
                <.participation_status status={record.status} size={:sm} />
              </label>
            </div>
          </div>
        </div>

        <div class="mb-6">
          <.input
            field={@form[:notes]}
            type="textarea"
            label={gettext("Session Notes (optional)")}
            placeholder={gettext("Any important notes about today's session...")}
            rows="3"
          />
        </div>

        <div class="flex gap-3">
          <button
            type="submit"
            class={[
              "flex-1 px-4 py-3 bg-hero-blue-600 text-white font-medium hover:bg-hero-blue-700 focus:outline-none focus:ring-2 focus:ring-hero-blue-500 focus:ring-offset-2",
              Theme.rounded(:lg),
              Theme.transition(:normal)
            ]}
          >
            {gettext("Submit Participation")}
          </button>
        </div>
      </.form>
    </div>
    """
  end

  @doc """
  Renders a session roster list with participation status.

  Displays all children enrolled in a session with their current participation status.
  Supports an editable mode with action buttons per record via the `:actions` slot.

  ## Examples

      <.roster_list
        participation_records={@participation_records}
        session={@session}
        editable={true}
      >
        <:actions :let={record}>
          <%= if record.status == :checked_in do %>
            <button phx-click="check_out" phx-value-id={record.id} class="btn-sm">
              Check Out
            </button>
          <% else %>
            <button phx-click="check_in" phx-value-id={record.id} class="btn-sm">
              Check In
            </button>
          <% end %>
        </:actions>
      </.roster_list>
  """
  attr :participation_records, :list,
    required: true,
    doc: "List of enriched participation record maps with child_first_name and child_last_name fields"

  attr :session, :map, required: true, doc: "Session map"
  attr :editable, :boolean, default: false, doc: "Whether to show action buttons"
  attr :class, :string, default: "", doc: "Additional CSS classes"

  attr :checkout_form_expanded, :string,
    default: nil,
    doc: "Record ID with checkout form expanded"

  attr :checkout_forms, :map,
    default: %{},
    doc: "Map of record_id => form structs"

  slot :actions, doc: "Action buttons per record" do
    attr :record, :map
  end

  slot :expanded_content,
    doc: "Full-width content rendered below the record row (forms, notes lists)" do
    attr :record, :map
  end

  def roster_list(assigns) do
    ~H"""
    <div class={[
      "bg-white border border-hero-grey-200",
      Theme.rounded(:lg),
      Theme.shadow(:md),
      @class
    ]}>
      <div class="p-4 md:p-6 border-b border-hero-grey-200">
        <div class="flex items-center justify-between">
          <h3 class="text-lg font-semibold text-hero-black">
            {gettext("Session Roster")}
          </h3>
          <div class="text-sm text-hero-grey-600">
            {gettext("%{checked_in} / %{total} checked in",
              checked_in: ParticipationCollection.count_checked_in(@participation_records),
              total: length(@participation_records)
            )}
          </div>
        </div>
      </div>

      <div class="divide-y divide-hero-grey-200">
        <div
          :for={record <- @participation_records}
          class="p-4 md:p-6 hover:bg-hero-grey-50 transition-colors"
        >
          <div class="flex items-start justify-between gap-4">
            <div class="flex-1">
              <div class="font-medium text-hero-black mb-1">
                {record.child_first_name} {record.child_last_name}
              </div>

              <%!-- Consent-gated safety info --%>
              <.safety_info_badges record={record} id={"safety-info-#{record.id}"} />

              <div class="space-y-1 text-sm text-hero-grey-600">
                <%= if record.check_in_at do %>
                  <div class="flex items-center gap-2">
                    <.icon name="hero-arrow-right-circle" class="w-4 h-4 text-green-600" />
                    <span>{gettext("In: %{time}", time: format_time(record.check_in_at))}</span>
                  </div>
                <% end %>
                <%= if record.check_out_at do %>
                  <div class="flex items-center gap-2">
                    <.icon name="hero-arrow-left-circle" class="w-4 h-4 text-hero-blue-600" />
                    <span>{gettext("Out: %{time}", time: format_time(record.check_out_at))}</span>
                  </div>
                <% end %>
              </div>

              <%= if Map.get(record, :check_in_notes) || Map.get(record, :check_out_notes) do %>
                <div class="mt-2 space-y-1">
                  <%= if Map.get(record, :check_in_notes) do %>
                    <div class="text-sm text-hero-grey-600 italic">
                      <span class="font-medium text-hero-black-100">{gettext("Check-in:")}</span>
                      "{record.check_in_notes}"
                    </div>
                  <% end %>
                  <%= if Map.get(record, :check_out_notes) do %>
                    <div class="text-sm text-hero-grey-600 italic">
                      <span class="font-medium text-hero-black-100">{gettext("Check-out:")}</span>
                      "{record.check_out_notes}"
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>

            <div class="flex flex-col items-end gap-2">
              <.participation_status status={record.status} />
              <%= if @editable && @actions != [] do %>
                <div class="flex gap-2">
                  {render_slot(@actions, record)}
                </div>
              <% end %>
            </div>
          </div>

          <%= if @checkout_form_expanded == to_string(record.id) do %>
            <div class="mt-4 border-t border-hero-grey-200 pt-4">
              <.form
                for={Map.get(@checkout_forms, to_string(record.id))}
                id={"checkout-form-#{record.id}"}
                phx-change="update_checkout_notes"
                phx-submit="confirm_checkout"
                phx-value-id={record.id}
              >
                <div class="space-y-3">
                  <.input
                    field={Map.get(@checkout_forms, to_string(record.id))[:notes]}
                    type="textarea"
                    label={gettext("Check-out notes (optional)")}
                    placeholder={gettext("E.g., picked up by parent, gave medication reminder...")}
                    rows="2"
                  />

                  <div class="flex gap-2 flex-wrap">
                    <button
                      type="submit"
                      class={[
                        "flex-1 px-4 py-2 bg-hero-blue-600 text-white font-medium hover:bg-hero-blue-700",
                        "focus:outline-none focus:ring-2 focus:ring-hero-blue-500 focus:ring-offset-2",
                        Theme.rounded(:md),
                        Theme.transition(:normal)
                      ]}
                    >
                      {gettext("Confirm Check Out")}
                    </button>
                    <button
                      type="button"
                      phx-click="cancel_checkout"
                      phx-value-id={record.id}
                      class={[
                        "px-4 py-2 bg-white text-hero-black-100 font-medium border border-hero-grey-300",
                        "hover:bg-hero-grey-50 focus:outline-none focus:ring-2 focus:ring-hero-blue-500 focus:ring-offset-2",
                        Theme.rounded(:md),
                        Theme.transition(:normal)
                      ]}
                    >
                      {gettext("Cancel")}
                    </button>
                  </div>
                </div>
              </.form>
            </div>
          <% end %>

          <%!-- Expanded content (forms, notes lists) rendered full-width below the row --%>
          <%= if @expanded_content != [] do %>
            {render_slot(@expanded_content, record)}
          <% end %>
        </div>

        <%= if @participation_records == [] do %>
          <div class="p-8 text-center text-hero-grey-500">
            <.icon name="hero-user-group" class="w-12 h-12 mx-auto mb-2 text-hero-grey-400" />
            <p>{gettext("No children enrolled in this session")}</p>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  @doc """
  Renders a behavioral note status badge.

  Shows the current status of a behavioral note (pending, approved, rejected)
  with appropriate color coding.

  ## Examples

      <.note_status_badge status={:pending_approval} />
      <.note_status_badge status={:approved} />
      <.note_status_badge status={:rejected} />
  """
  attr :status, :atom,
    required: true,
    values: [:pending_approval, :approved, :rejected],
    doc: "Note status"

  attr :id, :string, default: nil, doc: "Optional DOM id"

  def note_status_badge(assigns) do
    ~H"""
    <span
      id={@id}
      class={[
        "inline-flex items-center gap-1 px-2 py-0.5 text-xs font-medium rounded-full",
        note_status_classes(@status)
      ]}
    >
      <.icon name={note_status_icon(@status)} class="w-3 h-3" />
      {note_status_label(@status)}
    </span>
    """
  end

  @doc """
  Renders an inline form for submitting a behavioral note.

  ## Examples

      <.behavioral_note_form
        form={@note_forms["record-id"]}
        record_id="record-id"
      />
  """
  attr :form, Form, required: true, doc: "Form struct from to_form/2"
  attr :record_id, :string, required: true, doc: "Participation record ID"

  def behavioral_note_form(assigns) do
    assigns =
      assign(assigns,
        entity_id: assigns.record_id,
        id_prefix: "behavioral-note-form",
        wrapper_id_prefix: "note-form",
        label: gettext("Behavioral Note"),
        placeholder: gettext("Observation about the child's participation..."),
        submit_label: gettext("Submit Note"),
        submit_event: "submit_note",
        change_event: "update_note_content",
        cancel_event: "cancel_note"
      )

    behavioral_note_inline_form(assigns)
  end

  @doc """
  Renders an inline form for revising a rejected behavioral note.

  ## Examples

      <.behavioral_note_revision_form
        form={@revision_forms["note-id"]}
        note_id="note-id"
      />
  """
  attr :form, Form, required: true, doc: "Form struct from to_form/2"
  attr :note_id, :string, required: true, doc: "Behavioral note ID"

  def behavioral_note_revision_form(assigns) do
    assigns =
      assign(assigns,
        entity_id: assigns.note_id,
        id_prefix: "revision-note-form",
        wrapper_id_prefix: "revision-form",
        label: gettext("Revised Note"),
        placeholder: gettext("Update your observation..."),
        submit_label: gettext("Resubmit Note"),
        submit_event: "submit_revision",
        change_event: "update_revision_content",
        cancel_event: "cancel_revision"
      )

    behavioral_note_inline_form(assigns)
  end

  @doc """
  Inline edit form for a participation record (provider/staff).

  Lets the caller patch the record's primary notes field and, when the child
  hasn't departed yet, optionally record a departure time. Submits the
  `submit_edit` event with the form values; the LiveView wires that to
  `Participation.correct_attendance/1` with the appropriate `actor_role`.

  ## Examples

      <.edit_record_form
        form={@edit_forms[record.id]}
        record={record}
      />
  """
  attr :form, Form, required: true, doc: "Form struct from to_form/2"
  attr :record, :map, required: true, doc: "Participation record being edited"

  def edit_record_form(assigns) do
    ~H"""
    <div class="mt-4 border-t border-hero-grey-200 pt-4" id={"edit-form-#{@record.id}"}>
      <.form
        for={@form}
        id={"edit-record-form-#{@record.id}"}
        phx-change="update_edit_form"
        phx-submit="submit_edit"
        phx-value-id={@record.id}
      >
        <div class="space-y-3">
          <.input
            field={@form[:notes]}
            type="textarea"
            label={edit_notes_label(@record)}
            placeholder={gettext("Update the note for this child (e.g. clarify what happened)")}
            rows="3"
          />

          <%= if is_nil(@record.check_out_at) do %>
            <.input
              field={@form[:check_out_at]}
              type="datetime-local"
              label={gettext("Record departure time (optional)")}
            />
            <p class="text-xs text-hero-grey-500 -mt-2">
              {gettext("Leave blank to keep this child marked as present.")}
            </p>
          <% end %>

          <div class="flex gap-2 flex-wrap">
            <button
              type="submit"
              class={[
                "flex-1 px-4 py-2 bg-hero-blue-600 text-white font-medium hover:bg-hero-blue-700",
                "focus:outline-none focus:ring-2 focus:ring-hero-blue-500 focus:ring-offset-2",
                Theme.rounded(:md),
                Theme.transition(:normal)
              ]}
            >
              {gettext("Save changes")}
            </button>
            <button
              type="button"
              phx-click="cancel_edit"
              phx-value-id={@record.id}
              class={[
                "px-4 py-2 bg-white text-hero-black-100 font-medium border border-hero-grey-300",
                "hover:bg-hero-grey-50 focus:outline-none focus:ring-2 focus:ring-hero-blue-500 focus:ring-offset-2",
                Theme.rounded(:md),
                Theme.transition(:normal)
              ]}
            >
              {gettext("Cancel")}
            </button>
          </div>
        </div>
      </.form>
    </div>
    """
  end

  @doc """
  Renders a list of approved behavioral notes for a child.

  ## Examples

      <.approved_notes_list notes={record.behavioral_notes} record_id={record.id} />
  """
  attr :notes, :list, required: true, doc: "List of approved behavioral note domain models"
  attr :record_id, :string, required: true, doc: "Participation record ID for DOM ids"

  def approved_notes_list(assigns) do
    ~H"""
    <%= if @notes != [] do %>
      <div class="mt-2 space-y-1" id={"approved-notes-#{@record_id}"}>
        <div
          :for={note <- @notes}
          class="text-sm text-hero-grey-600 italic bg-green-50 px-2 py-1 rounded"
        >
          <span class="font-medium text-green-700">{gettext("Note:")}</span> "{note.content}"
        </div>
      </div>
    <% end %>
    """
  end

  attr :form, Form, required: true
  attr :entity_id, :string, required: true
  attr :id_prefix, :string, required: true
  attr :wrapper_id_prefix, :string, required: true
  attr :label, :string, required: true
  attr :placeholder, :string, required: true
  attr :submit_label, :string, required: true
  attr :submit_event, :string, required: true
  attr :change_event, :string, required: true
  attr :cancel_event, :string, required: true

  defp behavioral_note_inline_form(assigns) do
    ~H"""
    <div class="mt-3 border-t border-hero-grey-200 pt-3" id={"#{@wrapper_id_prefix}-#{@entity_id}"}>
      <.form
        for={@form}
        id={"#{@id_prefix}-#{@entity_id}"}
        phx-change={@change_event}
        phx-submit={@submit_event}
        phx-value-id={@entity_id}
      >
        <div class="space-y-3">
          <.input
            field={@form[:content]}
            type="textarea"
            label={@label}
            placeholder={@placeholder}
            rows="3"
          />
          <div class="flex gap-2 flex-wrap">
            <button
              type="submit"
              class={[
                "flex-1 px-3 py-1.5 bg-hero-blue-600 text-white text-sm font-medium hover:bg-hero-blue-700",
                "focus:outline-none focus:ring-2 focus:ring-hero-blue-500 focus:ring-offset-2",
                Theme.rounded(:md),
                Theme.transition(:normal)
              ]}
            >
              {@submit_label}
            </button>
            <button
              type="button"
              phx-click={@cancel_event}
              phx-value-id={@entity_id}
              class={[
                "px-3 py-1.5 bg-white text-hero-black-100 text-sm font-medium border border-hero-grey-300",
                "hover:bg-hero-grey-50 focus:outline-none focus:ring-2 focus:ring-hero-blue-500 focus:ring-offset-2",
                Theme.rounded(:md),
                Theme.transition(:normal)
              ]}
            >
              {gettext("Cancel")}
            </button>
          </div>
        </div>
      </.form>
    </div>
    """
  end

  attr :record, :map, required: true, doc: "Enriched participation record map with safety fields"
  attr :id, :string, default: nil, doc: "Optional DOM id for the badge container"

  defp safety_info_badges(assigns) do
    ~H"""
    <%= if Map.get(@record, :allergies) || Map.get(@record, :support_needs) || Map.get(@record, :emergency_contact) do %>
      <div class="flex flex-wrap gap-1 mt-1" id={@id}>
        <span
          :if={Map.get(@record, :allergies)}
          class="inline-flex items-center gap-1 px-2 py-0.5 text-xs font-medium bg-orange-50 text-orange-700 rounded-full"
        >
          {gettext("Allergies: %{details}", details: @record.allergies)}
        </span>
        <span
          :if={Map.get(@record, :support_needs)}
          class="inline-flex items-center gap-1 px-2 py-0.5 text-xs font-medium bg-blue-50 text-blue-700 rounded-full"
        >
          {gettext("Support: %{details}", details: @record.support_needs)}
        </span>
        <span
          :if={Map.get(@record, :emergency_contact)}
          class="inline-flex items-center gap-1 px-2 py-0.5 text-xs font-medium bg-red-50 text-red-700 rounded-full"
        >
          {gettext("Emergency: %{details}", details: @record.emergency_contact)}
        </span>
      </div>
    <% end %>
    """
  end

  defp format_session_datetime(session) do
    date = Map.get(session, :session_date) || Map.get(session, :date) || Date.utc_today()
    start_time = Map.get(session, :start_time) || ~T[00:00:00]

    "#{Calendar.strftime(date, "%B %d, %Y")} at #{Calendar.strftime(start_time, "%I:%M %p")}"
  end

  defp format_time(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%I:%M %p")
  end

  defp format_time(%Time{} = time) do
    Calendar.strftime(time, "%I:%M %p")
  end

  defp size_classes(:sm), do: "px-2 py-0.5 text-xs"
  defp size_classes(:md), do: "px-2.5 py-1 text-sm"
  defp size_classes(:lg), do: "px-3 py-1.5 text-base"

  defp icon_size_classes(:sm), do: "w-3 h-3"
  defp icon_size_classes(:md), do: "w-4 h-4"
  defp icon_size_classes(:lg), do: "w-5 h-5"

  defp status_color_classes(status) when status in [:registered, :scheduled],
    do: "bg-hero-grey-50 text-hero-black-100 border border-hero-grey-300"

  defp status_color_classes(:in_progress), do: "bg-blue-100 text-blue-700 border border-blue-300"

  defp status_color_classes(:completed), do: "bg-green-100 text-green-700 border border-green-300"

  defp status_color_classes(:checked_in), do: "bg-green-100 text-green-700 border border-green-300"

  defp status_color_classes(:checked_out), do: "bg-blue-100 text-blue-700 border border-blue-300"

  defp status_color_classes(:absent), do: "bg-orange-100 text-orange-700 border border-orange-300"

  defp status_color_classes(:expected), do: "bg-yellow-100 text-yellow-700 border border-yellow-300"

  defp status_color_classes(:cancelled), do: "bg-red-100 text-red-700 border border-red-300"

  defp status_icon(status) when status in [:registered, :scheduled], do: "hero-clock"
  defp status_icon(:in_progress), do: "hero-play-circle"
  defp status_icon(:completed), do: "hero-check-circle"
  defp status_icon(:checked_in), do: "hero-check-circle"
  defp status_icon(:checked_out), do: "hero-arrow-left-circle"
  defp status_icon(:absent), do: "hero-x-circle"
  defp status_icon(:expected), do: "hero-clock"
  defp status_icon(:cancelled), do: "hero-x-circle"

  defp status_label(:registered), do: gettext("Registered")
  defp status_label(:scheduled), do: gettext("Scheduled")
  defp status_label(:in_progress), do: gettext("In Progress")
  defp status_label(:completed), do: gettext("Completed")
  defp status_label(:checked_in), do: gettext("Present")
  defp status_label(:checked_out), do: gettext("Departed")
  defp status_label(:absent), do: gettext("Absent")
  defp status_label(:expected), do: gettext("Expected")
  defp status_label(:cancelled), do: gettext("Cancelled")

  defp note_status_classes(:pending_approval), do: "bg-yellow-50 text-yellow-700 border border-yellow-300"

  defp note_status_classes(:approved), do: "bg-green-50 text-green-700 border border-green-300"

  defp note_status_classes(:rejected), do: "bg-red-50 text-red-700 border border-red-300"

  defp note_status_icon(:pending_approval), do: "hero-clock"
  defp note_status_icon(:approved), do: "hero-check-circle"
  defp note_status_icon(:rejected), do: "hero-x-circle"

  defp note_status_label(:pending_approval), do: gettext("Pending Review")
  defp note_status_label(:approved), do: gettext("Approved")
  defp note_status_label(:rejected), do: gettext("Rejected")

  defp edit_notes_label(%{check_out_at: %DateTime{}}), do: gettext("Departure notes")
  defp edit_notes_label(_record), do: gettext("Notes")
end
