# SpotCheck app

Flutter app for iOS, Android, and web. See the [root README](../README.md)
for the full picture.

```bash
flutter run                                   # demo mode: canned results
flutter run --dart-define=API_BASE_URL=http://localhost:8080
flutter test
```

Build-time options (`--dart-define`):

| Name | Default | |
|---|---|---|
| `API_BASE_URL` | (none → demo mode) | SpotCheck API base URL |
| `DEMO_MODE` | `false` | Force demo mode even with an API URL |
| `FREE_CHECKS` | `3` | Checks before the paywall |

Code map:

```
lib/
  app.dart, main.dart      bootstrap, storage, theme
  config.dart              --dart-define configuration
  data/                    on-device storage (files; browser storage on web)
  services/                API client, photo capture/processing, purchases
  state/                   Riverpod providers and the check-flow draft
  theme/                   colors (incl. urgency palette) and typography
  ui/                      onboarding, home, check flow, result, history,
                           paywall, settings
tool/
  generate_icons.dart      renders the app icon into every platform slot
  generate_samples.dart    synthetic demo photos (no real patient images)
```
