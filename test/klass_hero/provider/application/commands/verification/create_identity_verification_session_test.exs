defmodule KlassHero.Provider.Application.Commands.Verification.CreateIdentityVerificationSessionTest do
  # async: false — exercises the StripeIdentityAdapter (global Req.Test stub + telemetry).
  use KlassHero.DataCase, async: false

  alias KlassHero.Provider.Adapters.Driven.Persistence.Repositories.IdentityVerificationRepository
  alias KlassHero.Provider.Adapters.Driven.Persistence.Repositories.VettingCaseRepository
  alias KlassHero.Provider.Adapters.Driven.StripeIdentityAdapter
  alias KlassHero.Provider.Application.Commands.Verification.CreateIdentityVerificationSession
  alias KlassHero.ProviderFixtures

  setup do
    Req.Test.stub(StripeIdentityAdapter, fn conn ->
      Req.Test.json(conn, %{
        "id" => "vs_created",
        "url" => "https://verify.stripe.com/start/vs_created",
        "status" => "requires_input"
      })
    end)

    %{provider: ProviderFixtures.provider_profile_fixture()}
  end

  describe "execute/1" do
    test "creates a Stripe session, records it, submits the identity step, and returns the redirect url",
         %{provider: provider} do
      assert {:ok, %{redirect_url: "https://verify.stripe.com/start/vs_created"}} =
               CreateIdentityVerificationSession.execute(%{
                 provider_id: provider.id,
                 return_url: "https://klasshero.test/provider/verification"
               })

      assert {:ok, iv} = IdentityVerificationRepository.get_by_session_id("vs_created")
      assert iv.provider_id == provider.id
      assert iv.status == :processing

      {:ok, case_} = VettingCaseRepository.get_by_provider(provider.id)
      identity_step = Enum.find(case_.steps, &(&1.key == :identity))
      assert identity_step.status == :submitted
    end
  end
end
