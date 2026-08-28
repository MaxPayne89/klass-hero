defmodule KlassHero.ProgramCatalog.Domain.Services.ProgramPricing do
  @moduledoc """
  Classifies a Program's price into the states the rest of the system branches on.

  Classification only — this module chooses no words and formats no currency.
  A price becomes display text in the web layer (`ProgramPresenter.price_label/1`),
  because the free and unpriced states are *translated* strings and only a
  `gettext/1` call site inside `lib/klass_hero_web/` is visible to
  `mix lint_translations`. A literal here would ship to German parents in English
  with nothing to catch it.

  Three states, not a `zero?` boolean, because unpriced and free are genuinely
  different facts about a Program and the UI says different things about each.
  `CONTEXT.md`'s **Payment** entry already leans on the distinction: "Only
  programs with a Price above zero have one."
  """

  @typedoc """
  What is known about a Program's price.

  * `:unset` — no price recorded yet; the Program is incomplete, not free.
  * `:free` — priced, at zero. See **Free Program** in `CONTEXT.md`.
  * `{:priced, amount}` — the amount, **unrounded**; rounding is the formatter's job.
  """
  @type price_state :: :unset | :free | {:priced, Decimal.t()}

  @doc """
  Classifies a raw price value.

  Takes the price itself rather than a `%Program{}` so that the schema and a bare
  enrollment total both classify through this one function.

  ## Examples

      iex> ProgramPricing.price_state(nil)
      :unset

      iex> ProgramPricing.price_state(Decimal.new("0.00"))
      :free

      iex> ProgramPricing.price_state(Decimal.new("45.00"))
      {:priced, Decimal.new("45.00")}
  """
  @spec price_state(Decimal.t() | nil) :: price_state()
  def price_state(nil), do: :unset

  def price_state(%Decimal{} = price) do
    if Decimal.equal?(price, 0), do: :free, else: {:priced, price}
  end
end
