# Runbook: Host & Infrastructure Metrics (Fly.io)

**Purpose:** See CPU, memory, disk, and network health for the running app.
**Cost:** Free. Fly.io includes managed Prometheus + Grafana at no extra charge.
**Owner:** Technical founder. No app code required for host metrics.

## Division of labour (which tool for what)

| Question | Tool | Retention |
|---|---|---|
| Is a business flow failing? Who/why? (traces, errors, funnels) | **Honeycomb** (`live` env) — see the *Business Health* board | 60 days |
| Is the host healthy? CPU/mem/disk/network | **Fly Grafana** (this runbook) | ~15 days |
| BEAM internals (process count, run-queue, memory-by-type) | Not collected yet — see *Phase 2* below | — |

Honeycomb is for **application behaviour**; Fly Grafana is for **infrastructure**. Don't
pipe host metrics into Honeycomb — Fly already provides them free and it keeps the two
concerns cleanly separated.

## Accessing the dashboards

1. Go to **https://fly-metrics.net** (managed Grafana, log in with your Fly account), **or**
   run `fly dashboard metrics -a klass-hero-dev`.
2. Open the built-in **"Fly Instance"** / **"Fly App"** dashboards. The Prometheus
   datasource is pre-wired — no setup.
3. Scope to app `klass-hero-dev`, region `fra`.

## What you get out of the box (zero instrumentation)

- **CPU:** `fly_instance_cpu` (+ baseline / balance / throttle — the last two matter on
  our `shared` CPU VM; sustained throttle = we're being CPU-limited).
- **Memory:** `fly_instance_memory_*` (total, available, cached, swap). Our VM is **1 GB**
  (`fly.toml [[vm]]`) — watch `memory_available` trending toward zero and swap climbing.
- **Disk:** `fly_instance_disk_*` (I/O ops).
- **Network:** `fly_instance_net_*` (bytes/packets in/out, errors).
- **Edge:** `fly_edge_http_responses_count`, `fly_app_concurrency`.

## Important caveat — gaps are not outages

`fly.toml` sets `auto_stop_machines = "suspend"` and `min_machines_running = 0`, so the
machine **suspends when idle**. A suspended machine emits no metrics, so you'll see **gaps**
in the CPU/mem graphs at low-traffic times. That is expected — not downtime. A real outage
shows as failing `/health` checks (also in Fly), not merely a metric gap.

## Verification (after enabling)

- [ ] `fly-metrics.net` loads and shows the `klass-hero-dev` app.
- [ ] CPU and memory panels render data for the last hour (trigger some traffic if the
      machine was suspended).
- [ ] Memory panel shows the 1 GB ceiling and current usage.

## Phase 2 (optional, requires code) — BEAM/Elixir VM internals

Fly does **not** infer BEAM internals (Erlang process count, run-queue length,
memory-by-type, Oban queue depth). To get those into Fly Grafana for free:

1. Add **PromEx** (`{:prom_ex, "~> 1.11"}`) — it ships plugins for `Beam`, `Phoenix`,
   `Ecto`, `LiveView`, `Oban`. It exposes a Prometheus-format `/metrics` endpoint.
2. Declare the scrape target in `fly.toml`:
   ```toml
   [metrics]
     port = 4000
     path = "/metrics"
   ```
   Fly auto-scrapes every 15s into the same managed Prometheus.

Note the existing `KlassHeroWeb.Telemetry.periodic_measurements/0` returns `[]` — the VM
metrics are *declared* in `metrics/0` but nothing polls/exports them. PromEx replaces that
gap. **Deferred** until a BEAM-level problem actually surfaces; host metrics above cover
the common "is it about to fall over" questions.
