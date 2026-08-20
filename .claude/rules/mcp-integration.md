# MCP Server Integration

The project uses **Model Context Protocol (MCP) servers** for enhanced development workflows.

## Tidewave MCP Server (Elixir/Phoenix)

**Purpose:** Interactive Elixir REPL and Phoenix application interaction

### When to Use Tidewave Instead of Bash

- Evaluating Elixir code: `project_eval`
- Getting documentation: `get_docs`
- Finding source code: `get_source_location`
- Executing SQL queries: `execute_sql_query`
- Checking logs: `get_logs`
- Inspecting Ecto schemas: `execute_sql_query` against `information_schema` for column truth,
  plus CodeGraph (or `get_source_location`) to find the schema module. Tidewave 0.9.0 removed
  the dedicated `get_ecto_schemas` tool — do not re-add it here.

### Common Tidewave Commands

```elixir
# Evaluate Elixir code in project context
project_eval(code: "KlassHero.Repo.all(KlassHero.Accounts.User)")

# Get documentation for a module or function
get_docs(reference: "Ecto.Changeset")

# Find source location
get_source_location(reference: "KlassHero.Accounts")

# Execute SQL query
execute_sql_query(query: "SELECT * FROM users LIMIT 5")

# Get application logs
get_logs(tail: 50, grep: "error")
```

### Critical: Tidewave MCP Integration Priority

For this Phoenix/Elixir project, Tidewave MCP is essential for optimal development workflow:

- **Always prefer Tidewave** over bash/shell tools for any Elixir evaluation, documentation, or project introspection
- **Maximize Tidewave usage** - it provides superior project context and direct interaction with running Phoenix application
- **Alert immediately if Tidewave becomes unavailable** - this indicates a critical development environment issue requiring user attention

### Tidewave Unavailability Alert Protocol

When Tidewave is not connected or fails to respond:

1. **Immediate notification**: Clearly alert the user with:
   ```
   TIDEWAVE MCP NOT RESPONDING
   [Reason: describe what failed]
   [Impact: what functionality is unavailable]
   [Next step: suggest remedial action]
   ```

2. **Investigation required**: run `bin/worktree-status` first — it answers the two
   questions that matter in one shot: is a server answering on this checkout's port,
   and does that server actually *live in this checkout*. Its verdict maps to a cause:

   | Verdict | Cause |
   |---|---|
   | `NOT RUNNING` | no dev server — run `bin/worktree-up` |
   | `NOT CONFIGURED` | no port claimed in `.claude/run/port` — run `bin/worktree-up` |
   | `ORPHAN` | a server from a deleted checkout is answering; `bin/worktree-up` reaps it |
   | `WRONG CHECKOUT` | another live checkout holds the port; **do not use Tidewave from here** |
   | `READY` | the server is fine. Tidewave calls resolve the target per request via `bin/tidewave-router`, so no restart is needed — retry the call. If it still fails, check `claude mcp get tidewave` reports `Connected` (a missing `node` leaves the session with no Tidewave tools) |

3. **Never silently degrade**: Do not fall back to bash/shell evaluation without explicitly notifying the user that Tidewave is unavailable

## Chrome DevTools MCP Server (Browser Testing)

**Purpose:** Automated browser testing and interaction. This is the project's browser tool of record (it replaced Playwright MCP) — it wins on the axis this app cares about most, real mobile emulation, and adds Lighthouse and performance tracing for free.

### Use Chrome DevTools For

- Testing LiveView interactions and flows
- Verifying **mobile-responsive** designs — `emulate` gives true device viewport + touch + device-pixel-ratio + network/CPU throttling, not just a window resize
- Taking screenshots of UI changes
- Navigating multi-step processes (enrollment, booking)
- **Lighthouse accessibility/perf audits** (`lighthouse_audit`) and **Core Web Vitals traces** (`performance_start_trace` / `performance_analyze_insight`)
- Catching browser-native a11y issues via `list_console_messages` (`types: ["issue"]`)

### Common Chrome DevTools Commands

```javascript
// Navigate to a page
navigate_page(type: "url", url: "http://localhost:4000/programs")

// Snapshot the accessibility tree (returns element uids to act on)
take_snapshot()

// Take screenshot
take_screenshot()

// Click an element (target by uid from the latest snapshot)
click(uid: "…")

// Fill a form
fill_form(elements: [{ uid: "…", value: "…" }])

// Emulate a mobile device for responsive checks
emulate(viewport: "375x667x2,mobile,touch")
```

**Snapshot uids go stale on any DOM change.** After a navigation, `phx-update`, or form submit, call `take_snapshot` again before targeting an element — this matters more on LiveView than on a static page.

**Known limitations / escape hatch.** Chrome DevTools MCP has no multi-step scripting (Playwright's `browser_run_code_unsafe`), no one-call `<select multiple>`, and no external file/MIME drag-drop. The Playwright plugin remains installed globally; reach for it only for those specific edge cases.

## Testing Workflow with MCP

1. Start Phoenix server: `mix phx.server`
2. Use **Tidewave** to check application state, run queries, evaluate code
3. Use **Chrome DevTools** to test UI flows and interactions
4. Use **Tidewave** to check logs for warnings/errors
5. Treat all warnings as errors to be addressed immediately

## Important Note

- **Always use Tidewave MCP server** for Phoenix application interaction instead of bash tools
- **Always use Chrome DevTools and/or Tidewave** to test changes by going through affected module flows
