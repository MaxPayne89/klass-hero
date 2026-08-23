defmodule KlassHero.Messaging.EmailSanitizer do
  @moduledoc """
  Sanitizes inbound email HTML for safe rendering in the admin panel.

  Wraps `HtmlSanitizeEx.basic_html/1` (which strips dangerous tags and event
  handler attributes), then applies email-specific post-processing:
  - Blocks external images by default to prevent tracking pixels
  - Adds `target="_blank"` and `rel="noopener noreferrer"` to all links
  """

  @spec sanitize(String.t() | nil) :: String.t()
  # Separate arity to avoid a duplicate-default compile error when both
  # `sanitize/1` and `sanitize/2` would otherwise share `opts \\ []`.
  def sanitize(html), do: sanitize(html, [])

  @spec sanitize(String.t() | nil, keyword()) :: String.t()
  def sanitize(nil, _opts), do: ""
  def sanitize("", _opts), do: ""

  def sanitize(html, opts) when is_binary(html) do
    allow_images = Keyword.get(opts, :allow_images, false)

    html
    |> HtmlSanitizeEx.basic_html()
    |> post_process_links()
    |> maybe_block_images(allow_images)
  end

  # Adds target="_blank" rel="noopener noreferrer" to all links (tabnabbing prevention).
  defp post_process_links(html) do
    String.replace(html, ~r/<a\b/i, ~s(<a target="_blank" rel="noopener noreferrer"))
  end

  # External images blocked by default to prevent tracking pixels.
  defp maybe_block_images(html, false) do
    String.replace(html, ~r/<img\b[^>]*src="https?:\/\/[^"]*"[^>]*\/?>/i, "[image blocked]")
  end

  defp maybe_block_images(html, true), do: html
end
