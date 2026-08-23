defmodule KlassHero.Messaging.EmailSanitizerTest do
  use ExUnit.Case, async: true

  alias KlassHero.Messaging.EmailSanitizer

  describe "sanitize/1" do
    test "preserves safe HTML tags" do
      html = "<p>Hello <strong>world</strong></p>"
      assert EmailSanitizer.sanitize(html) =~ "<p>"
      assert EmailSanitizer.sanitize(html) =~ "<strong>"
    end

    test "strips script tags" do
      html = "<p>Hello</p><script>alert('xss')</script>"
      result = EmailSanitizer.sanitize(html)
      refute result =~ "<script>"
      assert result =~ "<p>Hello</p>"
    end

    test "strips iframe tags" do
      html = "<p>Hello</p><iframe src=\"evil.com\"></iframe>"
      result = EmailSanitizer.sanitize(html)
      refute result =~ "<iframe>"
    end

    test "strips event handler attributes" do
      html = "<p onclick=\"alert('xss')\">Hello</p>"
      result = EmailSanitizer.sanitize(html)
      refute result =~ "onclick"
    end

    test "replaces external images with placeholder" do
      html = "<img src=\"https://tracker.com/pixel.gif\">"
      result = EmailSanitizer.sanitize(html)
      refute result =~ "https://tracker.com"
    end

    test "adds target=_blank to links" do
      html = "<a href=\"https://example.com\">Link</a>"
      result = EmailSanitizer.sanitize(html)
      assert result =~ "target=\"_blank\""
      assert result =~ "rel=\"noopener noreferrer\""
    end

    test "returns empty string for nil input" do
      assert EmailSanitizer.sanitize(nil) == ""
    end

    test "preserves table elements" do
      html = "<table><tr><td>Cell</td></tr></table>"
      result = EmailSanitizer.sanitize(html)
      assert result =~ "<table>"
      assert result =~ "<td>"
    end
  end

  describe "sanitize/2 with allow_images: true" do
    test "preserves external images when allowed" do
      html = "<img src=\"https://example.com/photo.jpg\">"
      result = EmailSanitizer.sanitize(html, allow_images: true)
      assert result =~ "https://example.com/photo.jpg"
    end
  end
end
