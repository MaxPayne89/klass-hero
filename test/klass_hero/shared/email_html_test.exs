defmodule KlassHero.Shared.EmailHtmlTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias KlassHero.Shared.EmailHtml

  # The five characters esc/1 must neutralise, paired with their entities.
  @escapes [
    {"<", "&lt;"},
    {">", "&gt;"},
    {"&", "&amp;"},
    {"\"", "&quot;"},
    {"'", "&#39;"}
  ]

  # Generator biased toward the special characters — random :printable strings
  # almost never contain them, so an unbiased generator would only exercise the
  # passthrough clause. Mixing in plain chars and a multi-byte codepoint keeps
  # the UTF-8 clause covered too.
  defp html_ish do
    StreamData.string([?<, ?>, ?&, ?", ?', ?\s, ?a, ?z, ?0, ?9, ?é], max_length: 40)
  end

  describe "esc/1" do
    test "escapes each HTML-significant character to its entity" do
      for {char, entity} <- @escapes do
        assert EmailHtml.esc(char) == entity,
               "esc(#{inspect(char)}) should be #{inspect(entity)}"
      end
    end

    test "passes through plain text unchanged" do
      assert EmailHtml.esc("Hello World") == "Hello World"
    end

    test "handles the empty string" do
      assert EmailHtml.esc("") == ""
    end

    test "escapes every special character in a mixed XSS payload" do
      assert EmailHtml.esc("<script>alert('XSS & \"fun\"')</script>") ==
               "&lt;script&gt;alert(&#39;XSS &amp; &quot;fun&quot;&#39;)&lt;/script&gt;"
    end

    test "preserves multi-byte UTF-8 characters while escaping specials" do
      assert EmailHtml.esc("Schüler & Lehrer") == "Schüler &amp; Lehrer"
    end

    test "coerces non-binary terms via to_string/1 before escaping" do
      assert EmailHtml.esc(42) == "42"
      assert EmailHtml.esc(:ok) == "ok"
      assert EmailHtml.esc(nil) == ""
    end

    property "agrees with Phoenix.HTML.html_escape for any binary (oracle)" do
      check all(text <- html_ish()) do
        oracle = text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
        assert EmailHtml.esc(text) == oracle
      end
    end

    property "output never contains a raw <, >, \" or ' character" do
      check all(text <- html_ish()) do
        escaped = EmailHtml.esc(text)
        refute escaped =~ ~r/[<>"']/
      end
    end
  end

  describe "wrap/2" do
    test "embeds the inner_html verbatim (it is not escaped)" do
      assert EmailHtml.wrap("<p>Hello</p>") =~ "<p>Hello</p>"
    end

    test "renders a complete HTML document with KlassHero branding" do
      result = EmailHtml.wrap("<p>body</p>")

      assert result =~ "<!DOCTYPE html>"
      assert result =~ "<html>"
      assert result =~ "</html>"
      assert result =~ "KlassHero"
    end

    test "renders the default footer (escaped) when no option is given" do
      assert EmailHtml.wrap("<p>body</p>") =~ "If you didn&#39;t expect this email"
    end

    test "uses and escapes a custom :footer_message" do
      result = EmailHtml.wrap("<p>body</p>", footer_message: "Visit <example.com>")

      assert result =~ "Visit &lt;example.com&gt;"
    end

    property "always embeds the footer in escaped form" do
      check all(footer <- html_ish()) do
        result = EmailHtml.wrap("<p>body</p>", footer_message: footer)
        assert result =~ EmailHtml.esc(footer)
      end
    end
  end
end
