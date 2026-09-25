# Jobwalk API

Base URL: your `JOBWALK_PUBLIC_URL`. JSON in and out. Everything under
`/v1` except sign-in needs `Authorization: Bearer <token>`.

## Conventions

**Errors** always look like this, with a stable `code` to branch on and a
`message` written for the person using the app:

```json
{"error": {"code": "conflict", "message": "This quote was changed on another device.", "request_id": "k2x..."}}
```

Some errors add fields next to `error` (a conflict includes `current`).
429 and 503 responses include `Retry-After`. Send `X-Request-Id` to tag a
request; it's echoed back and appears in the server logs.

| Status | Codes |
|---|---|
| 400 | `invalid_json`, `invalid_email`, `invalid_code`, `invalid_request`, `invalid_quote`, `invalid_profile`, `profile_incomplete`, `confirmation_required`, `invalid_plan`, `invalid_idempotency_key` |
| 401 | `unauthorized`: sign in again |
| 402 | `upgrade_required`: trial drafts used up, or the team is at the plan's size |
| 403 | `forbidden`: owners only |
| 404 | `not_found` |
| 409 | `conflict`, `deleted`, `already_approved`, `email_taken`, `in_progress`, `already_subscribed`, `no_subscription`, `payments_not_ready`, `deposit_unavailable` |
| 413 / 415 | `too_large`, `unsupported_type` |
| 422 | `refused`: the photos can't be quoted |
| 429 | `rate_limited`, `usage_limit` |
| 502 / 503 / 504 | `draft_failed`, `payments_error`; `busy`, `billing_unavailable`, `payments_unavailable`; `timeout` |

## Sign-in

Passwordless: request a code by email, then trade it for a session token.
The first sign-in creates a business with the person as its owner.

`POST /v1/auth/code` `{"email": "dana@brightline.co"}` → `{"ok": true}`
(also when no account exists yet).

`POST /v1/auth/verify` `{"email": "...", "code": "042913", "device": "iPhone 15"}`
→ `{"token": "jws_...", "created": true, "user": {...}, "business": {...}}`

Codes expire in 10 minutes and allow five guesses. Tokens last 90 days
from last use.

`POST /v1/auth/sign-out` `{"everywhere": false}` → `{"ok": true}`

## Account

`GET /v1/me`

```json
{
  "user": {"id": "u_...", "email": "dana@brightline.co", "name": "Dana", "role": "owner", "email_notifications": true},
  "business": {
    "id": "b_...",
    "profile": {"name": "Brightline Painting", "trades": ["painting"], "phone": "...", "email": "...", "zip": "78704", "license": "", "payment_link": "", "terms": "..."},
    "rates": {"labor_rate_cents": 6500, "material_markup_pct": 20, "minimum_job_cents": 0, "tax_rate_pct": 0, "deposit_pct": 25, "valid_days": 30, "round_prices": true, "price_list": []},
    "setup_complete": true,
    "next_quote_number": 1043,
    "plan": {"id": "trial", "status": "trialing", "paid": false, "trial_drafts_included": 25, "trial_drafts_used": 3, "trial_drafts_left": 22, "max_users": 3},
    "payments": {"connected": false, "ready": false},
    "created_at": "2026-09-25T15:00:00.000Z"
  }
}
```

`PUT /v1/me` `{"name": "Dana Ortiz", "email_notifications": false}` → me

`PUT /v1/business` `{"profile": {...}, "rates": {...}}` (either or both;
owners only) → me

`POST /v1/business/numbers` `{"count": 10, "at_least": 1042}` →
`{"first": 1042, "count": 10}`. Reserves quote numbers so phones can
number quotes offline without clashing. `at_least` moves the counter past
numbers a phone used before signing in.

`GET /v1/team` → `{"members": [{"id", "email", "name", "role", "you", "created_at", "last_seen_at"}]}`

`POST /v1/team` `{"email": "lee@...", "name": "Lee"}` (owners) → 201 with
members. The new member gets an email and signs in with their own address.

`DELETE /v1/team/<user_id>` (owners) → members. Ends their sessions.

`GET /v1/account/export` (owners) → everything stored about the business,
including approval audit trails.

`DELETE /v1/account` `{"confirm": "DELETE"}` → `{"ok": true}`. An owner
deletes the business and everything in it and cancels the subscription;
a member deletes only themself.

## Quotes

Quotes are made on the phone (with the phone's ids) and synced. The body
of a quote is the shared `Quote` JSON from `packages/core`. The server
owns two fields and fills them in on every read: `share` (the customer
link) and `response` (what the customer did), and derives `status` from
them.

A synced quote:

```json
{"id": "q_...", "version": 3, "deleted": false, "quote": {...}, "deposit": {"status": "paid", "paid_cents": 31100, "paid_at": "..."}}
```

`GET /v1/quotes?since=<cursor>&limit=100` → `{"items": [...], "cursor": 5120, "more": false}`.
Changes after `since`, oldest first; keep the cursor and pass it next
time. Deleted quotes arrive as `{"id", "version", "deleted": true}`.
Customer activity (views, approvals, deposits) moves a quote to the end,
so polling this endpoint is how phones learn about it.

`GET /v1/quotes/<id>` → a synced quote

`PUT /v1/quotes/<id>` `{"quote": {...}, "base_version": 3}` → the synced
quote with its new version. `base_version` is the version the phone last
saw (0 for new quotes). If someone else changed it since, the answer is
409 `conflict` with `current`; a retry of a write that already landed
succeeds.

`DELETE /v1/quotes/<id>` → tombstone. The customer link stops working
and the quote's photos are deleted.

`POST /v1/quotes/<id>/publish` → the synced quote plus `"changed": true|false`.
Builds the customer page from the stored quote and the business profile.
The first publish creates the link; publishing after edits makes a new
revision at the same link and clears an earlier decline. Publishing an
unchanged quote changes nothing (unless it expired, which re-issues it).
Approved quotes can't be republished: duplicate them.

`GET /v1/activity?before=<id>&limit=50` → `{"events": [{"id", "kind", "quote_id", "quote_number", "customer", "at", "data"}], "next": 812}`.
Kinds: `sent`, `revised`, `viewed`, `approved`, `declined`,
`deposit_paid`, `deposit_duplicate`, `follow_up_sent`.

## Photos

`PUT /v1/photos/<id>` with the JPEG or PNG bytes as the body (up to 10 MB)
→ 201 `{"id", "bytes", "content_type"}`. Ids come from the phone
(`<quote id>_<n>`), so uploads can be retried.

`GET /v1/photos/<id>` → the image, or a 302 to a short-lived signed URL.

## Drafts

`POST /v1/drafts` with a `DraftRequest` (profile, rates, note, and up to 8
base64 photos) → `{"draft": {...}, "model": "claude-opus-5-5", "demo": false, "prompt_version": "..."}`.
Takes up to about three minutes. Send `Idempotency-Key: <random>`: a retry
with the same key returns the first draft (`"replayed": true`) without a
second charge, or 409 `in_progress` while it's still running.

`GET /v1/drafts/<key>` → `{"state": "running"}`, `{"state": "failed"}`, or
`{"state": "done", "draft": {...}, ...}`. For a phone whose request was cut
off (lost signal, or a load balancer that closes quiet connections): the
draft keeps going on the server, so poll this instead of starting over.
The app does this on its own.

Trial businesses get 25 usable drafts (photos that can't be quoted don't
count), then 402 `upgrade_required`. Paid plans have a fair-use ceiling
(429 `usage_limit`).

## Money

`POST /v1/billing/checkout` `{"plan": "pro" | "crew"}` (owners) → `{"url"}`.
Open it in a browser; the plan turns on when Stripe confirms.

`POST /v1/billing/portal` (owners) → `{"url"}` to change plan, card, or cancel.

`GET /v1/payments` →
`{"enabled": true, "connected": true, "ready": true, "fee": {"platform_bps": 100, "processing_bps": 290, "processing_cents": 30, "description": "3.9% + 30¢ per deposit"}}`

`POST /v1/payments/connect` (owners) → `{"url"}` to Stripe's onboarding.
When the account is ready, customers see "Pay the deposit by card" after
approving.

`POST /v1/payments/dashboard` (owners) → `{"url"}` to the Stripe Express
dashboard (payouts, refunds).

## Customer pages

Server-rendered HTML, no JavaScript:

- `GET /q/<public_id>`: the quote. Counts a view unless it's a preview
  (`?preview=1`), a link-preview bot, or the same visitor again within 10
  minutes.
- `POST /q/<public_id>/approve` (form: `option`, `name`, `agree=yes`)
- `POST /q/<public_id>/decline` (form: `reason`)
- `POST /q/<public_id>/deposit`: redirects to Stripe Checkout.

## Operations

`GET /healthz`, `GET /readyz`, `GET /metrics`, `/admin/*`: see
[DEPLOY.md](DEPLOY.md).
