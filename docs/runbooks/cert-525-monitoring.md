# Runbook: Prod TLS cert-expiry + uptime monitoring (Cloudflare 525)

**Purpose:** Detect a stuck Let's Encrypt cert renewal or origin-TLS failure on
`klasshero.com` **before** customers see a Cloudflare HTTP 525.
**Cost:** Free. UptimeRobot free tier + email alerts.
**Owner:** Technical founder. No app code involved.

## Why this exists

On **2026-05-30** klasshero.com went fully down with **Cloudflare HTTP 525** (SSL
handshake failed between Cloudflare and the Fly origin). The per-hostname Let's
Encrypt cert for `klasshero.com` on Fly app `klass-hero-live` had **expired** — its
auto-renewal was silently blocked because Cloudflare's proxy intercepts Fly's
HTTP-01 ACME challenge, so Let's Encrypt cannot validate. The first signal was a
customer-facing outage; nothing alerted us. This runbook closes that detection gap.

## The failure mode

| Fact | Value |
|---|---|
| Symptom | Every visitor gets Cloudflare **HTTP 525**, `server: cloudflare` |
| Root cause | Per-hostname LE cert **expired**; renewal blocked by Cloudflare proxy intercepting the HTTP-01 ACME challenge |
| Where it lives | The **Cloudflare→Fly origin leg** only. It is *not* a Fly or Cloudflare outage, and *not* a code change |
| Prod app | `klass-hero-live` (region `fra`), behind Cloudflare orange-cloud proxy |
| Why dev is immune | `klass-hero-dev.fly.dev` has no Cloudflare and rides the wildcard `*.fly.dev` cert |

**Key subtlety:** the 525 appears **only on the proxied leg**. The Fly origin
(`klass-hero-live.fly.dev/health`) and Fly's own health checks stay green during the
outage. App-level observability (Honeycomb, error_tracker) is blind too — nothing
errors in the app. So detection must be **external and through the Cloudflare
hostname**, never the `*.fly.dev` origin.

## The permanent fix (already applied)

`_fly-ownership` **TXT records in Cloudflare DNS** let Fly do ownership-based
validation behind the proxy, so future renewals (~30 days before expiry) validate
automatically:

| Record name | Value |
|---|---|
| `_fly-ownership` | `app-wd1l3ge` |
| `_fly-ownership.www` | `app-wd1l3ge` |

**Do NOT delete these records.** Get exact values anytime with
`fly certs setup klasshero.com -a klass-hero-live`. Keep Cloudflare SSL mode on
**Full (strict)**.

## The monitors (UptimeRobot, free tier)

External vantage point, probing the **through-Cloudflare** path. Email alerts to the
founder inbox.

| Monitor | Type | URL | Catches |
|---|---|---|---|
| Prod apex uptime | HTTP(s), 5 min | `https://klasshero.com/health` | Any non-200 incl. **525** (origin-TLS / cert failure on the proxied leg) |
| Prod www uptime | HTTP(s), 5 min | `https://www.klasshero.com/health` | www-hostname cert/TLS failure. `www` returns **301 → apex** — the redirect is served *after* the www TLS handshake, so a www 525 still trips this. Leave UptimeRobot's default "follow redirects" **on** (it lands on the apex 200 = Up); do **not** hard-assert a literal 200 on this monitor or the healthy 301 will false-alert |
| Cert expiry | UptimeRobot SSL-expiry alert on the apex monitor | `klasshero.com` | Cert **<30/14/7 days** from expiry — leading indicator of a stuck renewal ~2 weeks early |

Two independent signals for one failure mode: the **SSL-expiry alert is the leading
indicator** (should always fire first if renewal is stuck); the **525 uptime alert
is the lagging safety net**. Alert channel: **email** (UptimeRobot signup email is
the default contact).

### Setup (one-time, in the UptimeRobot dashboard)

1. Create a free UptimeRobot account — signup email becomes the alert contact.
2. Add HTTP(s) monitor `https://klasshero.com/health`, 5-min interval.
3. Add HTTP(s) monitor `https://www.klasshero.com/health`, 5-min interval.
4. Enable the SSL-expiry notification on the apex monitor.
5. Send a test notification and confirm the email arrives.

## When an alert fires

Diagnose from the top — the first three steps need no Fly login:

1. `curl -I https://klasshero.com` → `HTTP 525`, `server: cloudflare` confirms the
   origin-leg TLS is broken.
2. `curl -I https://klass-hero-live.fly.dev/health` → `200` confirms the app + TLS
   stack are fine; the problem is the custom-domain cert only.
3. `openssl s_client -connect 66.241.124.133:443 -servername klasshero.com` →
   "no peer certificate available" confirms the origin serves no cert for that SNI.
4. `fly certs show klasshero.com -a klass-hero-live` → check `Expires`; the message
   *"Domain ownership verification is required… Add a _fly-ownership TXT record"*
   confirms the renewal-behind-proxy failure.

**Fix (~2 min, no redeploy):**

1. Verify the `_fly-ownership` / `_fly-ownership.www` TXT records still exist in
   Cloudflare DNS (see table above). Re-add if missing.
2. Re-trigger issuance:
   `fly certs check klasshero.com -a klass-hero-live` (and repeat for `www`).
3. Cert issues in 1–2 min; the 525 clears. Confirm with `curl -I https://klasshero.com`.

## Optional follow-up (separate ticket)

Add `_acme-challenge` CNAMEs in Cloudflare as a DNS-01 belt-and-suspenders fallback,
so validation has a second path independent of `_fly-ownership`. Not required — the
TXT records already make renewal reliable.

Escalation is **email-only** for now. If out-of-hours email proves too slow,
revisit SMS / Slack / PagerDuty routing.
