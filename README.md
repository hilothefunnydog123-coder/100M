# Jobwalk

**Quote the job before you leave the driveway.**

Jobwalk is a quoting app for small home-service crews: painters, fence
builders, pressure washers, landscapers, and anyone who quotes from a
walkthrough. Snap a few photos of the job, and Jobwalk drafts an itemized
quote priced with your own rates. Text the link to the customer; they pick
an option, sign, and pay the deposit from their phone.

> Status: work in progress. The core, server, and customer quote page are
> built and tested; the Flutter app's screens are written and being
> verified end to end.

## How the quotes stay accurate

The AI never writes a price. Claude Opus 5.5 looks at the photos and
estimates what an experienced estimator would: measurements (with how it
measured them), scope, labor hours, and material costs. Deterministic code
in `packages/core` then prices every line with the contractor's labor rate,
markup, and price list, in integer cents. Prices the contractor types over
a draft are learned for next time, and the assumptions that move the price
are flagged for them to confirm before sending.

## Repository

| Path | What |
|---|---|
| `packages/core` | Quote model, pricing math, AI draft parsing, customer-facing quote (pure Dart) |
| `server` | API: drafts quotes with Claude, hosts quote links and the approval page, landing page and waitlist |
| `app` | Flutter app (iOS, Android, web) |
| `eval` | Accuracy harness docs: score drafts against real invoices |

## Run it

```sh
# App in demo mode (sample jobs, no server needed)
cd app && flutter run -d chrome

# Server with sample drafts (no API key)
cd server && JOBWALK_FAKE_MODEL=true dart run bin/server.dart

# Server with Claude
cd server && ANTHROPIC_API_KEY=... JOBWALK_PUBLIC_URL=https://your.domain dart run bin/server.dart

# App against a server
cd app && flutter run --dart-define=API_BASE_URL=http://localhost:8080
```

The server's landing page is at `/`, and a sample customer quote at
`/sample`.
