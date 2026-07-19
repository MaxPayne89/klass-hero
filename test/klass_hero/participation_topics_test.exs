defmodule KlassHero.ParticipationTopicsTest do
  @moduledoc """
  Pins the PubSub topic strings LiveViews subscribe to against the single source
  of truth (#1108). If the derived topics ever drift from these literals, every
  subscriber has silently stopped receiving real-time updates.
  """
  use ExUnit.Case, async: true

  alias KlassHero.Participation

  describe "participation_topics/1" do
    @groups [
      {:session_note,
       [
         "session_note:session_note_submitted",
         "session_note:session_note_approved",
         "session_note:session_note_rejected"
       ]},
      {:attendance,
       [
         "participation:child_checked_in",
         "participation:child_checked_out",
         "participation:child_marked_absent"
       ]}
    ]

    for {group, expected} <- @groups do
      test "#{group} derives #{inspect(expected)}" do
        assert Participation.participation_topics(unquote(group)) == unquote(expected)
      end
    end
  end

  describe "provider_topic/1" do
    test "builds the provider-scoped topic" do
      assert Participation.provider_topic("prov-123") == "participation:provider:prov-123"
    end
  end
end
