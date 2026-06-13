defmodule KlassHeroWeb.Gettext do
  @moduledoc """
  Gettext backend for KlassHero. Usage: `use Gettext, backend: KlassHeroWeb.Gettext`.
  """
  use Gettext.Backend, otp_app: :klass_hero
end
