# LiveView Testing

Deep reference for testing Phoenix LiveView in this project. Read this when SKILL.md sends you here.

> **Mental model:** A LiveView test drives the LiveView through its public surface — the URL, form events, button clicks, navigation — and asserts on the rendered DOM and the app's observable side effects. **Always assert against DOM IDs you set explicitly in the template, never raw HTML or text content.** Cross-context business logic is stubbed via Mox; the LiveView test verifies the wiring, not the domain.

## Setup

```elixir
defmodule KlassHeroWeb.SomeLiveTest do
  use KlassHeroWeb.ConnCase, async: true     # ConnCase wraps Sandbox + Mox
  import Phoenix.LiveViewTest

  setup :register_and_log_in_user             # project helper — fixture user + scope
  setup :verify_on_exit!                      # if Mox expectations are involved
end
```

Why `ConnCase` (not `DataCase`)? Because LiveView tests need a `%Plug.Conn{}` to mount. Why `register_and_log_in_user`? Because the project uses `@current_scope` — most LiveViews `require_authenticated`.

## The Three Mount Modes

```elixir
# Live mode (the WebSocket handshake — most LV tests want this)
{:ok, view, html} = live(conn, ~p"/parent/children/invite")

# Static-only render (HTTP-fetched HTML, before WebSocket connects)
{:ok, html} = live_isolated(conn, MyLive)        # for component-style isolation
conn = get(conn, ~p"/...")                       # plain HTTP, no LV state

# Render after navigation
view |> follow_redirect(conn, "/expected/path")
```

Use `live/2` 99% of the time. The `view` is your handle for further interactions; `html` is the initial render string.

## Element Selection — DOM IDs Always

**Rule:** every form, button, and key region in a LiveView template needs an explicit `id=`. Tests select by ID via `has_element?/2` and `element/3`.

```heex
<%!-- TEMPLATE: explicit IDs at every assertion point --%>
<div id="invite-child" class="...">
  <.form for={@form} id="invite-child-form" phx-change="validate" phx-submit="save">
    <.input field={@form[:email]} id="invite-email" type="email" />
    <button type="submit" id="send-invite-btn">Send invite</button>
  </.form>

  <div :if={@invited?} id="invite-success">Sent!</div>
</div>
```

```elixir
# TEST: assert against IDs, not text
assert has_element?(view, "#invite-child-form")
assert has_element?(view, "#invite-email")
refute has_element?(view, "#invite-success")
```

`has_element?/3` accepts a third arg for text content when needed:

```elixir
assert has_element?(view, "#invite-success", "Sent!")
```

But **avoid this for structural assertions** — use it only when the text content itself is the assertion.

### Why not text matching?

```elixir
# ❌ FRAGILE — breaks on copy edits, i18n, whitespace, surrounding markup
assert render(view) =~ "Send invite"

# ✅ ROBUST — IDs change deliberately; copy changes routinely
assert has_element?(view, "#send-invite-btn")
```

## Triggering Events

### Forms

`form/3` returns a "form element" you pipe into render functions:

```elixir
# phx-change → render_change/1
view
|> form("#invite-child-form", child_invite: %{email: "kid@example.com", name: "Kid"})
|> render_change()

# phx-submit → render_submit/1
view
|> form("#invite-child-form", child_invite: %{email: "kid@example.com", name: "Kid"})
|> render_submit()
```

The second argument is the **params map** as the LiveView would receive them — top-level key matches the form's `for={@form}` binding (Phoenix wraps params under `"<schema_name>"`).

### Buttons / clicks

```elixir
# Click a button by ID
view |> element("#delete-btn") |> render_click()

# Click with extra params (sent as the event payload)
view |> element("#confirm-btn", "Yes") |> render_click(%{confirm: true})
```

### Hooks (`phx-hook`)

```elixir
# Send a hook event to the LiveView from JS-land
render_hook(view, "scroll-loaded", %{page: 2})
```

### URL changes (`handle_params`)

```elixir
view |> render_patch(~p"/programs?filter=open")
view |> render_navigate(~p"/elsewhere")
```

## Asserting on Navigation

Two flavours, two assertion macros. Pick correctly.

| LiveView calls | Test asserts with | Notes |
|---|---|---|
| `push_patch(socket, to: ~p"/...")` | `assert_patch(view, ~p"/...")` | Same LV, `handle_params` runs |
| `push_navigate(socket, to: ~p"/...")` | `assert_redirect(view, ~p"/...")` | Different LV — current view shuts down |
| `redirect(socket, to: ~p"/...")` (controller-style) | `assert_redirect(view, ~p"/...")` | Same as above |

```elixir
# Patch — current LV survives, params changed
view |> form("#filter-form", ...) |> render_submit()
assert_patch(view, ~p"/programs?status=open")

# Navigate — current LV is dead; you can't assert on `view` after
view |> element("#go-to-billing") |> render_click()
assert_redirect(view, ~p"/billing")

# Pattern-match on the destination (e.g. dynamic IDs)
{path, _flash} = assert_patch(view)
assert path =~ ~r"/programs/\d+"
```

## Asserting on Flash Messages (LiveView 1.1 idiom)

This is where baselines often go wrong. `Phoenix.Flash.get/2` is the modern accessor.

```elixir
# After render_submit / render_click / render_change
view
|> form("#invite-child-form", child_invite: valid_params)
|> render_submit()

# Flash is on the view itself in LV 1.1+
assert Phoenix.Flash.get(view |> Phoenix.LiveViewTest.assigns() |> Map.get(:flash), :info) ==
         "Invite sent!"
```

If the LV navigates away (`push_navigate`), the flash transfers to the new conn:

```elixir
{path, flash} = assert_redirect(view)
assert path == ~p"/parent/children"
assert Phoenix.Flash.get(flash, :info) == "Invite sent!"
```

For `push_patch` (same LV), use the second return form of `assert_patch/2`:

```elixir
{_path, flash} = assert_patch(view)
assert flash["info"] == "Invite sent!"
```

**Don't write** `assert result =~ "Invite sent!" or render(view) =~ "Invite sent!"` — that's the baseline anti-pattern. It tries to assert against the rendered HTML for the flash, but flash is rendered by the layout, not necessarily in the LV's DOM after navigation. Use `Phoenix.Flash.get/2` against the explicit flash map.

## Asserting Against Forms with Errors

After a failed `phx-submit`, the form re-renders with errors attached to fields. Assert against the rendered error DOM (which `<.input>` produces inside an element with `data-` or class hooks):

```elixir
# Submit invalid params
html =
  view
  |> form("#invite-child-form", child_invite: %{email: "", name: ""})
  |> render_submit()

# Form is still on the page (no navigation)
assert has_element?(view, "#invite-child-form")
refute has_element?(view, "#invite-success")

# The specific error is in the rendered HTML for that field
assert html =~ "can&#39;t be blank"   # &#39; because rendered as HTML entity

# Or — better — parse the input wrapper and look inside
parsed = html |> Floki.parse_document!()
[error_node] = Floki.find(parsed, "[phx-feedback-for='child_invite[email]']")
assert Floki.text(error_node) =~ "can't be blank"
```

If the project's `<.input>` core component renders errors with a stable `id` per field, prefer that:

```elixir
assert has_element?(view, "#invite-email-error", "can't be blank")
```

## Mocking Cross-Context Calls

LiveView tests should NOT exercise real cross-context business logic — that's the use case's responsibility, tested in its own unit/integration test. The LV test stubs the port and verifies the LV called the use case correctly.

### Pattern: Mox-backed port

Assume the LV calls `Family.send_child_invite/2`, which under the hood resolves to a port:

```elixir
# In the use case module:
defp invite_sender, do: Application.get_env(:klass_hero, :family)[:for_sending_invite_emails]

# In the LV test:
test "successful submit fires the invite + flash + patch", %{conn: conn, current_scope: scope} do
  Mox.expect(KlassHero.Family.InviteSenderMock, :send, fn ^scope, params ->
    assert params["email"] == "kid@example.com"
    {:ok, %Invite{id: "abc-123"}}
  end)

  {:ok, view, _html} = live(conn, ~p"/parent/children/invite")

  view
  |> form("#invite-child-form", child_invite: %{email: "kid@example.com", name: "Kid"})
  |> render_submit()

  {path, flash} = assert_patch(view)
  assert path == ~p"/parent/children"
  assert Phoenix.Flash.get(flash, :info) == "Invite sent!"
end
```

If the LV invokes `Family.send_child_invite/2` directly (no port), and `Family` is a context module, you have two options:

1. **Stub the cross-context boundary at the port level** (preferred — DDD architecture).
2. **Use a real test factory + sandbox** — let the call hit the real DB and the real domain. Slower but covers the whole vertical slice.

### Pattern: Inserting test data via Factory

For LV tests that need pre-existing DB state (e.g. a list view):

```elixir
test "renders the parent's invites", %{conn: conn, current_scope: scope} do
  invite_a = Factory.insert!(:child_invite, parent_id: scope.user.id, email: "a@example.com")
  invite_b = Factory.insert!(:child_invite, parent_id: scope.user.id, email: "b@example.com")

  {:ok, view, _html} = live(conn, ~p"/parent/children")

  assert has_element?(view, "#invite-row-#{invite_a.id}", "a@example.com")
  assert has_element?(view, "#invite-row-#{invite_b.id}", "b@example.com")
end
```

Note: each rendered row gets `id="invite-row-<id>"` in the template. That's not optional — without IDs the test can only fall back to text matching.

## LiveView Streams

The project rule (`.claude/rules/liveview.md`) requires `stream/3` for all collections. Tests must respect that.

```heex
<div id="invites" phx-update="stream">
  <div :for={{dom_id, invite} <- @streams.invites} id={dom_id}>
    <span>{invite.email}</span>
  </div>
</div>
```

```elixir
# Each streamed item has its own `id` (`<resource>-<id>`).
# Test assertions:
assert has_element?(view, "#invites-#{invite.id}", invite.email)

# Filter / re-stream test:
view |> form("#filter-form", q: "foo") |> render_change()
assert has_element?(view, "#invites-#{matching.id}")
refute has_element?(view, "#invites-#{non_matching.id}")
```

LiveView streams are **not enumerable** — you can't iterate `@streams.invites` outside the template. Tests assert per-item via the DOM ID.

## PubSub & Real-Time Updates

When a LiveView subscribes to PubSub and updates on broadcast:

```elixir
test "list updates when an invite is created elsewhere", %{conn: conn, current_scope: scope} do
  {:ok, view, _html} = live(conn, ~p"/parent/children")

  # Simulate a broadcast from another process / context
  Phoenix.PubSub.broadcast(
    KlassHero.PubSub,
    "family:#{scope.user.id}",
    {:invite_created, %Invite{id: "new-1", email: "new@example.com"}}
  )

  # Wait for the LV to handle the message and re-render
  assert render(view) =~ "new@example.com"
  # …or, better:
  assert has_element?(view, "#invites-new-1", "new@example.com")
end
```

`render(view)` synchronizes — it forces the LV to process pending messages before returning. Use it as a sync point when waiting for an async render.

## File Uploads

```elixir
test "uploads a profile photo", %{conn: conn} do
  {:ok, view, _html} = live(conn, ~p"/profile/edit")

  upload =
    file_input(view, "#profile-form", :photo, [
      %{name: "me.png", content: File.read!("test/fixtures/me.png"), type: "image/png"}
    ])

  assert render_upload(upload, "me.png") =~ "100%"
  view |> form("#profile-form") |> render_submit()

  assert_patch(view, ~p"/profile")
end
```

## Common Mistakes

| Mistake | Fix |
|---|---|
| Asserting `result =~ "text"` for flash | Use `Phoenix.Flash.get(flash, :info)` from `assert_patch` / `assert_redirect`'s second return |
| `render(view) =~ "..."` for structural assertions | Add an `id="..."` to the template, assert with `has_element?(view, "#...")` |
| `assert_redirect` after `push_patch` (or vice-versa) | Match the macro to what the LV does — patch vs navigate |
| Using `view` after `assert_redirect` | The LV is dead; build a fresh `conn` and `live(conn, new_path)` |
| Calling cross-context functions in tests without stubs | Mox the port; assert the call shape inside the `expect` body |
| Test imports `<.form>` from the layout component | Use `Phoenix.LiveViewTest.form/3`, not the rendering helper |
| `async: true` with `set_mox_global` | Doesn't work — global Mox forces sync |
| Forgetting `Mox.verify_on_exit!()` setup | Expectations silently pass even if never called |
| Asserting on an empty form's value | The first render has empty inputs; assert that AND assert render_change updates them |
| Submitting params with string keys when LV expects atoms (or vice-versa) | The `form/3` helper takes atom keys; LV receives string keys. Pass `child_invite: %{email: "..."}` (atom outer, atoms inner are stringified). |

## Quick Reference

### Setup checklist
- [ ] `use KlassHeroWeb.ConnCase, async: true`
- [ ] `import Phoenix.LiveViewTest`
- [ ] `setup :register_and_log_in_user` (if auth required)
- [ ] `setup :verify_on_exit!` (if using Mox)
- [ ] Pre-stub any cross-context ports

### Test coverage checklist (per LiveView)
- [ ] Initial mount renders the expected key elements (form / button / region IDs)
- [ ] Initial mount does NOT show success / error states
- [ ] `phx-change` event re-renders form with submitted values; no nav
- [ ] `phx-submit` happy path: side effect (Mox / DB), flash, navigation
- [ ] `phx-submit` error path: form re-renders with errors, NO nav, NO side effect
- [ ] Authorization: unauthenticated request redirects to login (if applicable)
- [ ] Real-time updates via PubSub (if applicable)

### Common helpers reference

| Helper | Purpose |
|---|---|
| `live(conn, path)` | Mount, returns `{:ok, view, html}` |
| `render(view)` | Sync + return current HTML; useful as a wait point |
| `has_element?(view, sel)` / `has_element?(view, sel, text)` | Existence check by CSS selector |
| `element(view, sel)` / `element(view, sel, text_filter)` | Get an element handle for further interaction |
| `form(view, sel, params)` | Form handle — pipe into `render_change` / `render_submit` |
| `render_change(elem)` / `render_submit(elem)` / `render_click(elem)` | Trigger LV events |
| `render_patch(view, path)` / `render_navigate(view, path)` | Simulate URL change |
| `render_hook(view, name, params)` | Trigger a JS hook event |
| `assert_patch(view, path)` / `assert_redirect(view, path)` | Assert navigation; second-arg-less form returns `{path, flash}` |
| `file_input(view, form_sel, name, files)` + `render_upload(input, name)` | Test file uploads |
| `follow_redirect(view, conn, path)` | Follow a redirect to a new conn for chained assertions |
| `Phoenix.Flash.get(flash, :info)` | Read a flash entry — use the flash from `assert_*` |

## See also

- `exunit-core.md` — Mox patterns, ConnCase, sandbox setup
- `stream-data.md` — properties for LiveView pure helper modules
- `.claude/rules/liveview.md` — project's LiveView conventions (streams, hooks, forms)
- `.claude/rules/phoenix.md` — HEEx + form rules
- Hex docs: <https://hexdocs.pm/phoenix_live_view/Phoenix.LiveViewTest.html>
