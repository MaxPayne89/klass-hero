defmodule KlassHeroWeb.MessagingComponentsTest do
  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.Factory
  import Phoenix.LiveViewTest

  alias KlassHeroWeb.MessagingComponents

  defp render_card(summary_attrs, opts \\ []) do
    render_component(&MessagingComponents.conversation_card/1, %{
      id: "conv-test",
      summary: build(:conversation_summary_schema, summary_attrs),
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
end
