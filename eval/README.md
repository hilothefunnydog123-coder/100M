# Accuracy harness

Scores AI drafts against what contractors actually charged, so prompt and
model changes are measured instead of guessed.

## Manifest

One JSON object per line (`//` lines are comments). Photo paths are relative
to the manifest.

```json
{"id": "paint-0142", "trade": "painting", "photos": ["paint-0142/1.jpg", "paint-0142/2.jpg"], "note": "two coats, ceilings too", "zip": "78704", "actual_total": 2480.00, "option": "full room"}
```

- `actual_total`: what the job was quoted or invoiced at, in dollars.
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
latency, overall and by trade. `--max-cost` stops starting new cases once the
run has spent that many dollars.
