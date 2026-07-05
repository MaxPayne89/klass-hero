defmodule KlassHero.Provider.PayRateTest do
  use ExUnit.Case, async: true

  alias KlassHero.Provider.PayRate
  alias KlassHero.Shared.Money

  describe "hourly/2" do
    test "builds an hourly PayRate with default EUR currency" do
      assert {:ok, pay_rate} = PayRate.hourly(Decimal.new("25.00"))
      assert pay_rate.type == :hourly
      assert pay_rate.money.currency == :EUR
      assert Decimal.equal?(pay_rate.money.amount, Decimal.new("25.00"))
    end

    test "propagates Money validation errors" do
      assert {:error, reasons} = PayRate.hourly(Decimal.new("-1"))
      assert Enum.any?(reasons, &String.contains?(&1, "negative"))
    end
  end

  describe "per_session/2" do
    test "builds a per_session PayRate" do
      assert {:ok, pay_rate} = PayRate.per_session(Decimal.new("80.00"))
      assert pay_rate.type == :per_session
      assert Decimal.equal?(pay_rate.money.amount, Decimal.new("80.00"))
    end
  end

  describe "new/1" do
    test "accepts a valid type + Money struct" do
      {:ok, money} = Money.new(Decimal.new("10.00"))
      assert {:ok, pay_rate} = PayRate.new(%{type: :hourly, money: money})
      assert pay_rate.type == :hourly
    end

    test "rejects unknown type" do
      {:ok, money} = Money.new(Decimal.new("10.00"))
      assert {:error, reasons} = PayRate.new(%{type: :weekly, money: money})
      assert Enum.any?(reasons, &String.contains?(&1, "type"))
    end

    test "rejects missing money" do
      assert {:error, reasons} = PayRate.new(%{type: :hourly, money: nil})
      assert Enum.any?(reasons, &String.contains?(&1, "money"))
    end
  end

  describe "from_persistence/1" do
    test "reconstructs a PayRate without validation" do
      {:ok, money} = Money.new(Decimal.new("25.00"))

      assert {:ok, pay_rate} =
               PayRate.from_persistence(%{type: :hourly, money: money})

      assert pay_rate.type == :hourly
    end

    test "returns error when required keys missing" do
      assert {:error, :invalid_persistence_data} = PayRate.from_persistence(%{type: :hourly})
    end

    test "accepts a string type and atomizes it" do
      {:ok, money} = Money.new(Decimal.new("25.00"))

      assert {:ok, pay_rate} = PayRate.from_persistence(%{type: "hourly", money: money})
      assert pay_rate.type == :hourly
    end

    test "rejects a string type that does not map to a known atom" do
      {:ok, money} = Money.new(Decimal.new("25.00"))

      assert {:error, :invalid_persistence_data} =
               PayRate.from_persistence(%{type: "not_a_real_rate_type_xyz", money: money})
    end
  end

  describe "valid?/1" do
    test "returns true for a well-formed PayRate" do
      {:ok, pay_rate} = PayRate.hourly(Decimal.new("25.00"))
      assert PayRate.valid?(pay_rate)
    end
  end
end
