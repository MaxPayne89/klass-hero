# Runbook: Scheduling `prod-watch` (on-machine / launchd)

`/prod-watch` sweeps prod for new issues, diagnoses them via `/analyze-prod-issue`, and auto-files
a `bug` + `priority:high` issue per real user-blocker. This runbook schedules it to run every 12h
on your Mac, unattended.

**Why on-machine (Path 1):** the sweep reaches prod through `bin/prod-db` (`fly mpg connect`) and
the Honeycomb MCP session — both authenticated interactively in *your* login. A launchd agent runs
as you and inherits `~/.fly/config.yml`, so **no headless token is needed**. See
`docs/runbooks/prod-db-access.md` for the prod-DB half.

## Two gotchas the setup is built around

1. **launchd's stripped environment** — jobs start with almost no environment (no `PATH`, no
   guaranteed `HOME`, cwd `/`). A run that works in your terminal fails under launchd as
   `fly: command not found`, "can't find `~/.fly/config.yml`", or a skill-not-found — all of which
   *read* like other failures but are env failures. `bin/prod-watch` sets `HOME`/`PATH`, `cd`s into
   its repo (so `claude` discovers `.claude/skills/`), and runs `bin/prod-db --check` as a fast-fail
   preflight so this surfaces clearly in the log.
2. **Branch coupling** — launchd runs whatever is *checked out* at the wrapper's path when the
   timer fires. Pointed at your primary working tree (which branch-switches), a scheduled sweep
   could run stale or unrelated code. Fix: a **dedicated worktree pinned to `main`** that
   self-updates each run.

## Pinned worktree (the stable checkout the scheduler runs from)

The scheduler runs from its own source-only worktree, never your primary tree:

```bash
git worktree add --detach ~/Projects/klass-hero-prod-watch origin/main
```

- `--detach` because `main` is already checked out in your primary tree (git forbids the same
  branch in two worktrees). The wrapper's self-update (`fetch` + `reset --hard FETCH_HEAD`, gated on
  `PROD_WATCH_SELF_UPDATE=1` set only in the plist) advances this detached HEAD to canonical `main`
  every run — so scheduled sweeps are independent of whatever your primary tree is doing.
- **Source-only — no `mix deps.get`/compile/test DB.** `/prod-watch` runs SQL via `bin/prod-db`
  (a `fly` proxy, no mix) + Honeycomb + `gh`; none need the app compiled.
- **Machine-owned — never edit this tree by hand.** The self-update `reset --hard`s it every run;
  local edits would be wiped. `.prod-watch/` (watermark + logs) is gitignored, so it survives.

## Install

1. Preflight by hand first (proves auth + PATH + cwd before scheduling):

   ```bash
   ~/Projects/klass-hero-prod-watch/bin/prod-watch --check
   ```

2. Create `~/Library/LaunchAgents/com.klasshero.prod-watch.plist`:

   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
     "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
     <key>Label</key>            <string>com.klasshero.prod-watch</string>
     <key>ProgramArguments</key>
     <array>
       <string>/Users/maximilianpergl/Projects/klass-hero-prod-watch/bin/prod-watch</string>
     </array>
     <key>EnvironmentVariables</key>
     <dict>
       <key>HOME</key><string>/Users/maximilianpergl</string>
       <!-- ~/.local/bin holds `claude`; /opt/homebrew/bin holds gh/fly/psql -->
       <key>PATH</key><string>/Users/maximilianpergl/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
       <!-- authorizes the wrapper's self-update; set ONLY here, never in the primary tree -->
       <key>PROD_WATCH_SELF_UPDATE</key><string>1</string>
     </dict>
     <key>StartInterval</key>    <integer>43200</integer> <!-- 12h -->
     <key>RunAtLoad</key>        <false/>
     <key>StandardOutPath</key>  <string>/Users/maximilianpergl/Projects/klass-hero-prod-watch/.prod-watch/log/out.log</string>
     <key>StandardErrorPath</key><string>/Users/maximilianpergl/Projects/klass-hero-prod-watch/.prod-watch/log/err.log</string>
   </dict>
   </plist>
   ```

3. Load it:

   ```bash
   launchctl load ~/Library/LaunchAgents/com.klasshero.prod-watch.plist
   launchctl list | grep prod-watch          # confirm it's registered
   ```

## Verify the scheduled env (the Path-1 risk)

Force a run and read the log — this is the check that `fly`/`psql`/`gh`/`claude` all resolve under
launchd's stripped env, not just in your shell:

```bash
launchctl start com.klasshero.prod-watch
tail -f ~/Projects/klass-hero-prod-watch/.prod-watch/log/out.log \
        ~/Projects/klass-hero-prod-watch/.prod-watch/log/err.log
```

A clean run ends with the preflight `✓` and either filed-issue notifications or a clean sweep. To
prove branch-independence, check out any old branch in your *primary* tree first — the run still
executes `main`'s skill from the pinned worktree.

## Manage

```bash
launchctl unload ~/Library/LaunchAgents/com.klasshero.prod-watch.plist   # stop scheduling
launchctl start com.klasshero.prod-watch                                 # run now, on demand
```

`StartInterval` fires 12h after load and every 12h thereafter (missed runs while the Mac is asleep
coalesce into one on wake). Nothing runs while the machine is off — the accepted cost of Path 1.

## When auth lapses

If you `fly auth logout` or the login token expires, the next run fails at the `bin/prod-db --check`
preflight and logs the fix. Re-run `fly auth login`; no plist change needed.
