defmodule KlassHeroWeb.ContactLiveTest do
  use KlassHeroWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "ContactLive" do
    test "renders peach hero with yellow help highlight + form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/contact")

      assert has_element?(view, "#mk-contact-hero")
      assert has_element?(view, "#mk-contact-hero h1", "We're here to")
      assert has_element?(view, "#mk-contact-hero h1 span.bg-hero-yellow-500", "help")
      assert has_element?(view, "#contact-form")
    end

    test "renders under :marketing chrome", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/contact")

      assert has_element?(view, "header.sticky nav a", "Contact")
      assert html =~ "Privacy"
      assert html =~ "Terms"
    end

    test "displays contact information from config", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/contact")

      # Trigger: contact config has email set, phone/address nil
      # Why: only configured contact methods should render
      email = Application.get_env(:klass_hero, :contact, [])[:email]
      assert email, "expected :contact config to have :email set"
      assert html =~ email

      # Phone and address are nil in config, so they should not appear
      refute html =~ "+1 (555) 123-4567"
      refute html =~ "123 Youth Avenue"
    end

    test "validates required fields", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/contact")

      render_change(view, "validate", %{
        "contact" => %{
          "name" => "",
          "email" => "",
          "subject" => "",
          "message" => ""
        }
      })

      html = render(view)
      assert html =~ "can&#39;t be blank" or html =~ "can't be blank"
    end

    test "validates name length constraints", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/contact")

      render_change(view, "validate", %{
        "contact" => %{
          "name" => "A",
          "email" => "test@example.com",
          "subject" => "general",
          "message" => "This is a test message with enough characters"
        }
      })

      html = render(view)
      assert html =~ "should be at least 2 character"

      long_name = String.duplicate("A", 101)

      render_change(view, "validate", %{
        "contact" => %{
          "name" => long_name,
          "email" => "test@example.com",
          "subject" => "general",
          "message" => "This is a test message with enough characters"
        }
      })

      html = render(view)
      assert html =~ "should be at most 100 character"
    end

    test "validates email format", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/contact")

      render_change(view, "validate", %{
        "contact" => %{
          "name" => "John Doe",
          "email" => "invalid-email",
          "subject" => "general",
          "message" => "This is a test message with enough characters"
        }
      })

      html = render(view)
      assert html =~ "must be a valid email address"
    end

    test "validates message length constraints", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/contact")

      render_change(view, "validate", %{
        "contact" => %{
          "name" => "John Doe",
          "email" => "john@example.com",
          "subject" => "general",
          "message" => "Short"
        }
      })

      html = render(view)
      assert html =~ "should be at least 10 character"

      long_message = String.duplicate("A", 1001)

      render_change(view, "validate", %{
        "contact" => %{
          "name" => "John Doe",
          "email" => "john@example.com",
          "subject" => "general",
          "message" => long_message
        }
      })

      html = render(view)
      assert html =~ "should be at most 1000 character"
    end

    test "validates subject is from allowed options", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/contact")

      render_change(view, "validate", %{
        "contact" => %{
          "name" => "John Doe",
          "email" => "john@example.com",
          "subject" => "invalid_subject",
          "message" => "This is a test message with enough characters"
        }
      })

      html = render(view)
      assert html =~ "is invalid"
    end

    test "accepts valid form submission", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/contact")

      render_submit(view, "submit", %{
        "contact" => %{
          "name" => "John Doe",
          "email" => "john@example.com",
          "subject" => "general",
          "message" => "This is a test message with enough characters to pass validation"
        }
      })

      html = render(view)
      assert html =~ "Message sent successfully!"

      assert html =~ "We&#39;ve got it" or html =~ "We've got it"
    end

    test "resets form after successful submission", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/contact")

      render_submit(view, "submit", %{
        "contact" => %{
          "name" => "John Doe",
          "email" => "john@example.com",
          "subject" => "general",
          "message" => "This is a test message with enough characters to pass validation"
        }
      })

      html = render(view)
      refute html =~ "value=\"John Doe\""
      refute html =~ "value=\"john@example.com\""
    end

    test "displays validation errors on submit with invalid data", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/contact")

      render_submit(view, "submit", %{
        "contact" => %{
          "name" => "A",
          "email" => "invalid",
          "subject" => "general",
          "message" => "Short"
        }
      })

      html = render(view)
      assert html =~ "should be at least 2 character" or html =~ "should be at least 10 character"
      refute html =~ "Message sent successfully!"
    end

    test "allows all valid subject options", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/contact")

      valid_subjects = ~w(general program booking instructor technical other)

      for subject <- valid_subjects do
        render_change(view, "validate", %{
          "contact" => %{
            "name" => "John Doe",
            "email" => "john@example.com",
            "subject" => subject,
            "message" => "This is a test message with enough characters"
          }
        })

        html = render(view)
        refute html =~ "is invalid"
      end
    end

    test "anonymous visitor sees blank name and email fields", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/contact")

      # No logged-in user → nothing to prefill; value attr is omitted entirely
      refute has_element?(view, "input#contact_name[value]")
      refute has_element?(view, "input#contact_email[value]")
    end

    test "real-time validation updates as user types", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/contact")

      render_change(view, "validate", %{
        "contact" => %{
          "name" => "John Doe",
          "email" => "invalid",
          "subject" => "general",
          "message" => "This is a test message"
        }
      })

      html = render(view)
      assert html =~ "must be a valid email address"

      render_change(view, "validate", %{
        "contact" => %{
          "name" => "John Doe",
          "email" => "john@example.com",
          "subject" => "general",
          "message" => "This is a test message"
        }
      })

      html = render(view)
      refute html =~ "must be a valid email address"
    end
  end

  describe "ContactLive prefill for logged-in users" do
    setup :register_and_log_in_user

    test "prefills name and email from the current user", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/contact")

      assert has_element?(view, "input#contact_name[value='#{user.name}']")
      assert has_element?(view, "input#contact_email[value='#{user.email}']")
    end
  end
end
