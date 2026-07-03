defmodule KlassHero.Provider.Adapters.Driven.Notifications.IncidentReportedEmailNotifierTest do
  @moduledoc """
  Tests for the IncidentReportedEmailNotifier adapter.

  Uses Swoosh.Adapters.Test (configured in test env) which returns
  `{:ok, %{}}` from `Mailer.deliver/1`, so `send_incident_report/3`
  returns `{:ok, email}`.
  """

  # async: false — the interaction telemetry handler is global, so suite-wide
  # interaction events would cross-talk into this test's assert_receive.
  use ExUnit.Case, async: false

  alias KlassHero.Provider.Adapters.Driven.Notifications.IncidentReportedEmailNotifier
  alias KlassHero.Provider.IncidentReport

  @recipient %{email: "owner@example.com", name: "Hannah Owner"}

  defp attach_interaction_telemetry do
    test_pid = self()
    ref = make_ref()

    :telemetry.attach_many(
      {__MODULE__, ref},
      [
        [:klass_hero, :interaction, :start],
        [:klass_hero, :interaction, :stop],
        [:klass_hero, :interaction, :exception]
      ],
      fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry, event, measurements, metadata})
      end,
      %{}
    )

    on_exit(fn -> :telemetry.detach({__MODULE__, ref}) end)
  end

  defp build_report(overrides \\ %{}) do
    struct!(
      IncidentReport,
      Map.merge(
        %{
          id: "01HZ-incident-id",
          provider_profile_id: "prov-1",
          reporter_user_id: "user-1",
          reporter_display_name: "Jane Doe",
          program_id: "prog-1",
          category: :safety_concern,
          severity: :high,
          description: "A child slipped near the edge of the play area.",
          occurred_at: ~U[2026-04-20 14:30:00Z]
        },
        overrides
      )
    )
  end

  defp build_context(overrides \\ %{}) do
    Map.merge(
      %{
        program_name: "Friday Climbing Club",
        business_name: "Acme Adventures",
        signed_photo_url: nil
      },
      overrides
    )
  end

  describe "send_incident_report/3" do
    test "delivers email with the prescribed subject format" do
      {:ok, email} =
        IncidentReportedEmailNotifier.send_incident_report(@recipient, build_report(), build_context())

      assert email.subject ==
               "Incident reported: Safety concern (High) — Friday Climbing Club"
    end

    test "renders text body containing report metadata and description" do
      {:ok, email} =
        IncidentReportedEmailNotifier.send_incident_report(@recipient, build_report(), build_context())

      assert email.text_body =~ "Safety concern"
      assert email.text_body =~ "High"
      assert email.text_body =~ "Friday Climbing Club"
      assert email.text_body =~ "A child slipped near the edge of the play area."
      assert email.text_body =~ "01HZ-incident-id"
      assert email.text_body =~ "2026-04-20"
    end

    test "renders HTML body containing report metadata and description" do
      {:ok, email} =
        IncidentReportedEmailNotifier.send_incident_report(@recipient, build_report(), build_context())

      assert email.html_body =~ "Safety concern"
      assert email.html_body =~ "High"
      assert email.html_body =~ "Friday Climbing Club"
      assert email.html_body =~ "A child slipped near the edge of the play area."
      assert email.html_body =~ "01HZ-incident-id"
    end

    test "includes the signed photo URL in both bodies when present" do
      context = build_context(%{signed_photo_url: "https://signed.example.com/photo.jpg?sig=abc"})

      {:ok, email} =
        IncidentReportedEmailNotifier.send_incident_report(
          @recipient,
          build_report(%{photo_url: "incidents/photo.jpg", original_filename: "photo.jpg"}),
          context
        )

      assert email.text_body =~ "https://signed.example.com/photo.jpg?sig=abc"
      assert email.html_body =~ "https://signed.example.com/photo.jpg?sig=abc"
    end

    test "omits photo section when signed_photo_url is nil" do
      {:ok, email} =
        IncidentReportedEmailNotifier.send_incident_report(@recipient, build_report(), build_context())

      refute email.text_body =~ "View photo"
      refute email.html_body =~ "View photo"
    end

    test "escapes HTML in user-provided description" do
      report =
        build_report(%{description: "<script>alert('xss')</script> happened in the room."})

      {:ok, email} =
        IncidentReportedEmailNotifier.send_incident_report(@recipient, report, build_context())

      refute email.html_body =~ "<script>alert('xss')</script>"
      assert email.html_body =~ "&lt;script&gt;"
    end

    test "uses the recipient name and email and the configured sender" do
      {:ok, email} =
        IncidentReportedEmailNotifier.send_incident_report(@recipient, build_report(), build_context())

      assert email.to == [{"Hannah Owner", "owner@example.com"}]
      assert email.from == {"KlassHero", "noreply@mail.klasshero.com"}
    end

    test "falls back to the email address when recipient name is nil" do
      recipient = %{email: "owner@example.com", name: nil}

      {:ok, email} =
        IncidentReportedEmailNotifier.send_incident_report(recipient, build_report(), build_context())

      assert email.to == [{"owner@example.com", "owner@example.com"}]
    end
  end

  describe "interaction telemetry" do
    test "emits a :stop event with :email kind and :ok status" do
      attach_interaction_telemetry()

      assert {:ok, %Swoosh.Email{}} =
               IncidentReportedEmailNotifier.send_incident_report(@recipient, build_report(), build_context())

      assert_receive {:telemetry, [:klass_hero, :interaction, :stop], %{duration_us: _},
                      %{
                        io_kind: :email,
                        operation: :send_incident_report,
                        status: :ok,
                        attributes: %{"email.operation" => :send_incident_report}
                      }}
    end

    test "never emits raw recipient or body — PII stays out of telemetry metadata" do
      attach_interaction_telemetry()

      IncidentReportedEmailNotifier.send_incident_report(@recipient, build_report(), build_context())

      assert_receive {:telemetry, [:klass_hero, :interaction, :stop], _measurements, metadata}
      refute Map.has_key?(metadata, :result)
      refute match?(%Swoosh.Email{}, metadata.sanitized_input)
    end
  end
end
