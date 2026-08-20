# Flow tests run without a browser; Wallaby covers what only a browser can

The end-to-end tier was seven Wallaby tests, all messaging, all in `test/e2e/messaging/`.
Measured against what it was there to prove, three things were wrong with it, and none of
them was the test count.

**No event was ever delivered.** `config/test.exs` points `:outbox` at `TestOutbox`, which
records staged events in the **process dictionary**. In a browser test the write happens in
the LiveView's process, so every event landed in a dictionary nobody reads and died with
that process. The `start_supervised!(ConversationSummaries)`, `rebuild_summaries()` and
`Process.sleep(500)` calls in `test/e2e/support/messaging_helpers.ex` were the workaround.

**The workaround masked the bug the tier existed to catch.** Asserting a read table after a
full `rebuild/0` means a projection that discards every event still passes. That is the
`projection-bootstrap-masks-discarded-events` shape, and it was built into the harness.

**None of the seven needed a browser.** Every one re-`visit()`ed the page rather than
asserting a live push. Meanwhile the things only a browser can prove — the four JS hooks in
`assets/js/hooks/`, the real login form, a real file upload, two concurrent live sessions —
had no coverage at all. The tier was paying browser prices for server-rendered assertions.

Separately it had rotted locally: `_build/chromedriver` was two Chrome majors behind, so
`mix test.e2e` was `0/7` with `** (RuntimeError) invalid session id`. A tier you cannot run
locally does not grow.

## Decision

**Two tiers, split by whether a browser is load-bearing.**

`test/flows/` holds **flow tests** on `phoenix_test` (`KlassHeroWeb.FlowCase`). A flow test
walks a whole journey across pages through the real router, the real plug pipeline, real
controller redirects and real session cookies, with no browser. `phoenix_test` chases 302s
and recycles cookies itself (`ConnHandler.visit/1`), so a multi-page chain is one pipe.

`test/e2e/` holds **browser tests** on Wallaby, restricted to a written charter.

| `test/flows/` — phoenix_test | `test/e2e/` — Wallaby |
|---|---|
| multi-page journeys, controller 302 chains, session cookies | the four JS hooks in `assets/js/hooks/` |
| forms, uploads via `upload/4`, projection-backed reads | duplicated `phx-trigger-action` forms (mobile + desktop) |
| anything assertable from server-rendered HTML | two concurrent sessions; a live push into an already-open page |
| | CSS-driven visibility — which duplicated element is actually clickable |

Flow tests sit under the default `mix test` path. They get **no tag, no alias and no CI job**
— `test/test_helper.exs` records that an excluded tag needs a runner, and this design adds
none.

### Flow tests use the real outbox

The registry in `config/config.exs` maps each topic to plain `{Module, :function}` tuples —
`{ProgramListings, :project}`, `{ConversationSummaries, :project}`. `EventDeliveryWorker`
calls them directly. So swapping `:outbox` to `ObanOutbox` and draining writes every read
table **with no projection GenServer running at all**.

`KlassHeroWeb.Journeys.with_real_outbox/1` is that swap, extracted from the eight files that
had copied it. Manual testing mode rather than the suite's `testing: :inline`, because inline
executes the delivery job at insert, inside the producer's own transaction.

This makes the flow tier strictly more faithful than the browser tier it replaces: an
unread count asserted after a real `messages_read` delivery is a claim about the projection;
the same count asserted after `rebuild/0` was a claim about the bootstrap query.

### Two rules that follow

**Arrange through the facade, never the read table.** `programs_live_test.exs` seeds
`program_listings` directly, so it can never prove a program reaches the catalog.
`Journeys.published_program/1` goes through `ProgramCatalog.create_program/1` and lets
delivery write the read table.

**Flow tests are `async: false`.** The outbox swap is a global `Application.put_env`; an async
test staging events alongside it would find `TestOutbox.staged()` empty. `FlowCase`'s `setup`
raises on `async: true` rather than leaving that as a convention — it cannot be caught at
compile time, because `ExUnit.CaseTemplate` applies the caller's opts before the template's
`using` block, which makes a nested `use ConnCase, async: false` inert.

## Consequences

**The magic-link login step cannot be driven by `phoenix_test`.**
`lib/klass_hero_web/live/user_live/confirmation.ex` renders two `phx-trigger-action` forms
(mobile and desktop), as does `login.ex`; `phoenix_test` raises `ArgumentError, "Found
multiple forms with phx-trigger-action."` on more than one.
`Journeys.follow_magic_link/1` therefore posts to `UserSessionController` directly. The
session write and the `signed_in_path/1` redirect still run for real; only the duplicated
client-side trigger is skipped, and by the table above that is browser-tier work. Collapsing
those duplicated forms into one CSS-controlled form would remove the workaround, and is
tracked separately.

**Wallaby stops being the answer to "test it for real".** It is now a small suite whose every
member fails for a browser-specific reason. Anything else that reaches for it should be a
flow test instead.

**A flow test is not free.** It is `async: false` and each `with_real_outbox/1` costs a drain.
The tier is meant to stay in the tens, covering main journeys — not to become where all
integration testing goes.

**A visited LiveView stays mounted for the rest of a flow test**, even after navigating
away, so "the user closed the tab" is not expressible in this tier. It matters wherever a
mounted page keeps reacting: a thread left open keeps marking arrivals read, which is why
`messaging_conversation_list_test.exs` arranges one read through the facade rather than
through the UI.

**`Oban.Testing.with_testing_mode/2` is process-local** (`Process.put`). A LiveView is a
different process, so a UI-driven act never sees `:manual` and its delivery jobs run inline,
inside the producer's transaction. Delivery still happens — which is what the tier needs —
but the manual-mode sequencing only applies to acts driven from the test process itself.
`with_real_outbox/1` therefore also drains *before* the act: a job left pending by an earlier
act would otherwise be delivered after this one, replaying a stale event out of order.

**Uploads are not covered yet.** A real `<input type=file>` was the fourth charter test and
was dropped: the inputs are `class="hidden"`, WebDriver will not type into a `display:none`
element, and unhiding it races LiveView's DOM patching into `Wallaby.StaleReferenceError`.
Fifteen `allow_upload/3` sites remain browser-untested; tracked separately.
