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

- [ ] Replace the bundle id `app.jobwalk.jobwalk` with your own
      (iOS project, `android/app/build.gradle.kts`).
- [ ] Build against the server:
      `flutter build ipa --dart-define=API_BASE_URL=https://api.jobwalk.app`
      (and `flutter build appbundle` for Android).
- [ ] Android release signing; Apple team and provisioning.
- [ ] Privacy policy and terms at the URLs in `app/lib/config.dart`. The
      policy should say: photos go to the Jobwalk server and Anthropic's
      API to draft the quote, and Jobwalk doesn't store them; published
      quotes store only what the customer sees.
- [ ] Store listings: screenshots of the capture, quote, and customer
      pages. Camera and photo-library permission text is already set.
- [ ] TestFlight and Play internal testing for the beta cohort.

## 4. Getting paid

- [ ] Stripe products for Pro and Crew, the customer portal, and both
      webhook endpoints ([DEPLOY.md](DEPLOY.md#stripe)).
- [ ] Connect with Express accounts: contractors take card deposits
      through Jobwalk (1% platform fee plus card processing). A payment
      link from Settings still works for anyone who doesn't connect.
- [ ] Sell plans on the web (Stripe Checkout), not through in-app
      purchase, and keep the app free to download.

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
