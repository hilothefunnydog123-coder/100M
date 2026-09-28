# Deploying Jobwalk

The API is one stateless Dart binary in front of Postgres. It serves the
app's API, the customer quote pages, the landing page, and Stripe
webhooks, and runs background jobs (emails, reminders, cleanup) from a
queue in Postgres. Photos go to S3-compatible storage. One Supabase
project provides both (see [Supabase](#supabase-database-and-photos)).

```
 phones ──HTTPS──▶  api (1..n instances)  ──▶  Postgres (Supabase)
 customers ──────▶    ├─ AI provider (drafts)
 Stripe ─webhooks─▶   ├─ Resend (email)
                      ├─ Supabase Storage (photos)
                      └─ Stripe (billing, Connect)
```

Any number of instances can run side by side: rate limits live in
Postgres, jobs are claimed with `FOR UPDATE SKIP LOCKED`, migrations take
an advisory lock, and each business's quote writes are serialized so sync
cursors never skip a change.

## What you need

| Service | Used for | Suggested |
|---|---|---|
| Postgres 14+ | Everything | Supabase; Neon or RDS work too |
| An AI provider key | Drafting quotes | Anthropic, or Gemini from a Google Cloud project with billing on; set a monthly spend limit |
| Resend | Sign-in codes, notifications | Verify your sending domain |
| S3-compatible bucket | Job photos | Supabase Storage; Cloudflare R2 or AWS S3 work too |
| Stripe (optional) | Subscriptions, deposits | Billing + Connect (Express) |
| A host for containers | The API | Fly.io (config in `server/fly.toml`), Render, Railway, ECS |

## Configuration

All settings are environment variables; `.env.example` lists them. The
server refuses to start in production with an unsafe or incomplete
configuration and prints every problem at once (exit code 78).

| Variable | Default | Notes |
|---|---|---|
| `JOBWALK_ENV` | `development` | `production` turns on the strict checks and HSTS. |
| `DATABASE_URL` | local Postgres | TLS is required unless the host is local or private (Compose service, `.internal`, `.flycast`). Add `?sslmode=` to override. With Supabase, the session pooler string (port 5432); the server refuses the transaction pooler (6543). |
| `DATABASE_POOL_SIZE` | `10` | Per instance. Supabase's session pooler allows 15 connections in all unless you raise its Pool Size, so `fly.toml` sets 5 for its two machines. |
| `JOBWALK_PUBLIC_URL` | `http://localhost:PORT` | Origin of quote links and email links. HTTPS in production. |
| `JOBWALK_SECRET` | dev value | 32+ random characters. Keys sign-in code hashes and onboarding links. |
| `JOBWALK_AI_PROVIDER` | `claude` | `gemini` or `groq` draft with another provider (see below). |
| `ANTHROPIC_API_KEY` | | Or `JOBWALK_FAKE_MODEL=true` for sample drafts (not in production). |
| `JOBWALK_MODEL`, `JOBWALK_EFFORT`, `JOBWALK_MAX_TOKENS`, `JOBWALK_FALLBACKS` | Opus 5.5, `high`, 32000, on | With Gemini: `gemini-3.8-flash`, `high` (`low`, `medium`, or `high`), 32000. With Groq: `qwen/qwen3.8-27b`, `medium` (same choices), 16000. Fallbacks are Claude's. |
| `JOBWALK_BACKUP_MODELS` | `claude-sonnet-5` with Claude, `gemini-3.7-flash` with Gemini, none with Groq | Models tried in order when the main one is busy or out of quota (see below). A comma-separated list; a name that doesn't start with `claude-` or `gemini-` needs its provider, as in `groq:qwen/qwen3.8-27b`. `none` turns backups off. |
| `GEMINI_API_KEY`, `GEMINI_BASE_URL` | | Required with `JOBWALK_AI_PROVIDER=gemini`. `GOOGLE_API_KEY` works too. |
| `GROQ_API_KEY`, `GROQ_BASE_URL` | | Required with `JOBWALK_AI_PROVIDER=groq`. |
| `JOBWALK_GROQ_FREE_TIER` | off | One photo per draft and a shorter answer, to fit Groq's free tier. |
| `JOBWALK_FREE_TIER` | off | Free AI plans for a beta (see below). Includes `JOBWALK_GROQ_FREE_TIER`. |
| `JOBWALK_MAX_CONCURRENT`, `JOBWALK_MAX_QUEUED` | 16, 64 | Drafts in flight per instance and the queue behind them; beyond that, 503 with Retry-After. |
| `JOBWALK_DRAFT_TIMEOUT_SECONDS` | 170 | |
| `EMAIL_PROVIDER` | `log` | `resend` in production (`log` prints sign-in codes). |
| `RESEND_API_KEY`, `EMAIL_FROM`, `EMAIL_REPLY_TO` | | |
| `STORAGE` | `file` | `s3` for more than one instance. `file` writes under `STORAGE_DIR`. |
| `S3_ENDPOINT`, `S3_BUCKET`, `S3_REGION`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY` | | Path-style requests; works with Supabase Storage, R2, MinIO, AWS. With Supabase, the endpoint ends in `/storage/v1/s3` and the region is the project's. Photos are served by short-lived signed URLs. |
| `STRIPE_SECRET_KEY` | | Billing and deposits are off without it. |
| `STRIPE_WEBHOOK_SECRET`, `STRIPE_CONNECT_WEBHOOK_SECRET` | | Signing secrets of the two endpoints (see below). |
| `STRIPE_PRICE_PRO`, `STRIPE_PRICE_CREW` | | Recurring price ids. |
| `STRIPE_APPLICATION_FEE_BPS` | `100` | Jobwalk's cut of each deposit (1%). |
| `STRIPE_PROCESSING_FEE_BPS`, `STRIPE_PROCESSING_FEE_CENTS` | `290`, `30` | Card fees passed through to the contractor (the platform pays Stripe on destination charges). |
| `JOBWALK_TRIAL_DRAFTS` | `25` | Free AI drafts per business. Unusable drafts don't count. |
| `JOBWALK_MONTHLY_DRAFT_CAP` | `500` | Fair-use ceiling on paid plans (rolling 30 days). |
| `JOBWALK_PRO_PRICE`, `JOBWALK_CREW_PRICE` | `35`, `79` | Monthly prices in whole dollars, shown on the landing page and in the app. Stripe charges its own prices, so keep them the same. |
| `JOBWALK_SESSION_DAYS` | `90` | Sessions slide with use. |
| `JOBWALK_TRUSTED_PROXIES` | `1` | Load balancers in front of the app; decides which `X-Forwarded-For` entry is the client (recorded in approval audit trails). `0` to use the socket address. |
| `JOBWALK_CORS_ORIGINS` | `*` | For the web build of the app. |
| `JOBWALK_MIGRATE_ON_START` | `true` | Set `false` and run `/app/migrate` as a release step instead. |
| `JOBWALK_RUN_WORKER` | `true` | Set `false` on web-only instances if you run `/app/worker` separately. |
| `ADMIN_TOKEN` | | 24+ characters. Enables `/admin/*`. |
| `METRICS_TOKEN` | | Bearer token for `/metrics`. Without it, `/metrics` is off in production. |
| `JOBWALK_REVIEW_EMAIL`, `JOBWALK_REVIEW_CODE` | | An account that signs in with a fixed six-digit code, for app store review. |
| `JOBWALK_LEGAL_NAME`, `JOBWALK_LEGAL_ADDRESS`, `JOBWALK_GOVERNING_LAW` | `Jobwalk`, none, none | Who runs the service, for the privacy policy and terms at `/privacy` and `/terms`: a sole proprietor's own legal name, or a company's registered name. The address is optional (a mailbox address works). The governing law is a US state, e.g. `Texas`. |
| `JOBWALK_CONTACT_EMAIL` | `EMAIL_REPLY_TO`, else the `EMAIL_FROM` address | Where the legal pages send privacy and data requests. |

### AI provider

Claude is the default. Two other providers get the same instructions and the
same checks on every answer, at a fraction of the cost. Run `bin/eval.dart` on
real jobs with each provider before switching (see
[eval/README.md](../eval/README.md)); the pricing guidance was written and
checked against Claude.

`JOBWALK_AI_PROVIDER=gemini` drafts with Gemini 3.8 Flash. Gemini enforces the
same answer schema Claude does and takes every photo. Its free tier allows
about 20 requests a day per Google Cloud project (Flash-Lite models allow
more), and on the free tier Google may use what you send to improve its
products, with people reviewing some of it. Use a key from a project with
billing turned on before customers' photos go through it.

**Backup models.** When the main model's provider turns a draft away
(busy, a timeout, rate limited, out of quota, or refusing the key), the
server sends the same draft to the next model in `JOBWALK_BACKUP_MODELS`,
so a contractor gets a quote instead of "try again". An answer the model
did give (declining the photos, or output that didn't parse) isn't sent on.
The default backup is an older model from the same provider, so the key,
billing, and data terms stay the same. A backup from another provider needs
that provider's key, and the privacy policy then names that company too.
Logs show each switch (`event: draft_backup`) and `/metrics` counts drafts
by the model that wrote them (`jobwalk_draft_models_total`).

**Free AI plans (for a beta).** With `JOBWALK_AI_PROVIDER=gemini` and
`JOBWALK_FREE_TIER=true`, drafts run on free plans with no card on file:

- Gemini 3.8 Flash first, then Gemini 3.7 Flash and 3.5 Flash-Lite, each
  with its own daily allowance (about 20, 20, and 500 requests).
- With a free Groq key (`GROQ_API_KEY`, no card), Groq's Qwen model last.
  It runs on another company's servers, so it answers when Google's are all
  busy, which happens often. Its free tier sees one photo per draft and
  allows roughly 25 to 30 drafts a day.
- When every model is busy, the app offers to write the quote by hand.

The privacy policy then says Google may use what its free tier is sent, and
that people at Google may review it, so keep people and anything private out
of job photos. Move to paid plans before charging customers.

`JOBWALK_AI_PROVIDER=groq` drafts with Qwen 3.8 27B on Groq. Groq's limits
shape what gets sent:

- At most 3 photos per request, each counted as 2,048 tokens. Later photos
  are left out, and the model is told so.
- Groq counts the prompt plus `max_completion_tokens` against the account's
  tokens-per-minute limit before it runs, and refuses a larger request
  outright. On the free tier that limit is 8,000, and three photos plus the
  instructions are more than that before the model writes a word.
  `JOBWALK_GROQ_FREE_TIER=true` sends one photo with light reasoning and
  shrinks the answer budget to fit (about 3,200 tokens). The free tier also
  caps each account at 200,000 tokens a day, roughly 25 to 30 drafts in all,
  so it suits trying Groq, not running a business on it.

## Supabase (database and photos)

One Supabase project holds the database and the job photos. Jobwalk uses
it as plain Postgres and plain S3 storage, not through Supabase's Auth or
its Data API, so there's no Supabase code in the app.

1. **Create the project** at [supabase.com](https://supabase.com), in the
   region nearest the server: East US (North Virginia) is next to Fly's
   `iad`, where `fly.toml` runs it. Use a long database password of
   letters and numbers; `@`, `#`, `/`, or `?` would have to be
   URL-encoded in the connection string. Leave **Automatically expose new
   tables** unchecked (the default for new projects).
2. **Database.** Click **Connect**, choose **Session pooler**, copy the
   URI, and put your password where it says `[YOUR-PASSWORD]`. That's
   `DATABASE_URL`:

   ```
   postgresql://postgres.<ref>:<password>@aws-0-us-east-1.pooler.supabase.com:5432/postgres
   ```

   The session pooler works over IPv4 from any host. The direct
   connection (`db.<ref>.supabase.co`) is IPv6 only, and the transaction
   pooler (port 6543) would break the lock migrations hold, so the server
   refuses it. The session pooler allows 15 connections in all unless you
   raise **Pool Size** in Database settings; `fly.toml` gives each of its
   two machines 5.
3. **Photos.** In **Storage**, create a private bucket named `jobwalk`.
   In Storage's **S3** settings, turn the S3 connection on if it's off,
   copy the **Endpoint** and **Region**, and create an access key:

   ```
   STORAGE=s3
   S3_ENDPOINT=https://<ref>.storage.supabase.co/storage/v1/s3
   S3_REGION=us-east-1
   S3_BUCKET=jobwalk
   S3_ACCESS_KEY_ID=...
   S3_SECRET_ACCESS_KEY=...
   ```

   The access key can read and write every bucket, so it goes to the
   server only. Phones get photos through signed links that last 10
   minutes.
4. **The first deploy creates the tables** (the release command runs
   `/app/migrate`). Each has row level security with no policies, so the
   Data API can't read them even if it's turned on; the server owns the
   tables and isn't affected. Browse the data in the Table Editor, but
   change it through the app: hand edits skip the revisions that keep
   phones in sync.
5. **Plan.** Free is enough to try it: 500 MB database, 1 GB of photos,
   5 GB of downloads a month, no backups, and the project pauses after a
   week without use. Move to Pro ($25 a month: 8 GB database, 100 GB of
   photos, 250 GB of downloads, daily backups kept 7 days, no pausing)
   before the first real customer.

## First deploy (Fly.io)

```sh
# From the repository root.
fly launch --no-deploy --copy-config --config server/fly.toml
fly secrets set --config server/fly.toml \
  DATABASE_URL='postgresql://postgres.<ref>:<password>@aws-0-us-east-1.pooler.supabase.com:5432/postgres' \
  JOBWALK_PUBLIC_URL=https://jobwalk.app \
  JOBWALK_SECRET="$(openssl rand -base64 48)" \
  ANTHROPIC_API_KEY=... EMAIL_PROVIDER=resend RESEND_API_KEY=... \
  EMAIL_FROM='Jobwalk <hello@jobwalk.app>' \
  S3_ENDPOINT=https://<ref>.storage.supabase.co/storage/v1/s3 S3_REGION=us-east-1 \
  S3_BUCKET=jobwalk S3_ACCESS_KEY_ID=... S3_SECRET_ACCESS_KEY=... \
  ADMIN_TOKEN="$(openssl rand -hex 24)" METRICS_TOKEN="$(openssl rand -hex 24)"
fly deploy --config server/fly.toml --dockerfile server/Dockerfile \
  --build-arg VERSION="$(git rev-parse --short HEAD)" .
```

`fly.toml` runs migrations as the release command, keeps two machines up,
checks `/readyz`, and gives in-flight drafts 200 seconds on shutdown. It
sets `STORAGE=s3` and `DATABASE_POOL_SIZE=5`; everything secret goes in
`fly secrets`, never in the file.
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

1. **Products.** Create Pro and Crew products with monthly prices ($35 and
   $79 unless you set `JOBWALK_PRO_PRICE` and `JOBWALK_CREW_PRICE`
   differently) and set `STRIPE_PRICE_PRO` and `STRIPE_PRICE_CREW`. Turn on the customer portal
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

**Backups.** Supabase Pro backs up the database daily and keeps 7 days;
add point-in-time recovery once losing a day of quotes would hurt. Its
storage keeps no old versions of photos, so for a second copy, sync the
bucket elsewhere now and then with any S3 tool and the same keys. The
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
