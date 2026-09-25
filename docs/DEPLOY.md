# Deploying Jobwalk

The API is one stateless Dart binary in front of Postgres. It serves the
app's API, the customer quote pages, the landing page, and Stripe
webhooks, and runs background jobs (emails, reminders, cleanup) from a
queue in Postgres. Photos go to S3-compatible storage.

```
 phones ──HTTPS──▶  api (1..n instances)  ──▶  Postgres
 customers ──────▶    ├─ Claude API (drafts)
 Stripe ─webhooks─▶   ├─ Resend (email)
                      ├─ S3 / R2 (photos)
                      └─ Stripe (billing, Connect)
```

Any number of instances can run side by side: rate limits live in
Postgres, jobs are claimed with `FOR UPDATE SKIP LOCKED`, migrations take
an advisory lock, and each business's quote writes are serialized so sync
cursors never skip a change.

## What you need

| Service | Used for | Suggested |
|---|---|---|
| Postgres 14+ | Everything | Neon, Supabase, Fly Postgres, RDS |
| Anthropic API key | Drafting quotes | Set a monthly spend limit |
| Resend | Sign-in codes, notifications | Verify your sending domain |
| S3-compatible bucket | Job photos | Cloudflare R2 (no egress fees) |
| Stripe (optional) | Subscriptions, deposits | Billing + Connect (Express) |
| A host for containers | The API | Fly.io (config in `server/fly.toml`), Render, Railway, ECS |

## Configuration

All settings are environment variables; `.env.example` lists them. The
server refuses to start in production with an unsafe or incomplete
configuration and prints every problem at once (exit code 78).

| Variable | Default | Notes |
|---|---|---|
| `JOBWALK_ENV` | `development` | `production` turns on the strict checks and HSTS. |
| `DATABASE_URL` | local Postgres | TLS is required unless the host is local or private (Compose service, `.internal`, `.flycast`). Add `?sslmode=` to override. |
| `DATABASE_POOL_SIZE` | `10` | Per instance. |
| `JOBWALK_PUBLIC_URL` | `http://localhost:PORT` | Origin of quote links and email links. HTTPS in production. |
| `JOBWALK_SECRET` | dev value | 32+ random characters. Keys sign-in code hashes and onboarding links. |
| `ANTHROPIC_API_KEY` | | Or `JOBWALK_FAKE_MODEL=true` for sample drafts (not in production). |
| `JOBWALK_MODEL`, `JOBWALK_EFFORT`, `JOBWALK_MAX_TOKENS`, `JOBWALK_FALLBACKS` | Opus 5.5, `high`, 32000, on | |
| `JOBWALK_MAX_CONCURRENT`, `JOBWALK_MAX_QUEUED` | 16, 64 | Drafts in flight per instance and the queue behind them; beyond that, 503 with Retry-After. |
| `JOBWALK_DRAFT_TIMEOUT_SECONDS` | 170 | |
| `EMAIL_PROVIDER` | `log` | `resend` in production (`log` prints sign-in codes). |
| `RESEND_API_KEY`, `EMAIL_FROM`, `EMAIL_REPLY_TO` | | |
| `STORAGE` | `file` | `s3` for more than one instance. `file` writes under `STORAGE_DIR`. |
| `S3_ENDPOINT`, `S3_BUCKET`, `S3_REGION`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY` | | Path-style requests; works with R2, MinIO, AWS. Photos are served by short-lived signed URLs. |
| `STRIPE_SECRET_KEY` | | Billing and deposits are off without it. |
| `STRIPE_WEBHOOK_SECRET`, `STRIPE_CONNECT_WEBHOOK_SECRET` | | Signing secrets of the two endpoints (see below). |
| `STRIPE_PRICE_PRO`, `STRIPE_PRICE_CREW` | | Recurring price ids. |
| `STRIPE_APPLICATION_FEE_BPS` | `100` | Jobwalk's cut of each deposit (1%). |
| `STRIPE_PROCESSING_FEE_BPS`, `STRIPE_PROCESSING_FEE_CENTS` | `290`, `30` | Card fees passed through to the contractor (the platform pays Stripe on destination charges). |
| `JOBWALK_TRIAL_DRAFTS` | `25` | Free AI drafts per business. Unusable drafts don't count. |
| `JOBWALK_MONTHLY_DRAFT_CAP` | `500` | Fair-use ceiling on paid plans (rolling 30 days). |
| `JOBWALK_SESSION_DAYS` | `90` | Sessions slide with use. |
| `JOBWALK_TRUSTED_PROXIES` | `1` | Load balancers in front of the app; decides which `X-Forwarded-For` entry is the client (recorded in approval audit trails). `0` to use the socket address. |
| `JOBWALK_CORS_ORIGINS` | `*` | For the web build of the app. |
| `JOBWALK_MIGRATE_ON_START` | `true` | Set `false` and run `/app/migrate` as a release step instead. |
| `JOBWALK_RUN_WORKER` | `true` | Set `false` on web-only instances if you run `/app/worker` separately. |
| `ADMIN_TOKEN` | | 24+ characters. Enables `/admin/*`. |
| `METRICS_TOKEN` | | Bearer token for `/metrics`. Without it, `/metrics` is off in production. |
| `JOBWALK_REVIEW_EMAIL`, `JOBWALK_REVIEW_CODE` | | An account that signs in with a fixed six-digit code, for app store review. |

## First deploy (Fly.io)

```sh
# From the repository root.
fly launch --no-deploy --copy-config --config server/fly.toml
fly secrets set --config server/fly.toml \
  DATABASE_URL=... JOBWALK_PUBLIC_URL=https://jobwalk.app \
  JOBWALK_SECRET="$(openssl rand -base64 48)" \
  ANTHROPIC_API_KEY=... EMAIL_PROVIDER=resend RESEND_API_KEY=... \
  EMAIL_FROM='Jobwalk <hello@jobwalk.app>' \
  S3_ENDPOINT=... S3_BUCKET=... S3_ACCESS_KEY_ID=... S3_SECRET_ACCESS_KEY=... \
  ADMIN_TOKEN="$(openssl rand -hex 24)" METRICS_TOKEN="$(openssl rand -hex 24)"
fly deploy --config server/fly.toml --dockerfile server/Dockerfile \
  --build-arg VERSION="$(git rev-parse --short HEAD)" .
```

`fly.toml` runs migrations as the release command, keeps two machines up,
checks `/readyz`, and gives in-flight drafts 200 seconds on shutdown.
Point your domain at the app and check:

```sh
curl https://jobwalk.app/healthz   # process is up; shows version and model
curl https://jobwalk.app/readyz    # database reachable, schema current
```

Elsewhere: build `server/Dockerfile` from the repository root. The image
contains `/app/server` (default command), `/app/migrate`, and
`/app/worker`. It listens on `$PORT` (8080), logs JSON lines to stdout,
and exits cleanly on SIGTERM after finishing in-flight requests.

## Stripe

1. **Products.** Create Pro and Crew products with monthly prices and set
   `STRIPE_PRICE_PRO` and `STRIPE_PRICE_CREW`. Turn on the customer portal
   (Settings → Billing → Customer portal) with plan switching and
   cancellation.
2. **Webhook endpoint** `https://jobwalk.app/webhooks/stripe` for your
   account, with these events, then set `STRIPE_WEBHOOK_SECRET`:
   `checkout.session.completed`, `checkout.session.async_payment_succeeded`,
   `customer.subscription.created`, `customer.subscription.updated`,
   `customer.subscription.deleted`.
3. **Connect.** Enable Connect with Express accounts, set your platform
   branding, and add a second endpoint (same URL) listening to events on
   **connected accounts** with `account.updated`; set
   `STRIPE_CONNECT_WEBHOOK_SECRET`.

Deposits are destination charges on the platform with
`on_behalf_of` the contractor, so the contractor is the merchant of record
and receives the deposit minus the application fee. The server fetches
subscriptions and accounts from Stripe on each webhook instead of trusting
event order, and ignores repeated events.

Test locally with the Stripe CLI:
`stripe listen --forward-to localhost:8080/webhooks/stripe`.

## Email

Verify your domain in Resend (SPF and DKIM), then set `EMAIL_FROM` to an
address on it. Sign-in codes expire in 10 minutes; retries stop after
three attempts. Contractors get an email when a customer first opens a
quote, approves, declines, or pays a deposit, and a nudge three days
after sending when there's no decision. Each person can turn these off.

## Operations

**Logs.** One JSON line per request (`event: request` with route, status,
milliseconds, request id) and per notable event. Personal data stays out
of logs: emails are masked and quote contents are never logged. Useful
events to alert on: `error`, `draft_failed`, `overloaded`, `job_failed`,
`stripe_error`, `not_ready`.

**Metrics.** `GET /metrics` with `Authorization: Bearer $METRICS_TOKEN`
returns Prometheus text: request counts and latency by route, drafts by
outcome, model spend, draft latency, drafts in flight and queued, and
background jobs by kind and outcome.

**Admin.** With `Authorization: Bearer $ADMIN_TOKEN`:

- `GET /admin/stats`: businesses, plans, active users, quotes sent and
  approved (30 days), draft volume and cost, deposits, job health, waitlist.
- `GET /admin/waitlist.csv`
- `GET /admin/jobs` (failed) and `GET /admin/jobs?state=pending`
- `POST /admin/jobs/<id>/retry`

**Backups.** Use your provider's point-in-time recovery for Postgres and
object versioning (or a replication rule) on the photo bucket. The
database holds everything else.

**Migrations.** Numbered, applied in order under an advisory lock, each in
its own transaction (`server/lib/src/db/migrations.dart`). Never edit a
shipped migration; add a new one. Write them to be compatible with the
previous release, since instances update one at a time.

**Housekeeping.** An hourly job deletes expired sessions and codes, old
finished jobs (failed ones are kept 60 days), stale rate-limit buckets,
draft responses older than 7 days (they only serve retries), and old
Stripe event ids.

## Security notes

- Session tokens (`jws_...`, 256 bits) and sign-in codes are stored only as
  hashes; codes are keyed with `JOBWALK_SECRET`, allow five guesses, and
  are rate limited per address and per IP.
- Every query is scoped to the signed-in person's business; ids from
  phones are unique only within a business.
- Customer pages send a strict Content-Security-Policy, `noindex`, and no
  referrer. Every value a contractor typed is escaped.
- Approvals record who signed, the option and total, the quote revision
  and a hash of its content, the IP address, and the browser. The
  contractor can export this with their data.
- `DELETE /v1/account` removes the business, its people, quotes, links,
  and photos, and cancels the subscription.
