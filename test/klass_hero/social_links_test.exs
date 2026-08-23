defmodule KlassHero.SocialLinksTest do
  # async: false — mutates application env, which is global.
  use ExUnit.Case, async: false

  alias KlassHero.SocialLinks

  setup do
    original = Application.get_env(:klass_hero, :social_links)
    on_exit(fn -> Application.put_env(:klass_hero, :social_links, original) end)
    :ok
  end

  defp configure(links), do: Application.put_env(:klass_hero, :social_links, links)

  describe "all/0" do
    test "is empty with the shipped config, so the footer row does not render" do
      # Klass Hero has no accounts yet. This asserts the shipped default, which is
      # what keeps dead placeholder anchors off the page.
      assert SocialLinks.all() == []
    end

    test "returns only the networks that carry a url" do
      configure(instagram: "https://instagram.com/klasshero", facebook: nil, tiktok: nil)

      assert SocialLinks.all() == [
               {:instagram, "Instagram", "https://instagram.com/klasshero"}
             ]
    end

    test "treats blank and whitespace-only as unset" do
      configure(instagram: "", facebook: "   ", tiktok: nil)

      assert SocialLinks.all() == []
    end

    test "trims surrounding whitespace from a pasted url" do
      configure(youtube: "  https://youtube.com/@klasshero  ")

      assert [{:youtube, "YouTube", "https://youtube.com/@klasshero"}] = SocialLinks.all()
    end

    test "ignores a non-string value rather than crashing the footer" do
      configure(instagram: :not_a_url)

      assert SocialLinks.all() == []
    end

    test "returns networks in declared display order, not config order" do
      configure(linkedin: "https://linkedin.com/company/kh", instagram: "https://instagram.com/kh")

      assert [{:instagram, _, _}, {:linkedin, _, _}] = SocialLinks.all()
    end
  end

  describe "networks/0 and label/1" do
    test "every declared network has a brand label" do
      for network <- SocialLinks.networks() do
        assert is_binary(SocialLinks.label(network))
      end
    end

    test "raises on an unknown network rather than rendering a blank" do
      assert_raise KeyError, fn -> SocialLinks.label(:mastodon) end
    end
  end
end
