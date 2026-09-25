# Launch checklist

## 1. Claude API

- [ ] Create an Anthropic API key for production and set a monthly spend
      limit in the console.
- [ ] Run the accuracy harness on real past jobs before the beta:
      `dart run bin/eval.dart --manifest ... --max-cost 20`.

## 2. Server

The server is a single binary (`server/Dockerfile`) that stores published
quotes and waitlist signups as files under `JOBWALK_DATA_DIR`. It needs one
instance with a persistent disk: a small VM, or Fly.io or Railway with a
volume. Before running several instances, move storage to Postgres by
implementing `QuoteStore`.

```sh
docker build -f server/Dockerfile -t jobwalk-api .
docker run -p 8080:8080 -v jobwalk-data:/data \
  -e ANTHROPIC_API_KEY=... \
  -e JOBWALK_PUBLIC_URL=https://jobwalk.app \
  -e JOBWALK_CORS_ORIGINS=https://app.jobwalk.app \
  jobwalk-api
```

- [ ] Domain and HTTPS. Quote links are `JOBWALK_PUBLIC_URL/q/<id>`.
- [ ] Back up the data volume daily.
- [ ] Watch the JSON logs: `draft` events carry latency, tokens, and
      estimated cost; `draft_failed`, `rate_limited`, and `overloaded` are
      the ones to alert on.
- [ ] Optional settings: `JOBWALK_EFFORT` (default `high`),
      `JOBWALK_MODEL`, and rate limits (`JOBWALK_RATE_LIMIT_*`).

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

- [ ] For the beta, each contractor adds their own Stripe, Square, or
      PayPal payment link in Settings; customers see a Pay deposit button
      after approving.
- [ ] Later: Stripe Connect for built-in deposits and a take rate.
- [ ] Jobwalk's own subscription: sell plans on the web, not through
      in-app purchase, and keep the app free to download.

## 5. Beta operations

- [ ] Consent for using past-job photos and prices in the eval set.
- [ ] A support channel (a shared inbox or text line) listed in the app.
- [ ] Weekly review: accuracy (change from draft), time to send, approval
      rate, and every failed draft.

## Known limits of the MVP

- Quotes live on the phone; there are no accounts or sync yet, so a lost
  phone loses its quotes (links already sent keep working).
- Status updates arrive when the app refreshes (on open, and with pull to
  refresh); there are no push notifications yet.
- The quote link is unguessable but not password-protected: anyone who has
  it can view it, like most quote and invoice links.
