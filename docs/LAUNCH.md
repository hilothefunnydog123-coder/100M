# Launch checklist

## 1. Claude API

- [ ] Create an Anthropic API key for production and set a monthly spend
      limit in the console.
- [ ] Run the accuracy harness on real past jobs before the beta:
      `dart run bin/eval.dart --manifest ... --max-cost 20`.

## 2. Server

Follow [DEPLOY.md](DEPLOY.md): Postgres, the API image, Resend, an R2 or
S3 bucket, and optionally Stripe.

- [ ] Domain and HTTPS. Quote links are `JOBWALK_PUBLIC_URL/q/<id>`.
- [ ] `JOBWALK_ENV=production` and every secret set; `/readyz` is green.
- [ ] Point-in-time recovery on Postgres; versioning on the photo bucket.
- [ ] Alerts on the JSON logs (`error`, `draft_failed`, `overloaded`,
      `job_failed`, `stripe_error`) and on `/metrics`.
- [ ] A review account for the app stores (`JOBWALK_REVIEW_EMAIL`,
      `JOBWALK_REVIEW_CODE`).

## 3. App

[STORE.md](STORE.md) has the steps, the listing text, and the privacy
answers; `store/` has the screenshots and the Play feature graphic.

- [ ] Keep or replace the app id `app.jobwalk.jobwalk` before the first
      upload; it can't change afterwards.
- [ ] iOS: pick your team in Xcode, `flutter build ipa` with
      `--dart-define=API_BASE_URL=...`, and upload to TestFlight.
- [ ] Android: create the upload key and `android/key.properties`, then
      `flutter build appbundle` with the same define, for internal testing.
- [ ] Give app reviewers the review account (`JOBWALK_REVIEW_EMAIL` and
      its fixed code); sign-in is by emailed code only.
- [ ] Privacy policy and terms: the server hosts them at `/privacy` and
      `/terms`, filled in from its own configuration (the AI provider,
      email, storage, and Stripe it uses, the fees, and the trial), and the
      app links to them on the server it's built against. Set
      `JOBWALK_LEGAL_NAME`, `JOBWALK_GOVERNING_LAW`,
      `JOBWALK_LEGAL_ADDRESS`, and `JOBWALK_CONTACT_EMAIL`, read both pages
      on the production URL, and have a lawyer review them before launch.
      With Gemini, the policy says the paid API is used: the key's Google
      Cloud project needs billing turned on.
- [ ] Store listings: name, description, keywords, screenshots, and the
      App Privacy and Data safety forms (STORE.md). Camera and
      photo-library permission text is already set.
- [ ] TestFlight and Play internal testing for the beta cohort.

## 4. Getting paid

- [ ] Stripe products for Pro and Crew, the customer portal, and both
      webhook endpoints ([DEPLOY.md](DEPLOY.md#stripe)).
- [ ] Connect with Express accounts: contractors take card deposits
      through Jobwalk (1% platform fee plus card processing). A payment
      link from Settings still works for anyone who doesn't connect.
- [ ] Sell plans on the web (Stripe Checkout), not through in-app
      purchase, and keep the app free to download. That's allowed on
      Apple's US storefront and, after enrolling in Google's external
      content links program, on Play in the US (STORE.md).

## 5. Beta operations

- [ ] Consent for using past-job photos and prices in the eval set.
- [ ] A support channel (a shared inbox or text line) listed in the app.
- [ ] Weekly review: accuracy (change from draft), time to send, approval
      rate, and every failed draft.

## Known limits

- Status updates reach the app when it syncs (on open, pull to refresh,
  and every minute while open) and by email; there are no push
  notifications yet.
- The quote link is unguessable but not password-protected: anyone who has
  it can view it, like most quote and invoice links.
