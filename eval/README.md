# Accuracy harness

Scores AI drafts against what contractors actually charged, so prompt and
model changes are measured instead of guessed.

## Manifest

One JSON object per line (`//` lines are comments). Photo paths are relative
to the manifest.

```json
{"id": "paint-0142", "trade": "painting", "photos": ["paint-0142/1.jpg", "paint-0142/2.jpg"], "note": "two coats, ceilings too", "zip": "78704", "actual_total": 2480.00, "option": "full room"}
```

- `actual_total`: what the job was quoted or invoiced at, in dollars. Leave it
  out to only compare drafts: the case is drafted and saved, not scored.
- `option`: which option that price matches (matched against option names);
  omit to compare with the recommended option.
- `rates`: optional contractor rates (the same JSON the app stores); defaults
  to the trade's defaults.

## Run

```sh
cd server
ANTHROPIC_API_KEY=... dart run bin/eval.dart --manifest ../eval/jobs.jsonl --out ../eval/out
dart run bin/eval.dart --manifest ../eval/jobs.jsonl --fake   # plumbing check, no API calls
```

Outputs `results.jsonl`, `summary.json`, and `summary.md`: median absolute
error of the total, bias, share within 10% and 20%, cost per draft, and
latency, overall and by trade. Every draft is saved in `drafts/<id>.json`
for reading side by side. `--max-cost` stops starting new cases once the run
has spent that many dollars.

## Compare providers

`--provider gemini` drafts with Gemini 3.8 Flash (`GEMINI_API_KEY`) and
`--provider groq` with Qwen 3.8 27B on Groq (`GROQ_API_KEY`), both with the
same instructions. Run the same manifest once per provider and compare:

```sh
GEMINI_API_KEY=... dart run bin/eval.dart --manifest ../eval/jobs.jsonl --provider gemini --out ../eval/out-gemini
GROQ_API_KEY=... dart run bin/eval.dart --manifest ../eval/jobs.jsonl --provider groq --out ../eval/out-groq
```

Gemini's free tier allows about 20 requests a day for its Flash models; when
that runs out, the remaining cases fail with a message saying so, and the
quota resets at midnight Pacific time. `--model gemini-3.5-flash-lite` has a
larger free allowance and a weaker model. On the free tier Google may use
what you send to improve its products, so keep customers' photos for a key
with billing turned on.

On Groq's free tier add `--free-tier`: its 8,000-token limit per request
leaves room for one photo and a short answer, so drafts see less of each job
than they would in production (see docs/DEPLOY.md). Costs are reported at
Groq's paid prices even when the free tier charges nothing. Groq runs one
draft at a time by default and waits out per-minute rate limits.

`samples.jsonl` holds the app's three sample jobs. Their photos are rendered
scenes and they have no actual prices, so they only show whether a provider
returns complete, sensible drafts. Only real jobs with what was actually
charged can say which provider prices jobs better.

```sh
GEMINI_API_KEY=... dart run bin/eval.dart --manifest ../eval/samples.jsonl --provider gemini --out ../eval/out-samples
```
