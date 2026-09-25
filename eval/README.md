# Accuracy evaluation

The harness runs the production analyzer (same prompt, schema, safety rules,
and photo preparation as the app) over labeled cases and reports:

- **Top-1 / top-3 accuracy** against a dermatologist differential
- **Serious cases under-triaged**: the safety number that matters most. A
  case counts as under-triaged when the advice is less urgent than the case
  needs, including retakes and declines on a serious case.
- **Serious condition named**: whether a serious reference condition made
  the differential at all
- **Top-3 accuracy by skin tone** (Fitzpatrick I-II, III-IV, V-VI), to catch
  bias before users do
- Retake, decline, and error rates; estimated cost; p50/p95 latency

## Run it on SCIN

[SCIN](https://github.com/google-research-datasets/scin) is Google's public
dataset of smartphone skin photos with dermatologist labels. Check its license
before using it beyond internal evaluation.

```bash
# 1. Build a manifest (downloads the CSVs; images are fetched lazily)
python3 eval/scin_to_manifest.py --out eval/data/scin/manifest.jsonl \
    --sample 300 --seed 7 --serious-first

# 2. Dry run the pipeline without API calls
cd server
dart run bin/eval.dart --manifest ../eval/data/scin/manifest.jsonl --limit 10 --fake

# 3. Real run: this spends API credits (roughly $0.05-0.15 per case at
#    effort=high). Start small; --max-cost stops the run at a spend cap.
ANTHROPIC_API_KEY=sk-ant-... dart run bin/eval.dart \
    --manifest ../eval/data/scin/manifest.jsonl --limit 50 --max-cost 10
```

Each run writes `results.jsonl` (per case), `summary.json`, and `report.md`
to `eval/out/<timestamp>/`. `eval/data/` and `eval/out/` are git-ignored.

Useful comparisons: `--effort medium` vs `high`, `--ensemble 3` vs `1`, and
any prompt change (bump `promptVersion` in `server/lib/src/prompt.dart` so
reports stay traceable).

## Your own cases

Any JSONL file with this shape works (`images` can be URLs or paths relative
to the manifest):

```json
{"id": "case_1", "site": "arm", "images": [{"path": "img/1.jpg", "kind": "close_up"}],
 "answers": {"skin_kind": ["rash"], "duration": ["1_6d"]},
 "labels": [{"name": "Eczema", "weight": 0.7}, {"name": "Psoriasis", "weight": 0.3}],
 "fitzpatrick": "fst5", "serious": false, "expected_urgency": "self_care"}
```

The best long-term dataset is your own: with consent, ask users what their
doctor concluded and add those confirmed outcomes here.
