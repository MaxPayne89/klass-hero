defmodule KlassHeroWeb.ProgramComponentsTest do
  use KlassHeroWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias KlassHero.Enrollment.ParticipantPolicy
  alias KlassHeroWeb.ProgramComponents

  describe "restriction_info/1" do
    test "renders nothing when policy has no restrictions" do
      policy = %ParticipantPolicy{
        program_id: "00000000-0000-0000-0000-000000000000",
        eligibility_at: "registration",
        min_age_months: nil,
        max_age_months: nil,
        allowed_genders: [],
        min_grade: nil,
        max_grade: nil
      }

      html = render_component(&ProgramComponents.restriction_info/1, %{policy: policy})

      refute html =~ "Participant Requirements"
      assert String.trim(html) == ""
    end

    test "renders the card when any age restriction is set" do
      policy = %ParticipantPolicy{
        program_id: "00000000-0000-0000-0000-000000000000",
        eligibility_at: "registration",
        min_age_months: 48,
        max_age_months: 120,
        allowed_genders: [],
        min_grade: nil,
        max_grade: nil
      }

      html = render_component(&ProgramComponents.restriction_info/1, %{policy: policy})

      assert html =~ "Participant Requirements"
    end

    test "renders the card when only allowed_genders is set" do
      policy = %ParticipantPolicy{
        program_id: "00000000-0000-0000-0000-000000000000",
        eligibility_at: "registration",
        min_age_months: nil,
        max_age_months: nil,
        allowed_genders: ["female"],
        min_grade: nil,
        max_grade: nil
      }

      html = render_component(&ProgramComponents.restriction_info/1, %{policy: policy})

      assert html =~ "Participant Requirements"
    end

    test "renders the card when only grade restriction is set" do
      policy = %ParticipantPolicy{
        program_id: "00000000-0000-0000-0000-000000000000",
        eligibility_at: "registration",
        min_age_months: nil,
        max_age_months: nil,
        allowed_genders: [],
        min_grade: 1,
        max_grade: 4
      }

      html = render_component(&ProgramComponents.restriction_info/1, %{policy: policy})

      assert html =~ "Participant Requirements"
    end
  end
end
