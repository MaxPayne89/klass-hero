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

  describe "anonymize_changeset/1" do
    @scrubbed_to_nil [:email, :bio, :headshot_url]

    test "scrubs every PII field" do
      staff = staff_member_with_pii()

      {:ok, anonymized} = staff |> StaffMember.anonymize_changeset() |> Repo.update()

      for field <- @scrubbed_to_nil do
        assert Map.fetch!(anonymized, field) == nil,
               "expected #{field} to be scrubbed to nil, got: #{inspect(Map.fetch!(anonymized, field))}"
      end

      assert StaffMember.full_name(anonymized) == "Deleted User"
      assert StaffMember.initials(anonymized) == "DU"
    end

    test "deactivates the staff member" do
      staff = staff_member_with_pii()
      assert staff.active

      {:ok, anonymized} = staff |> StaffMember.anonymize_changeset() |> Repo.update()

      refute anonymized.active
    end

    test "keeps provider-owned, non-personal data" do
      staff = staff_member_with_pii()

      {:ok, anonymized} = staff |> StaffMember.anonymize_changeset() |> Repo.update()

      assert anonymized.provider_id == staff.provider_id
      assert anonymized.role == staff.role
    end

    test "always kills the invitation token, so the invite link cannot be redeemed" do
      staff = staff_member_with_pii(invitation_status: :sent, invitation_token_hash: :crypto.strong_rand_bytes(32))

      {:ok, anonymized} = staff |> StaffMember.anonymize_changeset() |> Repo.update()

      assert anonymized.invitation_token_hash == nil
      assert {:error, :not_found} = Provider.get_staff_member_by_token_hash(staff.invitation_token_hash)
    end

    # Only an *outstanding* invitation is expired. :accepted was already consumed —
    # rewriting it would falsify roster history.
    @invitation_outcomes [
      {:pending, :expired},
      {:sent, :expired},
      {:accepted, :accepted},
      {:failed, :failed},
      {:expired, :expired}
    ]

    test "expires only the statuses that represent an outstanding invitation" do
      for {initial, expected} <- @invitation_outcomes do
        staff = staff_member_with_pii(invitation_status: initial)

        {:ok, anonymized} = staff |> StaffMember.anonymize_changeset() |> Repo.update()

        assert anonymized.invitation_status == expected,
               "#{initial} should anonymize to #{expected}, got #{anonymized.invitation_status}"
      end
    end

    defp staff_member_with_pii(attrs \\ []) do
      staff_member_fixture(
        Keyword.merge(
          [
            first_name: "Jane",
            last_name: "Doe",
            role: "Swim coach",
            email: "jane.doe@example.com",
            bio: "Twenty years teaching kids to swim.",
            headshot_url: "https://example.com/jane.jpg"
          ],
          attrs
        )
      )
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

    test "does not gatekeep pay rate — the changeset owns flat rate_* validation (#1060)" do
      # new/1 is the pure core; pay-rate validity depends on Ecto casting rate_type/
      # rate_amount, so it lives in the changeset. A garbage flat rate is therefore not
      # rejected here — it is caught downstream by create_changeset/edit_changeset.
      assert {:ok, %StaffMember{}} =
               StaffMember.new(%{
                 provider_id: "p",
                 first_name: "Alice",
                 last_name: "Smith",
                 rate_type: "not-a-real-type",
                 rate_amount: "-5.00"
               })
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
