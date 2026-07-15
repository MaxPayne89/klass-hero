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

  describe "action/1 — a dedicated step uses its step key as the action kind" do
    # {key, completed_via, dedicated}. One marker-driven clause replaces the former per-key forks:
    # any step with a dedicated surface renders its own inline widget (keyed by step key) in EVERY
    # state, ahead of the generic :none / :navigate_* clauses.
    @dedicated_cases [
      {:responsible_person_identity, {:stripe_identity}, :widget},
      {:business_registration, {:document, "business_registration"}, :command},
      {:insurance, {:document, "insurance_certificate"}, :widget}
    ]

    for {key, completed_via, dedicated} <- @dedicated_cases,
        status <- [:not_started, :submitted, :approved, :rejected] do
      test "#{key} (dedicated #{dedicated}) keeps its :#{key} action when #{status}" do
        step = %VettingStepView{
          key: unquote(key),
          completed_via: unquote(Macro.escape(completed_via)),
          dedicated: unquote(dedicated),
          ui_status: unquote(status)
        }

        assert %{kind: unquote(key)} = Presenter.action(step),
               "dedicated #{unquote(key)} when #{unquote(status)} should key its own widget"
      end
    end
  end

  describe "action/1 — a non-dedicated step uses the generic clauses" do
    # {key, completed_via, expected_kind}
    @generic_cases [
      {:identity, {:stripe_identity}, :identity},
      {:background, {:document, "background_check"}, :navigate_documents},
      {:community_agreement, {:signed_agreement, :community_agreement}, :navigate_agreement}
    ]

    for {key, completed_via, expected} <- @generic_cases do
      test "#{key} (not dedicated) routes to :#{expected}" do
        step = %VettingStepView{
          key: unquote(key),
          completed_via: unquote(Macro.escape(completed_via)),
          ui_status: :not_started
        }

        assert %{kind: unquote(expected)} = Presenter.action(step)
      end
    end
  end
end
