defmodule KlassHeroWeb.ProviderProfileLive do
  @moduledoc """
  The public provider profile: identity, then what they run.

  Reads happen synchronously in `mount/3` so the disconnected render already
  carries the content — this is a crawlable marketing page, and `assign_async`
  would serve an empty first byte.
  """

  use KlassHeroWeb, :live_view

  import KlassHeroWeb.CompositeComponents
  import KlassHeroWeb.MarketingComponents

  alias KlassHero.ProgramCatalog
  alias KlassHero.Provider
  alias KlassHeroWeb.Helpers.ProviderDisplay
  alias KlassHeroWeb.Presenters.ProgramPresenter
  alias KlassHeroWeb.Theme

  @impl true
  def mount(%{"id" => provider_id}, _session, socket) do
    case ProviderDisplay.public_view(provider_id) do
      nil ->
        {:ok,
         socket
         |> put_flash(
           :error,
           gettext("Provider not found. They may have been removed or are no longer listed.")
         )
         |> redirect(to: ~p"/programs")}

      provider ->
        {:ok, mount_profile(socket, provider_id, provider)}
    end
  end

  defp mount_profile(socket, provider_id, provider) do
    contact = contact_facts(provider_id)

    programs =
      provider_id
      |> ProgramCatalog.list_current_programs_for_provider()
      # No provider passed: the card's provider row would repeat the name of the
      # page it is on, once per card.
      |> Enum.map(&ProgramPresenter.to_card_view/1)

    socket
    |> assign(:page_title, provider.business_name)
    |> assign(:provider, provider)
    |> assign(:contact, contact)
    |> assign(:programs_empty?, programs == [])
    |> stream(:programs, programs)
  end

  # Read a second time rather than widening the public view: the hero takes a
  # deliberately slim map, and these fields belong to About, not to identity.
  defp contact_facts(provider_id) do
    case Provider.get_public_profile(provider_id) do
      {:ok, profile} -> Map.take(profile, [:description, :address, :phone, :website])
      {:error, :not_found} -> %{}
    end
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: false

  defp any_contact?(contact) do
    Enum.any?([:description, :address, :phone, :website], &present?(Map.get(contact, &1)))
  end

  @impl true
  def handle_event("view_program", %{"program-id" => program_id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/programs/#{program_id}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-5xl mx-auto px-4 sm:px-6 py-8 sm:py-12">
      <.provider_hero provider={@provider} variant={:full} />
    </div>

    <section :if={any_contact?(@contact)} id="provider-about" class="py-12 lg:py-16 bg-hero-cream-100">
      <div class="max-w-5xl mx-auto px-4 sm:px-6">
        <h2 class={[Theme.typography(:section_title), Theme.text_color(:heading), "mb-6"]}>
          <%!-- Not the bare "About", whose German is "Über uns" — this section is
                about someone else, and the reader is a parent. --%>
          {gettext("About the Provider")}
        </h2>

        <p
          :if={present?(@contact[:description])}
          class={[Theme.typography(:body), "text-[var(--fg-muted-on-light)] max-w-3xl mb-8"]}
        >
          {@contact.description}
        </p>

        <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
          <.mk_method_row
            :if={present?(@contact[:address])}
            icon="hero-map-pin"
            title={gettext("Address")}
            value={@contact.address}
          />
          <.mk_method_row
            :if={present?(@contact[:phone])}
            icon="hero-phone"
            title={gettext("Phone")}
            value={@contact.phone}
            href={"tel:#{@contact[:phone]}"}
          />
          <.mk_method_row
            :if={present?(@contact[:website])}
            icon="hero-globe-alt"
            title={gettext("Website")}
            value={@contact.website}
            href={@contact[:website]}
          />
        </div>
      </div>
    </section>

    <section id="provider-programs" class="py-12 lg:py-16 bg-white">
      <div class="max-w-5xl mx-auto px-4 sm:px-6">
        <h2 class={[Theme.typography(:section_title), Theme.text_color(:heading), "mb-6"]}>
          {gettext("Programs")}
        </h2>

        <.mk_empty_state
          :if={@programs_empty?}
          icon="hero-calendar"
          title={gettext("No programs running right now")}
          description={gettext("This provider has no open programs at the moment. Check back soon.")}
        />

        <div
          :if={!@programs_empty?}
          id="provider-programs-grid"
          phx-update="stream"
          class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6"
        >
          <.mk_program_card
            :for={{dom_id, program} <- @streams.programs}
            id={dom_id}
            program={program}
          />
        </div>
      </div>
    </section>

    <section class="py-12 lg:py-16 bg-hero-cream-100">
      <div class="max-w-5xl mx-auto px-4 sm:px-6 text-center">
        <h2 class={[Theme.typography(:section_title), Theme.text_color(:heading), "mb-3"]}>
          {gettext("Have questions?")}
        </h2>
        <p class={[Theme.typography(:body), "text-[var(--fg-muted-on-light)] mb-6"]}>
          {gettext("Message %{provider} directly about their programs.",
            provider: @provider.business_name
          )}
        </p>
        <%!-- A link, not a gated button. Messaging.build_compose_target/3 owns who may
              write to whom ("the gate lives here rather than in the callers"), and an
              anonymous visitor is bounced to log in by the target live_session. A
              pre-check here would only add a second copy of the rule and turn the CTA
              into a dead end for logged-out traffic. --%>
        <.link id="provider-message-cta" navigate={~p"/messages/new?provider_id=#{@provider.id}"}>
          <.kh_button variant={:primary}>{gettext("Message this provider")}</.kh_button>
        </.link>
      </div>
    </section>
    """
  end
end
