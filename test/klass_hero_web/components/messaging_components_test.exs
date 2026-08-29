defmodule KlassHeroWeb.MessagingComponentsTest do
  use KlassHeroWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias KlassHero.Messaging.InboxConversation
  alias KlassHero.Messaging.StaffConversation
  alias KlassHeroWeb.MessagingComponents

  # The card is duck-typed over field names — `InboxConversation` for the parent and
  # provider inboxes, `StaffConversation` for the staff one — so it is rendered against
  # the real struct rather than a stand-in for a read table that no longer exists.
  defp inbox_conversation(attrs) do
    struct!(
      %InboxConversation{
        conversation_id: Ecto.UUID.generate(),
        conversation_type: :direct,
        provider_id: Ecto.UUID.generate(),
        other_participant_name: "Other User",
        latest_message_content: "Hello",
        latest_message_at: DateTime.utc_now()
      },
      attrs
    )
  end

  defp render_card(summary_attrs, opts \\ []) do
    render_component(&MessagingComponents.conversation_card/1, %{
      id: "conv-test",
      summary: inbox_conversation(summary_attrs),
      user_type: Keyword.get(opts, :user_type, :parent),
      navigate: "/messages/conv-1"
    })
  end

  describe "conversation_card/1 display name" do
    # {summary attrs, expected title}
    @display_name_cases [
      {[conversation_type: :direct, other_participant_name: nil], "Unknown"},
      {[conversation_type: :direct, other_participant_name: "Jane Doe"], "Jane Doe"},
      {[conversation_type: :program_broadcast, other_participant_name: nil, program_name: "Science Explorers"],
       "Science Explorers"},
      {[conversation_type: :program_broadcast, other_participant_name: nil, program_name: nil], "Program Broadcast"}
    ]

    test "derives the title from the summary's own fields" do
      for {attrs, expected} <- @display_name_cases do
        assert render_card(attrs) =~ expected, "#{inspect(attrs)} should render #{expected}"
      end
    end

    test "a named broadcast never falls back to 'Unknown'" do
      refute render_card(conversation_type: :program_broadcast, program_name: "Science Explorers") =~
               "Unknown"
    end
  end

  describe "conversation_card/1 latest message" do
    test "shows the message preview when there is content" do
      assert render_card(latest_message_content: "See you tomorrow") =~ "See you tomorrow"
    end

    test "shows a photo preview for an attachment-only message" do
      html = render_card(latest_message_content: nil, has_attachments: true)

      assert html =~ "Photo"
      refute html =~ "No messages yet"
    end

    test "shows the empty preview and no timestamp when no message ever arrived" do
      html =
        render_card(
          latest_message_content: nil,
          has_attachments: false,
          latest_message_at: ~U[2025-03-01 10:30:00Z]
        )

      assert html =~ "No messages yet"
      assert timestamp_text(html) == ""
    end

    test "shows the timestamp once a message exists" do
      html =
        render_card(
          latest_message_content: "Hello",
          latest_message_at: DateTime.utc_now() |> DateTime.truncate(:second)
        )

      refute timestamp_text(html) == ""
    end
  end

  describe "conversation_card/1 enrolled children" do
    test "lists the enrolled child names for a provider-side reader" do
      html = render_card([enrolled_child_names: ["Emma", "Liam"]], user_type: :provider)

      assert html =~ "Emma, Liam"
    end

    test "hides the enrolled child names from a parent-side reader" do
      html = render_card([enrolled_child_names: ["Emma", "Liam"]], user_type: :parent)

      refute html =~ "Emma, Liam"
    end
  end

  defp timestamp_text(html) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(~s([data-role="conversation-timestamp"]))
    |> LazyHTML.text()
    |> String.trim()
  end

  describe "contact_provider_button/1" do
    test "renders a button carrying program_id and provider_id as phx-values" do
      html =
        render_component(&MessagingComponents.contact_provider_button/1, %{
          program_id: "prog-42",
          provider_id: "prov-7",
          "phx-click": "contact_provider"
        })

      doc = LazyHTML.from_fragment(html)
      button = LazyHTML.query(doc, "button")

      assert Enum.count(button) == 1
      assert LazyHTML.attribute(button, "phx-click") == ["contact_provider"]
      assert LazyHTML.attribute(button, "phx-value-program-id") == ["prog-42"]
      assert LazyHTML.attribute(button, "phx-value-provider-id") == ["prov-7"]
      assert LazyHTML.text(button) =~ "Contact Provider"
    end
  end

  # The card is duck-typed on purpose (#746): it matches field names, never a struct
  # name, so the owner's staff-conversations list renders through the very same card
  # as the participant inbox and the two cannot drift apart. These tests are what stop
  # someone reintroducing a struct-name match and silently breaking that.
  describe "conversation_card/1 renders a StaffConversation" do
    defp staff_row(attrs) do
      struct!(
        %StaffConversation{
          conversation_id: "conv-1",
          conversation_type: :direct,
          provider_id: "prov-1",
          inserted_at: DateTime.utc_now()
        },
        attrs
      )
    end

    defp render_staff_card(attrs \\ []) do
      render_component(&MessagingComponents.conversation_card/1, %{
        id: "conv-test",
        summary: staff_row(attrs),
        user_type: :provider,
        navigate: "/provider/messages/staff/conv-1"
      })
    end

    test "reads the same display and preview fields it reads off a summary" do
      html =
        render_staff_card(
          other_participant_name: "Pat Parent",
          latest_message_content: "Is pickup still at four?"
        )

      assert html =~ "Pat Parent"
      assert html =~ "Is pickup still at four?"
    end

    test "falls back to the no-messages preview when the thread is empty" do
      assert render_staff_card() =~ "No messages yet"
    end

    test "shows the staff attribution only when the row carries names" do
      with_names = render_staff_card(staff_member_names: ["Sam Staff"])
      assert with_names =~ "Sam Staff"

      assert with_names
             |> LazyHTML.from_fragment()
             |> LazyHTML.query(~s([data-role="staff-attribution"]))
             |> Enum.count() == 1

      assert render_staff_card()
             |> LazyHTML.from_fragment()
             |> LazyHTML.query(~s([data-role="staff-attribution"]))
             |> Enum.empty?()
    end

    # `InboxConversation` has no such field at all — the card must omit the line
    # rather than raise, which is exactly what makes the shared-card reuse safe.
    test "omits the attribution for a row that has no such field" do
      assert render_card([], user_type: :provider)
             |> LazyHTML.from_fragment()
             |> LazyHTML.query(~s([data-role="staff-attribution"]))
             |> Enum.empty?()
    end

    test "hides the unread badge, which a non-participant can never have" do
      # Paired with a positive case on purpose: asserting only the absence would pass
      # just as happily against a mistyped selector.
      assert render_card([unread_count: 3], user_type: :provider)
             |> LazyHTML.from_fragment()
             |> LazyHTML.query(~s([data-role="unread-count"]))
             |> Enum.count() == 1

      assert render_staff_card()
             |> LazyHTML.from_fragment()
             |> LazyHTML.query(~s([data-role="unread-count"]))
             |> Enum.empty?()
    end
  end
end
