# Runbook: Scheduling `prod-watch` (on-machine / launchd)

`/prod-watch` sweeps prod for new issues, diagnoses them via `/analyze-prod-issue`, and auto-files
a `bug` + `priority:high` issue per real user-blocker. This runbook schedules it to run every 12h
on your Mac, unattended.

**Why on-machine (Path 1):** the sweep reaches prod through `bin/prod-db` (`fly mpg connect`) and
the Honeycomb MCP session — both authenticated interactively in *your* login. A launchd agent runs
as you and inherits `~/.fly/config.yml`, so **no headless token is needed**. See
`docs/runbooks/prod-db-access.md` for the prod-DB half.

## The one real gotcha: launchd's stripped environment

launchd starts jobs with almost no environment — no `PATH`, no guaranteed `HOME`. A run that works
in your terminal fails under launchd as `fly: command not found` or "can't find `~/.fly/config.yml`",
which *reads* like an auth failure but is an env failure. `bin/prod-watch` sets `HOME`/`PATH` and
runs `bin/prod-db --check` as a fast-fail preflight so this surfaces clearly in the log.

## Install

1. Preflight by hand first (proves auth + PATH before scheduling):

   ```bash
   bin/prod-watch --check
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
       <string>/Users/maximilianpergl/Projects/klass-hero/bin/prod-watch</string>
     </array>
     <key>EnvironmentVariables</key>
     <dict>
       <key>HOME</key><string>/Users/maximilianpergl</string>
       <!-- ~/.local/bin holds `claude`; /opt/homebrew/bin holds gh/fly/psql -->
       <key>PATH</key><string>/Users/maximilianpergl/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
     </dict>
     <key>StartInterval</key>    <integer>43200</integer> <!-- 12h -->
     <key>RunAtLoad</key>        <false/>
     <key>StandardOutPath</key>  <string>/Users/maximilianpergl/Projects/klass-hero/.prod-watch/log/out.log</string>
     <key>StandardErrorPath</key><string>/Users/maximilianpergl/Projects/klass-hero/.prod-watch/log/err.log</string>
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
tail -f .prod-watch/log/out.log .prod-watch/log/err.log
```

A clean run ends with the preflight `✓` and either filed-issue notifications or a clean sweep.

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
