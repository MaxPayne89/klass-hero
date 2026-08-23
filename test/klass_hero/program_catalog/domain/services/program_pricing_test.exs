defmodule KlassHero.ProgramCatalog.Domain.Services.ProgramPricingTest do
  use ExUnit.Case, async: true

  alias KlassHero.ProgramCatalog.Domain.Services.ProgramPricing

  describe "price_state/1" do
    @states [
      {nil, :unset, "a program nobody has priced yet"},
      {Decimal.new("0"), :free, "an integral zero"},
      {Decimal.new("0.00"), :free, "a zero carrying scale — Decimal.equal?/2, not ==/2"},
      {Decimal.new("-0"), :free, "negative zero still equals zero"}
    ]

    test "classifies the non-priced states" do
      for {price, expected, why} <- @states do
        assert ProgramPricing.price_state(price) == expected,
               "#{inspect(price)} (#{why}) should classify as #{inspect(expected)}"
      end
    end

    test "classifies a positive price as priced, carrying the amount through" do
      price = Decimal.new("45.00")

      assert {:priced, ^price} = ProgramPricing.price_state(price)
    end

    test "does not round — rounding belongs to the formatter, not the classifier" do
      assert {:priced, amount} = ProgramPricing.price_state(Decimal.new("45.5"))
      assert Decimal.to_string(amount) == "45.5"
    end
  end
end
