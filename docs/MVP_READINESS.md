# UzaNet mobile MVP readiness

## Product boundary

The free mode runs without a UzaNet account or an internet connection: device-local router onboarding, RouterOS status, hotspot servers/profiles/users, usage state, active hotspot/PPP sessions, voucher generation and printing. It still needs a reachable local router; “offline” does not mean a disconnected router can be managed.

Remote mode requires an existing active UzaNet operator account. It uses the hardened FastAPI API, with backend ownership and role checks. It includes router registration/settings/deletion, VPN onboarding scripts, connection/traffic checks, plans, hotspot and PPPoE customers, enable/disable/delete actions, payment records, paid-access provisioning recovery, logs, account password change and logout. Native customer checkout supports hotspot purchases and existing PPPoE renewals through the provider configured by the backend.

There is **no subscription billing or paid entitlement enforcement yet**. Remote features are authenticated, ready for a future paid tier. An app-only paywall is not authorization: add and enforce entitlements on every applicable backend route before monetizing remote access. Existing payment-provider integrations collect ISP customer payments, not app subscription fees.

## Changes from the original app

- Removed the embedded router address/password and all credential/command logging. The old password remains in Git history: rotate that router credential before distribution.
- Replaced the previous RouterOS dependency, whose implementation logged outgoing words unconditionally and assumed whole replies arrived in one packet. The new bounded native transport handles fragmented UTF-8 sentences, closes sockets on failure, supports certificate-validated TLS, refuses legacy challenge login, and never includes router error payloads in user messages.
- Local setup tests a read-only resource command before saving connection details in platform secure storage. Private IPv4 addresses only; plaintext API is an explicit trusted-LAN choice. TLS does not disable certificate verification. A private address is not proof of the physical route: a device VPN may route private subnets; this app does not create a VPN in free mode.
- Removed mock router model/version and fake expiry logic. Zero uptime limit is unlimited; week/day/time formats are handled. Active-session reports are described as snapshots, not login history.
- Voucher intent and generated credentials are saved before sending a router mutation. A timeout marks the ticket uncertain; recovery looks up and verifies that same username and credentials. It never automatically repeats an uncertain add. Confirmed tickets can be reprinted without provisioning again. Only one current batch per device/router/account is supported; this is not a multi-device inventory or spooler.
- Remote JWTs live in secure storage, never source code or preferences. Login uses OAuth form encoding and validates `/me`. HTTPS only, redirects disabled, finite request/response limits, no automatic mutation retries. Expiry/401 destroys the remote navigation stack; late responses from old sessions are rejected. Local tools survive logout.
- Checkout saves the exact body/idempotency key before initiation, retains the payment capability in secure storage, and resumes the same request/status lookup after interruption. Price/provider cannot be supplied by the form. No operator bearer token is sent to public payment endpoints. Polling is bounded and stops on background/disposal/errors. Unconfirmed payments cannot be cleared for a new purchase. If a status token expires, checkout reconciles the outcome through the authenticated, router-scoped payment-session list. Unresolved payments remain blocked; use Payment recovery to investigate before another payment.
- Forms lock during submission; lists provide loading, empty, retry and refresh states. Router-changing and account-changing operations require explicit actions.
- Android release signing no longer falls back to a debug key. Android backups are disabled; HTTP cleartext policy is disabled (raw RouterOS TCP is deliberately controlled by the local connection setting). iOS includes local-network purpose text and device-bound Keychain access.

## Build and configuration

Use the CI-pinned Flutter 3.44.2 SDK and Java 17. Keep `pubspec.lock` committed.

```sh
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos
flutter test
flutter build apk --debug
```

Default backend: `https://api.uzanet.co.ke/api/v1/`. Override only at build time:

```sh
flutter build appbundle --release --dart-define=UZANET_API_URL=https://api.uzanet.co.ke/api/v1/
```

The URL must be HTTPS and end in `/api/v1/`. No admin secrets, provider keys, VPN shared secret or router credentials belong in Dart defines. The backend hostname changes invalidate the saved operator session.

Configure `android/key.properties` locally (gitignored):

```properties
storeFile=/absolute/path/to/upload-keystore.jks
storePassword=YOUR_KEYSTORE_PASSWORD
keyAlias=upload
keyPassword=YOUR_KEY_PASSWORD
```

CI may compile an **unsigned** release via `./gradlew assembleRelease -PallowUnsignedRelease=true`; that artifact cannot be distributed as a signed release. Do not enable this flag for publication. iOS CI builds without signing and does not prove provisioning-profile/store readiness.

The existing `com.example.uzanet` application identifiers are preserved to avoid silently breaking an existing installation/store lineage. Confirm whether this app was previously published. Choose permanent identifiers before its first store release, or preserve the existing identifiers and signing keys for updates.

## Backend and operational gates

1. Use the hardened backend migrations, encryption/auth configuration, allowed management CIDRs, payment webhooks and scheduled expiry jobs. Those remain backend responsibilities. The mobile app does not access MySQL, the VPS, the VPN agent or payment-provider secrets directly.
2. Remote onboarding creates a one-time RouterOS script. The operator must apply it to the intended router and then confirm online/authenticated status. It is not executed automatically on a locally configured router. The backend VPN agent / xl2tpd socket integration must be healthy on the VPS.
3. RouterOS profiles must exist before adding plans/users. Rate-limit metadata does not configure a router profile. Backend router deletion may be blocked by retained records, including retired plans.
4. Native networking is not browser CORS. API authentication, account enabled state, certificate validity and reverse-proxy/rate-limit settings still apply. Configure trusted client-IP forwarding at the edge for payment rate limits.
5. Native checkout shows issued hotspot credentials for entry on the router’s captive page. It does not submit credentials to an arbitrary captive URL or implement RouterOS CHAP. PPPoE renewals use the existing account username. Internet reachability is required for STK/status calls; ensure captive-network walled-garden and SMS fallback work for your deployment.
6. The one-time onboarding script must be retained by the operator when generated. The backend currently has no mobile-safe script reissue endpoint. If the response is lost, inspect the existing router before creating another onboarding record.

## Physical acceptance checks before launch

- Fresh Android/iOS installation: deny then allow local-network access; add/edit/forget a router; bad password, unreachable IP, API disabled, invalid TLS certificate, accepted TLS certificate and explicit plain-LAN mode.
- RouterOS 6.43+ and 7: Unicode profile names, large user lists, slow/fragmented network, disconnect during a read, reconnect, usage limits and unlimited accounts. Verify relevant router policies without handing out unrestricted admin credentials.
- Create a small voucher batch; disconnect immediately after an add; restart the app; verify recovery has exactly one user per ticket. Stop halfway through a batch. Test unavailable secure storage and a full device. Confirm print cancellation/reprint does not create users. Verify A4 output and actual configured Android/iOS print services; thermal/ESC-POS and persistent print-job spooling are not implemented.
- Sign in with wrong/disabled/locked accounts; expire/revoke token while nested inside a router; sign out offline; sign in as another owner; background/resume; Android system Back; rotate device and test narrow screens/large text. Confirm no previous operator data remains visible.
- Two owners: backend must reject cross-owner UUIDs. Test remote status offline/online, missing profile, plan retirement, customer enable/disable/delete, PPPoE restoration and scheduled expiry.
- Provider sandbox first: M-Pesa and Kopo Kopo success/failure/cancellation; close app after payment initiation; recover identical request; duplicate webhook; paid-but-router-offline; authenticated retry after repair. Verify a paid PPPoE renewal extends access once. Exercise expired payment capabilities through Payment recovery.
- Android signed release and iOS signed physical build, printer integration, store IDs/version codes, privacy policy/support/deletion process, privacy/data safety forms, signing backups and backend backup/restore drill. No production customer charge/router mutation is part of CI.

## Test evidence

Automated checks and CI status are recorded in the pull request. Tests cover protocol fragmentation and secret-safe errors, local address/uptime validation, secure-write-before-provision behavior, interrupted voucher recovery, duplicate submit guards, token invalidation/session races, payment replay/capabilities and public-vs-authenticated navigation. A passing mock-based suite is not a claim of verified provider, VPN, printer or physical-device operation.

The Flutter tooling’s Azure metadata probe is suppressed with its supported `CI=true` environment and analytics disabled. In a root/container runtime that rejects archive ownership IDs, `TAR_OPTIONS=--no-same-owner` allows SDK extraction without changing file ownership. Neither setting changes application behavior.

Remote onboarding supports the backend's expiring, single-use fetch/import command.
The result page lets the operator copy the command and inspect the manual RSC
fallback; old backend responses without a command still display the script.
Deploy backend migration `a7b8c9d0e1f2` first. No tokens are stored in app preferences.
Replacing an existing managed tunnel is explicit and disconnects its previous
UzaNet record. Account-free local onboarding is unchanged. Physical RouterOS
fetch/import and certificate-store acceptance are still required before rollout.
