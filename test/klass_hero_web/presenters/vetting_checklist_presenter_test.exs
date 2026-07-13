defmodule KlassHeroWeb.Presenters.VettingChecklistPresenterTest do
  @moduledoc """
  Tests for the per-step display metadata the checklist presenter emits. Focused on the
  business-track step keys (Slice 0) — the presenter has no fallback clause, so an
  unhandled key raises, which is exactly what these pin down.
  """

  use ExUnit.Case, async: true

  alias KlassHero.Provider.VettingStepView
  alias KlassHeroWeb.Presenters.VettingChecklistPresenter, as: Presenter

  # Every step key the business track can surface. community_agreement is shared with the
  # individual track and already had a clause; the other four are new in Slice 0.
  @business_keys [
    :responsible_person_identity,
    :business_registration,
    :insurance,
    :community_agreement,
    :staff_attestation
  ]

  describe "step_meta/1 for business-track keys" do
    test "returns a complete 4-key display map for every business step key" do
      for key <- @business_keys do
        meta = Presenter.step_meta(key)

        assert %{title: title, description: description, icon: icon, gradient: gradient} = meta,
               "step_meta(#{inspect(key)}) must return the full display map"

        assert is_binary(title) and title != ""
        assert is_binary(description) and description != ""
        assert String.starts_with?(icon, "hero-")
        assert is_atom(gradient)
      end
    end
  end

  describe "action/1 forks the two stripe-identity steps" do
    test "the business responsible-person step gets its own :responsible_person action" do
      step = %VettingStepView{
        key: :responsible_person_identity,
        completed_via: {:stripe_identity},
        ui_status: :not_started
      }

      assert %{kind: :responsible_person} = Presenter.action(step)
    end

    test "the individual identity step keeps the bare :identity action" do
      step = %VettingStepView{key: :identity, completed_via: {:stripe_identity}, ui_status: :not_started}

      assert %{kind: :identity} = Presenter.action(step)
    end
  end
end
