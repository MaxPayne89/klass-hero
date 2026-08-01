defmodule KlassHero.Enrollment.Adapters.Driven.Notifications.InviteEmailNotifierTest do
  @moduledoc """
  Tests for the InviteEmailNotifier adapter.

  Delivery goes through StubMailerAdapter (configured in test env), which passes
  to Swoosh.Adapters.Test unless a test arms a failure — so Mailer.deliver/1
  returns {:ok, %{}} here and send_invite/3 returns {:ok, email}.
  """

  # async: false — the interaction telemetry handler is global, so suite-wide
  # interaction events would cross-talk into this test's assert_receive.
  use ExUnit.Case, async: false

  alias KlassHero.Enrollment.Adapters.Driven.Notifications.InviteEmailNotifier

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

  defp build_invite(overrides \\ %{}) do
    Map.merge(
      %{
        guardian_email: "parent@example.com",
        guardian_first_name: "Hans",
        child_first_name: "Emma",
        child_last_name: "Schmidt",
        invite_token: "test-token-abc"
      },
      overrides
    )
  end

  @url "https://app.klasshero.com/invites/test-token-abc"

  describe "send_invite/3" do
    test "delivers email with correct recipient and subject" do
      {:ok, email} = InviteEmailNotifier.send_invite(build_invite(), "Dance Class", @url)

      assert email.to == [{"Hans", "parent@example.com"}]
      assert email.subject =~ "Emma"
      assert email.subject =~ "Dance Class"
    end

    test "uses mailer_defaults sender" do
      {:ok, email} = InviteEmailNotifier.send_invite(build_invite(), "Dance Class", @url)

      assert email.from == {"KlassHero", "noreply@mail.klasshero.com"}
    end

    test "includes invite URL in text body" do
      {:ok, email} = InviteEmailNotifier.send_invite(build_invite(), "Dance Class", @url)

      assert email.text_body =~ @url
      assert email.text_body =~ "Emma"
      assert email.text_body =~ "Dance Class"
    end

    test "includes invite URL and child name in HTML body" do
      {:ok, email} = InviteEmailNotifier.send_invite(build_invite(), "Dance Class", @url)

      assert email.html_body =~ @url
      assert email.html_body =~ "Emma"
      assert email.html_body =~ "Dance Class"
    end

    test "falls back to email as recipient name when guardian_first_name is nil" do
      invite = build_invite(%{guardian_first_name: nil})
      {:ok, email} = InviteEmailNotifier.send_invite(invite, "Dance Class", @url)

      assert email.to == [{"parent@example.com", "parent@example.com"}]
    end
  end

  describe "interaction telemetry" do
    test "emits a :stop event with :email kind and :ok status" do
      attach_interaction_telemetry()

      assert {:ok, %Swoosh.Email{}} = InviteEmailNotifier.send_invite(build_invite(), "Dance Class", @url)

      assert_receive {:telemetry, [:klass_hero, :interaction, :stop], %{duration_us: _},
                      %{
                        io_kind: :email,
                        operation: :send_invite,
                        status: :ok,
                        attributes: %{"email.operation" => :send_invite}
                      }}
    end

    test "never emits raw recipient or body — PII stays out of telemetry metadata" do
      attach_interaction_telemetry()

      InviteEmailNotifier.send_invite(build_invite(), "Dance Class", @url)

      assert_receive {:telemetry, [:klass_hero, :interaction, :stop], _measurements, metadata}
      refute Map.has_key?(metadata, :result)
      refute match?(%Swoosh.Email{}, metadata.sanitized_input)
    end
  end
end
