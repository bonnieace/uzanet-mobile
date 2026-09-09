# UzaNet mobile

Flutter companion for [UzaNet's hardened backend](https://github.com/bonnieace/Mikrotik).

| Mode | Account | Features |
| --- | --- | --- |
| Local tools | None | Device-local router setup, router/hotspot status, users and usage, active sessions, recoverable voucher batches and PDF printing |
| Remote workspace | UzaNet operator | Remote routers and VPN onboarding, hotspot/PPPoE customers, plans, payments and provisioning recovery, logs, native checkout and renewals |

Local credentials stay in device secure storage. Remote features use authenticated HTTPS requests; the app never connects to the VPS database or VPN agent directly. Subscription charging is a future backend feature and is not enabled here.

## Run

Use Flutter **3.44.2**, Dart **3.12**, and Java **17** for Android.

```sh
flutter pub get --enforce-lockfile
flutter run
```

The default API is `https://api.uzanet.co.ke/api/v1/`. For another deployment, use `--dart-define=UZANET_API_URL=https://your-api.example/api/v1/`.

## Verify

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos
flutter test
```

GitHub Actions also compiles Android debug/unsigned release and iOS without signing. Android and iOS are the mobile targets; retained desktop/web scaffolding is not a supported release target for the native socket workflow.

Read [MVP readiness](docs/MVP_READINESS.md) for signing, configuration, known backend constraints, physical-device checks and launch gates. Rotate the router credential embedded in the old commit before releasing this app.
