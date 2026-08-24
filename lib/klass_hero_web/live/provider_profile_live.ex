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
    programs =
      provider_id
      |> ProgramCatalog.list_current_programs_for_provider()
      # No provider passed: the card's provider row would repeat the name of the
      # page it is on, once per card.
      |> Enum.map(&ProgramPresenter.to_card_view/1)

    socket
    |> assign(:page_title, provider.business_name)
    |> assign(:provider, provider)
    |> assign(:programs_empty?, programs == [])
    |> stream(:programs, programs)
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: false

  defp any_contact?(provider) do
    Enum.any?([:description, :address, :phone, :website], &present?(provider[&1]))
  end

  @impl true
  def handle_event("view_program", %{"program-id" => program_id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/programs/#{program_id}")}
  end

  attr :id, :string, default: nil
  attr :background, :string, required: true
  slot :inner_block, required: true

  defp profile_section(assigns) do
    ~H"""
    <section id={@id} class={["py-12 lg:py-16", @background]}>
      <div class="max-w-5xl mx-auto px-6">
        {render_slot(@inner_block)}
      </div>
    </section>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <%!-- The hero carries the marketing surface's warm pink base, and it also keeps
          the bands alternating when About is absent — which is the common case, since
          most providers have filled none of this in. Alternation that depends on
          optional content collapses into two flush white sections exactly then. --%>
    <.profile_section background={Theme.gradient(:base_fade)}>
      <.provider_hero provider={@provider} variant={:full} />
    </.profile_section>

    <.profile_section :if={any_contact?(@provider)} id="provider-about" background="bg-hero-cream-100">
      <h2 class={[Theme.typography(:section_title), Theme.text_color(:heading), "mb-6"]}>
        <%!-- Not the bare "About", whose German is "Über uns" — this section is
              about someone else, and the reader is a parent. --%>
        {gettext("About the Provider")}
      </h2>

      <p
        :if={present?(@provider[:description])}
        class={[Theme.typography(:body), "text-[var(--fg-muted-on-light)] max-w-3xl mb-8"]}
      >
        {@provider.description}
      </p>

      <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <.mk_method_row
          :if={present?(@provider[:address])}
          icon="hero-map-pin"
          title={gettext("Address")}
          value={@provider.address}
        />
        <.mk_method_row
          :if={present?(@provider[:phone])}
          icon="hero-phone"
          title={gettext("Phone")}
          value={@provider.phone}
          href={"tel:#{@provider[:phone]}"}
        />
        <.mk_method_row
          :if={present?(@provider[:website])}
          icon="hero-globe-alt"
          title={gettext("Website")}
          value={@provider.website}
          href={@provider[:website]}
        />
      </div>
    </.profile_section>

    <.profile_section id="provider-programs" background="bg-white">
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
    </.profile_section>

    <.mk_cta_section
      id="provider-cta"
      title={gettext("Have questions?")}
      lede={
        gettext("Message %{provider} directly about their programs.",
          provider: @provider.business_name
        )
      }
    >
      <:cta>
        <%!-- A link, not a gated button. Messaging.build_compose_target/3 owns who may
              write to whom ("the gate lives here rather than in the callers"), and an
              anonymous visitor is bounced to log in by the target live_session. A
              pre-check here would only add a second copy of the rule and turn the CTA
              into a dead end for logged-out traffic. --%>
        <.link id="provider-message-cta" navigate={~p"/messages/new?provider_id=#{@provider.id}"}>
          <.kh_button variant={:primary}>{gettext("Message this provider")}</.kh_button>
        </.link>
      </:cta>
    </.mk_cta_section>
    """
  end
end
