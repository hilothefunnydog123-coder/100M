# How SpotCheck gets (and proves) accuracy

"Hella accurate" is the goal, and it has to be earned in layers, then
measured. No photo model is reliable enough on its own to tell someone
what they have. A confident wrong "you're fine" on a melanoma is the
failure that hurts people and gets apps pulled. So SpotCheck optimizes
for two things, in this order:

1. **Never under-triage.** The urgency advice must be at least as cautious
   as the situation needs.
2. **Name the right condition** among the top few possibilities, with
   honest likelihoods.

## What a photo can and can't do

- It can show visible conditions: rashes, moles and growths, acne, bites,
  wounds and burns, pink eye, styes, mouth sores, nail and scalp problems.
- It can't feel texture or warmth, see under the skin, or run a test. It
  can't tell strep from a virus, confirm a fungal infection, or rule out
  cancer. The prompt tells the model to say so and to recommend the test.
- Lighting, focus, skin tone, and camera processing all shift how a
  condition looks, so the app treats photo quality as a first-class input.

## The layers

| Layer | Where | What it protects against |
|---|---|---|
| Photo coaching and checks (brightness, glare, sharpness, resolution) | `packages/core/lib/src/photo_pipeline.dart`, run on the device | Garbage in: blurry, dark, or glare-washed photos |
| Close-up plus wider view | App photo step | Missing context (distribution, location, surrounding skin) |
| Structured intake: 17 questions, only the relevant ones asked | `packages/core/lib/src/intake.dart` | Image-only guessing; doctors weigh history as much as the image |
| Emergency interception before any AI runs | `SafetyRules.evaluate` → `EmergencyScreen` | Anaphylaxis, chemical eye injury, sepsis signs waiting on a model |
| Model reasoning order: quality → observations → differential → urgency | JSON schema property order in `server/lib/src/assessment_schema.dart` | Jumping to a name before looking |
| Adaptive thinking at `high` effort (Claude Opus 5.5) | `server/lib/src/analyzer.dart` | Shallow pattern matching on hard cases |
| Retake instead of guessing | `image_quality.usable = false` → retake screen | Confident answers from unusable photos |
| Serious conditions stay in the list when they can't be excluded | System prompt | Silent omission of melanoma, BCC/SCC, cellulitis |
| Deterministic safety floor, 49 rules | `packages/core/lib/src/safety_rules.dart` | The model under-calling urgency; rules can only raise it |
| Contradiction guard | App result view | A reassuring model headline next to escalated advice |
| Optional ensemble (N samples, most cautious urgency, serious possibilities never dropped) | `server/lib/src/ensemble.dart` | Run-to-run variance on borderline cases |
| Evaluation harness with fairness slices | `server/bin/eval.dart` | Believing it works without measuring |

## The numbers to watch

Run the harness (see [eval/README.md](../eval/README.md)) on a fixed,
seeded SCIN sample before every prompt, model, or effort change.

| Metric | Why it matters | Suggested launch gate |
|---|---|---|
| **Serious cases under-triaged** | Missed skin cancer or infection | As close to 0% as possible; investigate every case |
| Serious condition named | The differential includes the serious diagnosis | ≥ 90% |
| Top-3 accuracy | The right answer is among the first three | Track and improve; compare against published baselines for SCIN |
| Top-3 by Fitzpatrick group | Equal quality across skin tones | Gap between groups within a few points |
| Retake rate | Photo guidance works | Under ~15% |
| Cost and p95 latency | Unit economics and user patience | Know them before you set prices |

These gates are proposals. Set yours with a clinical advisor, and publish
the method and results: Apple asks medical apps to disclose their
methodology, and it builds user trust.

## Improving it

Change one thing at a time, re-run the same sample, and keep a held-out
test split you look at only for the final comparison.

- **Effort.** Compare `--effort medium`, `high`, and `xhigh`. On Opus 5.5,
  `medium` is the API default and already strong; triage is where extra
  thinking may pay off. Measure it.
- **Ensemble.** `--ensemble 3` triples cost. Check whether it reduces
  serious-case under-triage enough to justify it, perhaps only for moles.
- **Prompt.** Bump `promptVersion` in `server/lib/src/prompt.dart` on every
  change so reports stay traceable. Look at the harness's "most common
  top-1 misses" list for patterns.
- **Photo guidance.** If the retake rate is high for a body site, improve
  that site's tips.
- **Questions.** If the same confusion keeps happening, such as eczema
  versus fungal infection, a targeted question often fixes it.
- **Synonyms.** The harness lists reference labels it can't match. Add
  them to `LabelMatcher.synonyms` so the metrics stay honest.

## The data flywheel

The strongest long-term advantage is ground truth from your own users. The
check detail screen already asks "What did a doctor say?" and stores the
answer on the device. With explicit opt-in consent (and a privacy review),
confirmed outcomes can be contributed to an internal evaluation set. That
reflects your real users, their phones, and their skin tones better than any
public dataset.

## Later: beyond one general model

- A dedicated lesion classifier (trained on licensed dermoscopic and
  clinical images) run alongside the LLM for moles, with disagreements
  pushed to the more cautious answer.
- A paid "have a dermatologist review this" option through a teledermatology
  partner. It's the most accurate layer there is, and a revenue line.
- A clinical validation study, the prerequisite for any regulatory
  clearance and for claims beyond triage.
