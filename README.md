# Jobwalk

**Quote the job before you leave the driveway.**

Jobwalk is a quoting app for small home-service crews: painters, fence
builders, pressure washers, landscapers, and anyone who prices work from a
walkthrough.

1. **Walk the job.** Snap 3 to 8 photos and say what the photos don't show
   ("two coats, ceilings too").
2. **Check the draft.** About a minute later there's an itemized quote,
   measured from the photos and priced with *your* labor rate, markup, and
   price list, with good/better/best options and a short list of
   assumptions to confirm.
3. **Text the link.** The customer opens a clean quote page, picks an
   option, signs, and pays the deposit with your payment link. You see when
   they open it and when they approve.

## How the quotes stay accurate

The AI never writes a price. Claude Opus 5.5 does what an estimator does on
a walkthrough: measures from things of known size in the photos (doors,
fence sections, garage doors), works out scope, labor hours, and material
costs, and says how it got each number. Deterministic code then prices
every line with the contractor's own rates, in integer cents. Prices the
contractor types over a draft are learned for the next job, and the
assumptions that move the price are flagged before anything is sent.
Details: [docs/ACCURACY.md](docs/ACCURACY.md).

## What's here

| Path | What |
|---|---|
| `packages/core` | Quote model, pricing math, AI draft parsing, the customer-facing quote, price memory. Pure Dart, shared by app and server. |
| `server` | The backend: accounts with emailed sign-in codes, teams, quote sync, AI drafting with Claude (metered, idempotent), customer quote pages with an e-signature audit trail, Stripe subscriptions and Connect deposits, email notifications and reminders from a Postgres job queue, metrics, admin. |
| `app` | Flutter app for iOS, Android, and web. |
| `eval` | How to score drafts against real invoices. |
| `docs` | [Business plan](docs/BUSINESS.md), [accuracy](docs/ACCURACY.md), [API](docs/API.md), [deploying](docs/DEPLOY.md), [launch checklist](docs/LAUNCH.md). |

## Try it

The app runs without a server in demo mode: drafts come from three sample
jobs (living room repaint, backyard fence, driveway wash), and you can play
the customer and approve your own quote.

```sh
cd app
flutter run -d chrome        # or an iOS simulator / Android emulator
```

The backend (Postgres and the API with sample drafts, no API key needed):

```sh
docker compose up --build        # http://localhost:8080
```

Sign-in codes are printed in the API's log (`EMAIL_PROVIDER=log`). The
landing page is at `/` and a sample customer quote at `/sample`. For real drafts, set `ANTHROPIC_API_KEY` and drop
`JOBWALK_FAKE_MODEL`. Deploying: [docs/DEPLOY.md](docs/DEPLOY.md).

## Development

Each package runs the same checks as CI:

```sh
cd packages/core && dart test
cd server && dart test          # needs Postgres (below)
cd app && flutter test
```

Server tests create a throwaway database per test file on
`TEST_DATABASE_URL` (default `postgres://postgres:postgres@localhost:5432/postgres`,
e.g. `docker compose up db`). Without a server they're skipped, unless
`REQUIRE_DB=1` as in CI. Run the API outside Docker with
`cd server && JOBWALK_FAKE_MODEL=true dart run bin/server.dart`.

`dart format`, `dart analyze --fatal-infos` (`flutter analyze` in `app`),
a web build, and a Docker build that boots the image against Postgres
also run in CI.
