# How Jobwalk keeps quotes accurate

A quote is only useful if the contractor would send it with small edits.
Jobwalk is built around one rule: **the AI estimates the work; the
contractor's own rates set the price.**

## The pipeline

1. **Photos.** The app resizes each photo to at most 2048 px on the long
   edge and re-encodes it as JPEG (`packages/core/lib/src/photo_pipeline.dart`),
   the same pipeline the accuracy harness uses. Very dark or tiny photos are
   flagged before sending.
2. **Draft.** The server sends the photos, the contractor's rates, their
   price list, and their note to Claude Opus 5.5 with adaptive thinking at
   high effort and a strict JSON schema (`server/lib/src/draft_schema.dart`).
   The estimator prompt (`server/lib/src/prompt.dart`) covers:
   - Measuring from standard sizes: 80 in doors, 8 ft fence sections,
     garage doors, bricks, outlets, and ceiling height judged from the gap
     above the door casing.
   - Production rates per trade (sq ft per hour for walls, hours per post,
     and so on) and material coverage.
   - Scope: prep, cleanup, and disposal are included; hidden problems are
     flagged instead of priced.
3. **Numbers, not prices.** For each line the model returns quantity, unit,
   labor hours, material cost (what the contractor pays), and pass-through
   costs. It never writes a price or a total. The schema orders fields so it
   explains each line (`basis`) before its numbers.
4. **Pricing.** `packages/core/lib/src/pricing.dart` prices each line in
   integer cents: hours times the labor rate, plus materials with markup,
   plus pass-through costs; or quantity times the contractor's own price
   when the model matched a price-list entry in the same unit. Then the
   minimum job, discount, tax, and deposit. Lines round to prices people
   write ($2,480, not $2,477.63) unless the contractor turns that off.
5. **Guardrails.** Parsing clamps every number, drops unknown units and
   options, and collapses inconsistent options so a line is never counted
   twice. Truncated or malformed output is retried once; photos that can't
   support a quote come back as a retake request instead of a guess.

## What the contractor sees

- **Check before sending:** up to six assumptions, most important first,
  marked by price impact.
- **How Jobwalk got these numbers:** each measurement, how it was taken,
  and its confidence.
- **Only you see this:** total labor hours, material cost, crew-days, and
  how far their edits moved the price from the AI draft.

## It learns your prices

When a contractor types a price over an AI line and sends the quote, that
becomes a learned price-list entry (per unit, for example $1.38 per sq ft for
"Paint walls, 2 coats"). The next draft sees it in the prompt and prices
matching lines with it (`packages/core/lib/src/price_memory.dart`). Entries
they add by hand always win over learned ones.

## Measuring accuracy

Two numbers, tracked from day one of the beta:

1. **Change from draft.** Every quote stores the AI's draft total per
   option. The share of quotes sent within 10% of the draft is the
   in-product accuracy metric.
2. **Error against real jobs.** The harness (`server/bin/eval.dart`,
   [eval/README.md](../eval/README.md)) drafts past jobs from their photos
   and compares the total with what was actually charged: median absolute
   error, bias, and the share within 10% and 20%, overall and by trade.

Starting targets for interior painting, to be adjusted once real data
arrives: median absolute error of 12% or less, and 75% of jobs within 20%.
No real-job eval has been run yet; the development environment had no API
key. Collecting 30+ past jobs per trade is the first task of the beta, and
prompt or model changes should ship only when they don't make these numbers
worse.
