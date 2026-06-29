defmodule KlassHeroWeb do
  @moduledoc """
  Entrypoint for defining web interface modules (controllers, components, channels).

      use KlassHeroWeb, :controller
      use KlassHeroWeb, :html
  """

  def static_paths, do: ~w(assets downloads fonts images favicon.ico robots.txt)

  def router do
    quote do
      use Phoenix.Router, helpers: false

      import Phoenix.Controller
      import Phoenix.LiveView.Router
      import Plug.Conn
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
    end
  end

  def controller do
    quote do
      use Phoenix.Controller, formats: [:html, :json]
      use Gettext, backend: KlassHeroWeb.Gettext

      import Plug.Conn

      unquote(verified_routes())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView

      unquote(html_helpers())
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(html_helpers())
    end
  end

  def html do
    quote do
      use Phoenix.Component

      import Phoenix.Controller,
        only: [get_csrf_token: 0, view_module: 1, view_template: 1]

      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      use Gettext, backend: KlassHeroWeb.Gettext

      import KlassHeroWeb.CompositeComponents
      import KlassHeroWeb.CoreComponents
      import KlassHeroWeb.ParentComponents
      import KlassHeroWeb.ParticipationComponents
      import KlassHeroWeb.ProviderLayoutComponents
      import KlassHeroWeb.UIComponents
      import Phoenix.HTML

      alias KlassHeroWeb.Layouts

      # Role → landing/section path resolver (single source of truth)
      alias KlassHeroWeb.RoleRouting
      alias Phoenix.LiveView.JS

      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: KlassHeroWeb.Endpoint,
        router: KlassHeroWeb.Router,
        statics: KlassHeroWeb.static_paths()
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
