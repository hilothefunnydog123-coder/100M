# App Store and Google Play

Everything to get Jobwalk into TestFlight and Play internal testing, then
into the stores. Build on a Mac with Flutter installed; iOS builds need
Xcode.

## Before the first upload

- **App id.** Both projects use `app.jobwalk.jobwalk`. Keep it, or change
  it before the first upload, because it can't change after: iOS in Xcode
  (Runner target, Signing & Capabilities, Bundle Identifier), Android as
  `applicationId` in `app/android/app/build.gradle.kts`.
- **Version.** `version: 0.1.0+1` in `app/pubspec.yaml`. The number after
  `+` must go up with every upload to either store.
- **Server.** Every store build points at your API:
  `--dart-define=API_BASE_URL=https://api.jobwalk.app`. The app's privacy
  policy and terms links go to that server's `/privacy` and `/terms`.
- **Review account.** Set `JOBWALK_REVIEW_EMAIL` and `JOBWALK_REVIEW_CODE`
  on the server (see [DEPLOY.md](DEPLOY.md)); reviewers sign in with that
  email and fixed code.

## Accounts without a company

A sole proprietor publishes under their own name in both stores; an LLC
can take the apps over later.

- **Apple** enrolls you as an individual, and the App Store lists your
  legal name as the seller. After forming a company, ask Apple to convert
  the membership to an organization (Membership details, Convert to
  Organization); that needs the company's D-U-N-S number, and the apps
  stay put.
- **Google Play** shows a personal account's legal name, country, and
  email on the listing (the full address only for apps that sell through
  Google Play's billing, which Jobwalk doesn't). A personal account made
  after November 13, 2023 must run a closed test with at least 12 testers
  opted in for 14 days in a row before it can publish to production. Run
  the beta as that closed test: each crew member who joins counts.

## iOS

1. Join the Apple Developer Program ($99 a year) and create the app in
   App Store Connect with the bundle id.
2. Open `app/ios/Runner.xcworkspace` in Xcode, select the Runner target,
   and under Signing & Capabilities choose your team (automatic signing).
3. Build:

   ```sh
   cd app
   flutter build ipa --release --dart-define=API_BASE_URL=https://api.jobwalk.app
   ```

4. Upload `build/ios/ipa/*.ipa` with Apple's Transporter app, or open
   `build/ios/archive/Runner.xcarchive` in Xcode's Organizer and choose
   Distribute App.
5. In TestFlight, add your team as internal testers right away; outside
   testers need a short beta review first.

Export compliance is answered in `Info.plist`: the app uses only standard
HTTPS encryption.

## Android

1. Create a Google Play developer account ($25 once) and the app in Play
   Console. Keep Play App Signing on (the default).
2. Make an upload key once, and keep it and its passwords somewhere safe:

   ```sh
   keytool -genkey -v -keystore ~/jobwalk-upload.jks -keyalg RSA \
     -keysize 2048 -validity 10000 -alias upload
   ```

3. Create `app/android/key.properties` (git ignores it; never commit it):

   ```properties
   storePassword=<keystore password>
   keyPassword=<key password>
   keyAlias=upload
   storeFile=/Users/<you>/jobwalk-upload.jks
   ```

   Without this file, release builds are signed with the debug key, which
   Play rejects.
4. Build and upload `build/app/outputs/bundle/release/app-release.aab` to
   the Internal testing track, then add testers by email. With a personal
   account, also run a closed test for 14 days with 12 or more testers
   before applying for production access (see above):

   ```sh
   cd app
   flutter build appbundle --release --dart-define=API_BASE_URL=https://api.jobwalk.app
   ```

## Selling plans from the app

The Plans screen opens Stripe Checkout in the browser rather than using
Apple's or Google's in-app purchase. As of September 2026:

- **Apple** allows buttons and links to outside payment only on the US
  storefront. Release the iOS app in the United States only (App Store
  Connect, Pricing and Availability) until plans are also sold through
  in-app purchase. Apple currently takes no commission on these links, but
  it has asked the court to set one.
- **Google Play** allows it in the US for apps enrolled in its external
  content links program, with a service fee on those sales reported
  monthly from October 2026. Enroll before the Android app shows the
  Plans button to paying customers.

During the free beta nobody buys a plan, so this can wait for the switch
to paid.

## Store listing

| Field | Text |
|---|---|
| Name | Jobwalk |
| Subtitle (iOS, 30) | Job photos to approved quotes |
| Promotional text (iOS, 170) | Walk the job, snap a few photos, and send an itemized quote with your own prices before you leave the driveway. Customers approve and pay the deposit from their phone. |
| Short description (Play, 80) | Snap the job, get an itemized quote with your own prices, and get it approved. |
| Keywords (iOS, 100) | estimate,quote,contractor,painter,painting,fence,pressure washing,bid,handyman,landscaping,deposit |
| Category | Business (secondary: Productivity) |
| Age rating | 4+ / Everyone |
| Support URL | Your landing page, e.g. `https://jobwalk.app` |
| Privacy policy URL | `https://<your server>/privacy` |

**Description** (both stores):

```text
Jobwalk turns a walkthrough into an approved quote.

Take a few photos of the job and add a note like "two coats, ceilings too."
Jobwalk measures the job from the photos, scopes the work, and writes an
itemized quote priced with your own labor rate, markup, and price list.
Check the lines, text the link, and your customer picks an option, signs,
and pays the deposit from their phone.

- Send the quote before you leave the driveway, not after dinner.
- Your prices: Jobwalk estimates the work, and your rates set the price.
  Change a price once and it's remembered.
- Good, better, best: options where the job has a real choice, so
  customers choose up instead of shopping around.
- Check before sending: the assumptions that move the price are flagged
  for you to confirm.
- Write it yourself anytime: quotes you build by hand are always free.
- A link, not a PDF: customers approve with a signature record and can pay
  a card deposit that goes to your own Stripe account.
- Your whole crew: quotes sync across everyone's phones.

Made for painters, fence builders, pressure washers, landscapers,
handymen, and any crew that quotes from a walkthrough. New accounts
include 25 free AI drafts.
```

**Screenshots** are in `store/`: `ios/` at 1290 x 2796 (the 6.7-inch slot,
which App Store Connect scales for smaller phones) and `play/` at
1080 x 1920, plus the Play feature graphic (`play/feature-graphic.png`,
1024 x 500). They're taken from the demo build with the sample jobs;
retake them with real jobs once you have some.

**App Review notes:**

```text
Sign in with <JOBWALK_REVIEW_EMAIL>; the code is <JOBWALK_REVIEW_CODE>.
Jobwalk drafts contractor quotes from job photos. If you don't have a job
to photograph, tap New quote and pick one of the sample jobs. Account
deletion is in Settings.
```

## Privacy answers

Both stores ask what data the app collects. Jobwalk has no ads, analytics,
or tracking.

**App Store (App Privacy):** data is used for App Functionality only,
linked to the user, and not used for tracking.

- Contact Info: Name, Email Address, Phone Number, Physical Address (the
  business's and its customers')
- User Content: Photos or Videos (job photos), Other User Content (quotes
  and notes)
- Identifiers: User ID
- Purchases: Purchase History (the plan)

**Google Play (Data safety):** collected, not shared (the AI provider,
Stripe, and email service process data on Jobwalk's behalf, which Play
doesn't count as sharing), encrypted in transit, and users can ask for
deletion (in the app, or by email).

- Personal info: Name, Email address, Phone number, Address
- Photos and videos: Photos
- App activity: Other user-generated content (quotes)
- Financial info: Purchase history
