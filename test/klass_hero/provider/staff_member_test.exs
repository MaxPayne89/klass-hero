defmodule KlassHero.Provider.StaffMemberTest do
  use KlassHero.DataCase, async: true

  import KlassHero.ProviderFixtures

  alias KlassHero.Provider
  alias KlassHero.Provider.PayRate
  alias KlassHero.Provider.StaffMember

  describe "full_name/1 and initials/1" do
    test "full_name joins first and last" do
      staff = %StaffMember{first_name: "Mike", last_name: "Johnson"}
      assert StaffMember.full_name(staff) == "Mike Johnson"
    end

    test "initials derives from the full name" do
      staff = %StaffMember{first_name: "Mike", last_name: "Johnson"}
      assert StaffMember.initials(staff) == "MJ"
    end
  end

  describe "generate_invitation_token/0" do
    test "returns a raw token and its sha256 hash" do
      assert {raw, hash} = StaffMember.generate_invitation_token()
      assert is_binary(raw)
      assert byte_size(hash) == 32
      {:ok, raw_bytes} = Base.url_decode64(raw, padding: false)
      assert :crypto.hash(:sha256, raw_bytes) == hash
    end
  end

  describe "valid_invitation_statuses/0" do
    test "is derived from the transition map (no nil pre-state)" do
      statuses = StaffMember.valid_invitation_statuses()
      assert Enum.sort(statuses) == [:accepted, :expired, :failed, :pending, :sent]
      refute nil in statuses
    end
  end

  describe "transition_invitation/2" do
    test "allows the legal edges of the state machine" do
      assert {:ok, %{invitation_status: :pending}} =
               StaffMember.transition_invitation(%StaffMember{invitation_status: nil}, :pending)

      assert {:ok, %{invitation_status: :sent}} =
               StaffMember.transition_invitation(%StaffMember{invitation_status: :pending}, :sent)

      assert {:ok, %{invitation_status: :accepted}} =
               StaffMember.transition_invitation(%StaffMember{invitation_status: :sent}, :accepted)

      assert {:ok, %{invitation_status: :expired}} =
               StaffMember.transition_invitation(%StaffMember{invitation_status: :sent}, :expired)

      assert {:ok, %{invitation_status: :pending}} =
               StaffMember.transition_invitation(%StaffMember{invitation_status: :failed}, :pending)
    end

    test "rejects illegal transitions" do
      assert {:error, :invalid_invitation_transition} =
               StaffMember.transition_invitation(%StaffMember{invitation_status: :accepted}, :sent)

      assert {:error, :invalid_invitation_transition} =
               StaffMember.transition_invitation(%StaffMember{invitation_status: :pending}, :expired)
    end
  end

  describe "invitation_expired?/1" do
    test "is false when never sent" do
      refute StaffMember.invitation_expired?(%StaffMember{invitation_sent_at: nil})
    end

    test "is true past the 7-day window" do
      sent = DateTime.add(DateTime.utc_now(), -8, :day)
      assert StaffMember.invitation_expired?(%StaffMember{invitation_sent_at: sent})
    end

    test "is false within the 7-day window" do
      sent = DateTime.add(DateTime.utc_now(), -1, :day)
      refute StaffMember.invitation_expired?(%StaffMember{invitation_sent_at: sent})
    end
  end

  describe "new/1 — domain validator" do
    test "accepts valid attrs" do
      assert {:ok, %StaffMember{}} =
               StaffMember.new(%{provider_id: "p", first_name: "Alice", last_name: "Smith"})
    end

    test "rejects an empty first name with a domain message" do
      assert {:error, errors} =
               StaffMember.new(%{provider_id: "p", first_name: "", last_name: "Smith"})

      assert Enum.any?(errors, &String.contains?(&1, "First name"))
    end

    test "rejects an invalid tag" do
      assert {:error, errors} =
               StaffMember.new(%{
                 provider_id: "p",
                 first_name: "Alice",
                 last_name: "Smith",
                 tags: ["not-a-category"]
               })

      assert Enum.any?(errors, &String.contains?(&1, "Invalid tags"))
    end
  end

  describe "pay_rate round-trip (virtual field + flat columns)" do
    test "persisted rate rehydrates as a %PayRate{} on read" do
      provider = provider_profile_fixture()
      {:ok, pay_rate} = PayRate.hourly(Decimal.new("25.00"))

      {:ok, staff} =
        Provider.create_staff_member(%{
          provider_id: provider.id,
          first_name: "Rita",
          last_name: "Rate",
          pay_rate: pay_rate
        })

      assert {:ok, fetched} = Provider.get_staff_member(staff.id)
      assert %PayRate{type: :hourly} = fetched.pay_rate
      assert Decimal.equal?(fetched.pay_rate.money.amount, Decimal.new("25.00"))
    end

    test "load_pay_rate/1 rebuilds the virtual field from the flat columns" do
      staff = %StaffMember{rate_type: :per_session, rate_amount: Decimal.new("80.00"), rate_currency: :EUR}
      loaded = StaffMember.load_pay_rate(staff)
      assert %PayRate{type: :per_session} = loaded.pay_rate
    end

    test "load_pay_rate/1 yields nil when no rate is set" do
      loaded = StaffMember.load_pay_rate(%StaffMember{})
      assert loaded.pay_rate == nil
    end
  end
end
