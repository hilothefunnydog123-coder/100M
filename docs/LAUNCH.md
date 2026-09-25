# Launch guide: claims, stores, privacy, payments

This is a practical checklist, not legal advice. Before you launch a health
app, have a regulatory attorney or consultant review your claims, privacy
policy, and store listings. That costs far less than a rejection, a recall,
or an enforcement action.

## 1. What SpotCheck claims (and doesn't)

The product is designed as **triage and education**: possibilities, urgency,
next steps, and when to see a clinician. That framing is what keeps it safe
and shippable. Keep every surface (App Store listing, ads, TikToks,
onboarding, push notifications) inside it.

| Say | Don't say |
|---|---|
| "See what it might be and how soon to get it checked" | "Diagnose your skin" / "Know if you have a disease" |
| "Helps you decide whether to see a doctor" | "Replaces a dermatologist visit" |
| "Flags warning signs that need a doctor's attention" | "Detects skin cancer" / "Melanoma risk score" |
| "Built with clinical safety rules" | "Dermatologist-level accuracy" (unless you have published evidence) |
| Measured, published accuracy with its method | Accuracy numbers without a published method |

Why this matters:

- **FDA.** Software that analyzes medical images to diagnose or detect
  disease is generally a regulated medical device. Tools that suggest
  possible conditions and advise when to see a clinician have been treated
  as lower risk, but image analysis, and anything cancer-related, gets
  scrutiny. SpotCheck's mole rules only ever *refer* (never reassure), and
  the copy never claims detection. Get an opinion on your final feature set.
  A cleared device (510(k) or De Novo) is a later, deliberate step. It needs
  a clinical validation study.
- **FTC.** In 2015 the FTC acted against two mole-checking apps (MelApp and
  Mole Detective) for claiming, without evidence, that they could assess
  melanoma risk from photos. Every accuracy or health claim needs
  substantiation.
- **Outside the US.** The EU (MDR) and UK (MHRA) are generally stricter:
  image-based triage software is likely a medical device there. Launch in
  the US first unless you plan for certification.

## 2. App Store and Google Play

**Apple (App Review Guidelines 1.4.1 and 5.1.3)**
- Medical apps get extra scrutiny. Apple asks you to disclose the data and
  methodology behind accuracy claims, and it rejects apps whose accuracy
  can't be validated. Publish your evaluation method and results (see
  [ACCURACY.md](ACCURACY.md)) and link them in the review notes.
- Remind users to check with a doctor. The app does this in onboarding
  and on every result.
- Health data may not be used for advertising and **may not be stored in
  iCloud**. Exclude the app's storage directory from iCloud backup before
  submitting (see the checklist).
- Give reviewers demo instructions. A build with `DEMO_MODE=true` or a
  reviewer account avoids "app didn't work" rejections.
- Choose the Medical category and answer the age-rating questionnaire's
  medical-information item honestly.

**Google Play**
- Complete the health apps declaration in Play Console, include a clear
  "not a medical device; not a diagnosis" disclaimer in the listing, and
  link a privacy policy.
- Declare camera and photo use in the Data safety form. Photos are sent
  for processing and not stored.

## 3. Privacy and security

SpotCheck is built to collect as little as possible:

- Photos and answers are analyzed in memory by the API and never written to
  disk or logs. Logs contain only ids, status, urgency, latency, and cost.
- History, photos, and the profile live on the device only.
- The install id is random and only used for rate limiting.
- No ad or analytics SDKs. If you add analytics, never send health data,
  photos, or answers.

What you still need to handle:

- **Model provider terms.** By default, Anthropic doesn't train on API
  inputs or outputs. Review the current retention terms for your account,
  and ask about zero data retention for health workloads.
- **US state and federal rules.** The FTC Health Breach Notification Rule
  applies to health apps outside HIPAA. Washington's My Health My Data Act
  (and similar laws) require explicit consent and a dedicated health-data
  privacy policy. Write your privacy policy to match what the app actually
  does, and update `privacyPolicyUrl` and `termsUrl` in `app/lib/config.dart`.
- **HIPAA.** A direct-to-consumer app usually isn't covered. If you add
  clinician review or partner with providers, you may become a business
  associate; confirm BAAs with every vendor in the data path.
- **Abuse.** The API key never ships in the app. The server rate-limits by
  install and IP. Before launch, add Firebase App Check (App Attest on iOS,
  Play Integrity on Android) and verify its token in the API, so only your
  real app can spend your Claude budget.

## 4. Payments

`app/lib/services/purchases.dart` defines `PurchasesService` and ships a
**simulated** implementation that shows a "purchases are simulated" notice.
Replace it before release:

1. Create the subscription products in App Store Connect and Play Console
   (the paywall assumes $49.99/year with a 7-day trial, and $9.99/month).
2. Add RevenueCat (`purchases_flutter`), configure an entitlement such as
   `pro`, and implement `PurchasesService` with it: load offerings for the
   plan cards, purchase a package, and set Pro from the active entitlement.
3. Enforce the free quota on the server too. Today it's counted on the
   device, so reinstalling resets it. Verify entitlement with RevenueCat
   (webhooks or REST) in the API before serving checks beyond the free tier.

## 5. Pre-launch checklist

**Product and safety**
- [ ] Run the SCIN evaluation at your chosen effort and review every
      under-triaged serious case
- [ ] Have a clinician review the 49 safety rules and the system prompt
- [ ] Decide free-check count and effort for free users (cost vs. conversion)
- [ ] Set the emergency number by locale (Settings has a manual override)

**Engineering**
- [ ] Deploy the API (see README) with `SPOTCHECK_CORS_ORIGINS` restricted
- [ ] Build the app with `--dart-define=API_BASE_URL=https://your-api`
- [ ] Add App Check / Play Integrity and verify tokens in the API
- [ ] Exclude the storage directory from iCloud backup on iOS (set
      `isExcludedFromBackup` on the Application Support/spotcheck URL via a
      small platform channel), and consider encrypting it at rest
- [ ] Replace simulated purchases with RevenueCat; server-side entitlement
- [ ] Set real bundle ids (currently `com.spotcheck.spotcheck`) and signing
- [ ] Add recheck push notifications (the in-app "Time to recheck" list
      already works)
- [ ] Error monitoring that never captures request bodies

**Legal and store**
- [ ] Regulatory review of claims and feature set
- [ ] Privacy policy (including health-data consent) and terms
- [ ] Trademark search for the name; "SpotCheck" is a working name
- [ ] Store listings that follow section 1's table
- [ ] Review notes with demo instructions and a methodology link
