# SpotCheck: the plan to $10M ARR

All numbers below are planning estimates. Replace each one with a measured
value as soon as you have it: the evaluation harness measures cost and
latency, and the funnel metrics come from your first few thousand installs.

## The product in one line

Point your phone at a rash, mole, bite, red eye, mouth sore, or nail and,
in about a minute, learn what it might be, whether it's worrying, and
exactly how soon to see someone.

## Who it's for

| User | Moment | What they need |
|---|---|---|
| Worried adult | "What is this rash / spot?" at 11pm | A calm, specific answer and a clear next step |
| Parent | A child's rash, bite, or pink eye | Is this an ER trip, a pediatrician call, or nothing? |
| 40+ with moles | "Has this mole changed?" | Tracking over time, and a nudge to see a dermatologist |
| Anyone without easy access to a dermatologist | Months-long waits | Know whether it's worth the wait or the urgent slot |

The job to be done is **deciding what to do next**, not getting a
diagnosis. That's also why the product can be honest and still be worth
paying for.

## Why it can win

The category is proven: skin-scanner apps get millions of downloads, and
people already search Google Lens for their rashes. What most tools lack
is exactly what SpotCheck is built around:

1. **Triage first.** Every result leads with urgency and who to see, and
   emergencies are caught before any AI runs.
2. **Safety you can explain.** 49 deterministic rules that can only make
   advice more cautious. That's a story for users, app reviewers, clinicians,
   and press.
3. **Beyond skin.** Eyes, mouth and throat, nails, and scalp in one app, for
   the whole family.
4. **Private by design.** Photos aren't stored on servers, and history stays
   on the phone.
5. **Measured and published accuracy**, including by skin tone. A
   credibility moat that fast followers won't bother to build.

## Business model

- **Free:** 3 checks (configurable with `FREE_CHECKS`). Safety information
  (urgency, red flags, the emergency screen) is never paywalled. That's a
  principle, and it's also what keeps app reviewers and clinicians on side.
- **SpotCheck Pro:** $49.99/year with a 7-day free trial, or $9.99/month.
  Unlimited checks, spot tracking with recheck reminders, doctor summaries,
  family use.
- **Later add-ons:** "Have a dermatologist review this" through a
  teledermatology partner (about $29–39 per case, revenue share), and
  referral fees for booked appointments.

### Unit economics (estimate, then measure)

| Item | Estimate |
|---|---|
| Claude Opus 5.5 cost per check at `high` effort | ~$0.10–0.20 (two ~2048 px photos ≈ 8–9k input tokens at $4/MTok, cached system prompt at $0.20/MTok, 3–7k thinking + output tokens at $20/MTok) |
| At `medium` effort | Roughly half the output tokens |
| Net revenue per annual subscriber | ~$42 after a 15% store fee (small business program), ~$35 at 30% |
| Checks per Pro user per month | 2–6 → $3–15 per year in model cost |
| Gross margin on Pro | ~65–90% |
| Free-tier model cost per install | Up to ~$0.50 if all 3 free checks are used |

Levers if costs run high: `medium` effort for free-tier checks, 2 free
checks instead of 3, one photo instead of two for simple cases, and prompt
caching (already on).

## The path to $10M ARR

$10M ARR is roughly **240,000 paying annual subscribers** at ~$42 net, or
the equivalent mix of monthly plans.

| Funnel step | Planning assumption |
|---|---|
| Install → finishes onboarding | 70% |
| → completes a first check | 60% of those |
| → starts a trial | 8–12% of installs |
| → converts to paid | 40–50% of trials |
| **Install → paid** | **~4–5%** |

That means **~5–6 million installs** over 18–24 months, plus renewals. It's
ambitious but in range for a top app in a high-intent, visual category.
Channels, in order:

1. **Short-form video.** "I asked AI about this mole" / "what my rash
   turned out to be" formats, before-and-after tracking, and partnerships
   with dermatologists and nurse creators (who also add credibility).
   Budget for UGC creators from week one.
2. **App Store search.** High-intent keywords: skin scanner, rash
   identifier, mole checker, skin analyzer, pink eye. Invest in ASO, then
   Apple Search Ads.
3. **SEO plus a web check.** Condition pages ("ringworm vs eczema on dark
   skin") that funnel into the app. The Flutter web build is a head start.
4. **Built-in referral.** Every shared doctor summary carries the name, and
   parents check for the whole family.
5. **Paid social** once measured LTV supports a CAC under about a third
   of it.
6. **Partners.** Telehealth referrals, pharmacies, employers.

**Retention loops:** monthly mole recheck reminders, family members,
seasonal spikes (summer rashes, bites, sunburn), and the history as a
personal skin record.

## Roadmap

| When | What |
|---|---|
| Weeks 0–4 | TestFlight beta · SCIN evaluation baseline · clinician review of rules and prompt · RevenueCat · App Check · privacy policy · US launch |
| Months 2–4 | Push reminders · body map for mole tracking · Spanish · dermatologist-review partner |
| Months 4–9 | Opt-in outcome data · lesion classifier ensemble · published accuracy report · family plan |
| Months 9–18 | Clinical validation study · evaluate an FDA pathway for lesion triage · international with a regulatory plan |

## Metrics that run the company

- Funnel: install → onboarding → first check → paywall → trial → paid
- Quality: retake rate, analysis success rate, **serious-case under-triage
  on the eval set**, agreement with doctor verdicts users report
- Engagement: checks per user, recheck completion, D30 retention
- Economics: model cost per check, p95 latency, LTV:CAC by channel

## Risks

| Risk | Mitigation |
|---|---|
| A missed serious condition harms someone | Safety floor, emergency interception, never-reassure copy, evaluation gates, clinician review |
| Regulatory action over claims | Triage framing, claims discipline ([LAUNCH.md](LAUNCH.md)), counsel review, a deliberate device pathway later |
| App Store rejection | Published methodology, disclaimers, demo mode for reviewers |
| Free alternatives (Google Lens) | Triage, tracking, family use, trust, and doctor summaries, not just "what is this" |
| Model cost or latency spikes | Effort tuning, caching, per-tier effort, concurrency limits |
| Privacy incident | No server-side storage of photos or answers; minimal logging |
