defmodule KlassHero.Shared.MoneyTest do
  use ExUnit.Case, async: true

  alias KlassHero.Shared.Money

  describe "new/2" do
    test "creates Money with Decimal amount and explicit currency" do
      assert {:ok, money} = Money.new(Decimal.new("25.00"), :EUR)
      assert Decimal.equal?(money.amount, Decimal.new("25.00"))
      assert money.currency == :EUR
    end

    test "defaults currency to :EUR when omitted" do
      assert {:ok, money} = Money.new(Decimal.new("10.00"))
      assert money.currency == :EUR
    end

    test "accepts integer amount and coerces to Decimal" do
      assert {:ok, money} = Money.new(15)
      assert Decimal.equal?(money.amount, Decimal.new("15"))
    end

    test "accepts string amount that parses to Decimal" do
      assert {:ok, money} = Money.new("42.50")
      assert Decimal.equal?(money.amount, Decimal.new("42.50"))
    end

    test "accepts zero amount (volunteer rate)" do
      assert {:ok, money} = Money.new(Decimal.new("0"))
      assert Decimal.equal?(money.amount, Decimal.new("0"))
    end

    test "rejects negative amount" do
      assert {:error, reasons} = Money.new(Decimal.new("-5.00"))
      assert Enum.any?(reasons, &String.contains?(&1, "negative"))
    end

    test "rejects unknown currency atom" do
      assert {:error, reasons} = Money.new(Decimal.new("10.00"), :USD)
      assert Enum.any?(reasons, &String.contains?(&1, "currency"))
    end

    test "accepts a currency as a string" do
      assert {:ok, money} = Money.new(Decimal.new("10.00"), "EUR")
      assert money.currency == :EUR
    end

    test "rejects an unknown currency string" do
      assert {:error, reasons} = Money.new(Decimal.new("10.00"), "USD")
      assert Enum.any?(reasons, &String.contains?(&1, "currency"))
    end

    test "rejects unparseable string amount" do
      assert {:error, reasons} = Money.new("not a number")
      assert Enum.any?(reasons, &String.contains?(&1, "amount"))
    end

    test "rejects nil amount" do
      assert {:error, reasons} = Money.new(nil)
      assert Enum.any?(reasons, &String.contains?(&1, "amount"))
    end
  end

  describe "from_persistence/1" do
    test "reconstructs Money from DB-shaped map without validation" do
      assert {:ok, money} =
               Money.from_persistence(%{amount: Decimal.new("99.99"), currency: "EUR"})

      assert Decimal.equal?(money.amount, Decimal.new("99.99"))
      assert money.currency == :EUR
    end

    test "returns error when required keys missing" do
      assert {:error, :invalid_persistence_data} = Money.from_persistence(%{amount: nil})
    end
  end

  describe "equal?/2" do
    test "returns true for same amount and currency" do
      {:ok, a} = Money.new(Decimal.new("25.00"), :EUR)
      {:ok, b} = Money.new(Decimal.new("25.00"), :EUR)
      assert Money.equal?(a, b)
    end

    test "returns false for different amount" do
      {:ok, a} = Money.new(Decimal.new("25.00"), :EUR)
      {:ok, b} = Money.new(Decimal.new("26.00"), :EUR)
      refute Money.equal?(a, b)
    end
  end
end
