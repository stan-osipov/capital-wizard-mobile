# capital-wizard-mobile

Hybrid iOS and Android shells for Capital Wizard. Build instructions are in
`CLAUDE.md`.

## Coding Lab

The shared iOS project also contains the `coding-lab-ios` target and shared
scheme. It builds **Coding Lab** (`co.coding-lab.ios`, version 1.0) with its own
flask icon, native launch/auth branding, OAuth callback, associated domain,
and `https://app.coding-lab.co/` WebView. Select this scheme in Xcode to run or
archive it. Both targets share the native source and bridge; `AppProduct` is
selected at compile time with `CODING_LAB`.

```sh
xcodebuild -project iOS/capital-wizard-ios.xcodeproj -scheme coding-lab-ios \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project iOS/capital-wizard-ios.xcodeproj -scheme coding-lab-ios \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath .build/CodingLab.xcarchive -allowProvisioningUpdates archive
xcodebuild -exportArchive -archivePath .build/CodingLab.xcarchive \
  -exportOptionsPlist iOS/ExportOptions-TestFlight.plist \
  -exportPath .build/coding-lab-testflight -allowProvisioningUpdates
```

Apple team: `V3B5J86794`. On 2026-10-08, `co.coding-lab.ios` was registered with
Apple Sign In, Push Notifications, and Associated Domains. The shared Supabase
project accepts `coding-lab-ios://auth/callback` and
`coding-lab-android://auth/callback`, and its Apple audience list includes
`co.coding-lab.ios`. Existing callbacks/audiences were preserved.
The web repository's product packaging writes Coding Lab's own Apple association
file to its app host. The marketing apex is not claimed by iOS.

Android mirrors the identity through `capitalWizard` and `codingLab` flavors:
`./gradlew assembleCapitalWizardDebug assembleCodingLabDebug`. Coding Lab uses
`co.codinglab.android`; supply its own `app/src/codingLab/google-services.json`
before enabling Firebase push. The existing Capital Wizard Firebase client is
never compiled into Coding Lab. Android app-link verification needs Coding Lab's
release certificate fingerprint before its `assetlinks.json` can be published.

Native store billing remains disabled in Coding Lab because the current catalog
and verification configuration belong to Capital Wizard. Apple/Google sign-in,
signed-in project navigation, and push delivery still need a real user/device
smoke test before a public App Store release.

## Direct mobile wallet sandbox integration

Both shells include matching `StoreService` implementations: system StoreKit on
iOS and Google Play Billing 8.3.0 on Android. RevenueCat is not used. Catalog,
console setup, server verification, rollout limits and device tests are documented
in `../capital-wizard/docs/mobile-wallet-payments.md`.

Purchases require a signed-in Capital Wizard administrator. iOS supports Debug
builds and TestFlight: a sandbox receipt enables the bridge, and Release builds
must also verify Apple's signed sandbox app transaction before opening a purchase
sheet. Missing/production receipts keep Release billing unavailable. Every iOS
purchase must be a verified sandbox transaction before it is sent to the server.
Android remains Debug-only: Play test tracks can charge real money for users who
are not license testers, unlike TestFlight. Its release gate stays closed until
the Google setup and device tests are complete.

The server must be configured and the corresponding sandbox gate enabled before
opening a purchase sheet. No store API keys or service-account credentials belong
in these native builds. These TestFlight instructions supersede the older
Debug-only iOS restriction in the web repository's mobile billing document.

The native layer sends purchase evidence straight to `store-verify` using its
Supabase session. The server validates the store, account and paid transaction,
and atomically credits the isolated test wallet. Only then does iOS finish the
transaction or the server acknowledge/consume the Play purchase. Pending results
retry on launch/restore. The web bridge never receives purchase evidence.

This is not a billing release. Both stores require real device sandbox testing;
live settlement and App Store/Google Play production billing remain disabled.
Build tools and caches installed for this worktree live under ignored `.build/`.

## Upload an iOS sandbox build to TestFlight

1. Open `iOS/capital-wizard-ios.xcodeproj` in Xcode. Sign in to the Apple Developer
   account for the team that owns `com.capital-wizard`; use automatic signing.
2. Select the `capital-wizard-ios` scheme and a generic iOS device destination.
   Keep Archive on Release and StoreKit Configuration on None. Set a build number
   that has not been uploaded for version 1.7 (Xcode can manage this on upload).
3. Product → Archive → Distribute App → TestFlight Internal Only. This build is
   for administrator testing, not submission to the public App Store.
4. Wait for App Store Connect processing, then add the build to an internal
   TestFlight group containing the tester. Sign in to TestFlight with the normal
   Apple Account; the sandbox account is only for optional purchase controls.
5. Install from TestFlight, sign in to Capital Wizard with an administrator
   account, and open Billing. Buy `cw_credit_10` once. Check that the purchase
   sheet is for sandbox testing, then verify that the isolated test wallet gains
   one $10 credit (any outstanding test invoice may use some of it). If pending,
   reopen/restore instead of buying again.

TestFlight purchases use Apple's sandbox without charging the tester. The
production notification URL stays unset. Sandbox device verification, including
renewals, refunds, account switching and duplicate delivery, is still required.

For command-line uploads after Xcode's Apple account and signing are configured,
run from this repository's root:

```sh
mkdir -p .build
xcodebuild -resolvePackageDependencies -project iOS/capital-wizard-ios.xcodeproj \
  -scheme capital-wizard-ios -clonedSourcePackagesDirPath "$PWD/.build/packages"
xcodebuild -project iOS/capital-wizard-ios.xcodeproj -scheme capital-wizard-ios \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath "$PWD/.build/ios" -clonedSourcePackagesDirPath "$PWD/.build/packages" \
  -archivePath "$PWD/.build/CapitalWizard.xcarchive" -allowProvisioningUpdates archive
xcodebuild -exportArchive -archivePath "$PWD/.build/CapitalWizard.xcarchive" \
  -exportOptionsPlist iOS/ExportOptions-TestFlight.plist \
  -exportPath "$PWD/.build/testflight" -allowProvisioningUpdates
```

The export options upload an internal-only TestFlight build and let Xcode choose
the next build number. A successful archive alone does not mean it was uploaded;
confirm upload success and App Store Connect processing before inviting testing.

References: [Apple TestFlight purchases](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testing-subscriptions-and-in-app-purchases-in-testflight/),
[signed app transaction](https://developer.apple.com/documentation/storekit/apptransaction).
