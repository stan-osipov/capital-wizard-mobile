# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Structure

Monorepo with platform-specific native apps:

```
iOS/          — Xcode project (Swift/UIKit)
Android/      — Gradle project (Kotlin)
```

Both apps are **hybrid native wrappers** — native authentication wrapping a WebView that loads `capital-wizard.com`. Post-login, auth tokens are injected into the web context via JavaScript bridge.

### The two shells ship in lockstep

**Any work done on the iOS app MUST also be done on the Android app, in the same task — and vice versa.** These are not two products; they are one product with two hosts. The web app is written once and asks the shell for things — a bridge event, an OS permission, a native screen, a stashed deep link, a push behaviour — and every one of those has to exist on both sides or the feature is silently broken for half the users, with no error anywhere to show for it.

When a change touches either shell:

- **Mirror it before calling the task done.** The two files should read as translations of each other, comments included: `Services/PushService.swift` ↔ `services/PushService.kt`, `Modules/WebView/WebViewCommunication.swift` ↔ `webview/WebViewBridge.kt`, `Services/DeepLinkService.swift` ↔ `services/DeepLinkService.kt`.
- **Where the platforms genuinely differ, implement each one's correct behaviour and say WHY in a comment** — the APNs sandbox/production split has no FCM equivalent; Android 13+ has a runtime notification permission iOS expresses as an authorization status; iOS opens an `SFSafariViewController` where Android fires an `ACTION_VIEW` intent. A real difference is documented; an unimplemented side is a bug.
- **Guard the web side** so a shell that has not shipped the capability yet degrades to "unknown" rather than to a wrong answer (`if (cw && typeof cw.x === 'function')` on the way in, a timeout on the way back).
- **Build both** before finishing:

```bash
xcodebuild -project iOS/capital-wizard-ios.xcodeproj -scheme capital-wizard-ios -sdk iphonesimulator build
```

```bash
cd Android && JAVA_HOME=/opt/homebrew/opt/openjdk@17 ./gradlew assembleDebug
```

---

## Which site the WebView loads (`EndpointStore`)

Both shells can be pointed at either of the web app's two deployments —
`app.capital-wizard.com` (built from `main`) or `dev.capital-wizard.com` (built
from `dev`). One binary, two addresses; the choice is persisted per device.

- `iOS/.../Utils/EndpointStore.swift` and `Android/.../utils/EndpointStore.kt`
  hold the two addresses and the `AppEndpoint` enum. Mirrored by
  `DEPLOY_ENDPOINTS` in the web app's `src/lib/deployEnvironment.ts` — change
  one, change all three.
- **The bridge carries a channel NAME, never a URL.** The web posts
  `{ type: "system", eventName: "set-endpoint", endpoint: "production"|"development" }`
  and the shell resolves it through the store's allowlist. The bridge hangs off
  `window`, so the allowlist has to be on the far side of it.
- A change **rebuilds** the web layer (`recreateWebView()` / `recreateOnce()`),
  never just reloads it: a reload would re-fetch the old URL and keep the
  document-start script that told the page which site it was on.
- That script carries `endpoint` in `window.__capital_wizard_native`, which is
  how the web app's admin header states the site. An older shell that omits it
  must read as *unknown*, never as production.
- Every same-host check (`shouldOverrideUrlLoading`, `decidePolicyFor`, the
  start URL, the deep-link loader) reads the store, so they follow the switch
  together — a stale one would kick in-app links out to the browser.
- Universal/app links stay production-only: `applinks:app.capital-wizard.com` is
  the sole associated domain, and dev links open in the browser.

---

## iOS (`iOS/`)

### Build & Run

Open `iOS/capital-wizard-ios.xcodeproj` in Xcode.

```bash
# Build from command line
xcodebuild -project iOS/capital-wizard-ios.xcodeproj -scheme capital-wizard-ios -sdk iphonesimulator build

# Run tests
xcodebuild -project iOS/capital-wizard-ios.xcodeproj -scheme capital-wizard-ios -sdk iphonesimulator test
```

**Dependency:** Supabase Swift SDK via Swift Package Manager (resolved through Xcode project).

### Core Flow

```
AppDelegate → AppManager (registers services) → SceneDelegate (sets up window)
  → WindowsService (subscribes to auth events, manages root VC transitions)
  → AuthService.postInit() (checks existing Supabase session)
  → On login: ApplicationService.startApplications() → WebViewApplication loads web app
  → WebViewCommunication injects tokens via window.__capital_wizard.auth(data)
```

### Service Layer (`iOS/capital-wizard-ios/Services/`)

Uses **Service Locator pattern** via `ServiceManager.shared`. `AuthService` and `ApplicationService` register in `AppManager.init()`; `WindowsService` registers in `SceneDelegate.scene(willConnectTo:)` (needs the live `UIWindow`). After registration, `AppManager.postInit()` calls `WindowsService.postInit()` then `AuthService.postInit()`.

- **AuthService** — Supabase Auth via `AuthClient` (PKCE flow, `KeychainLocalStorage`). Supports email/password, Google OAuth, and **Apple Sign In** (`ASAuthorizationAppleIDProvider`, exchanged with Supabase via `signInWithIdToken`). Publishes `onLogin`/`onLogout` events. OAuth callback URL scheme: `capital-wizard-ios://auth/callback` (handled by `SceneDelegate.scene(_:openURLContexts:)` → `AuthService.onOpenUrl`).
- **DeepLinkService** — maps an inbound link to a web-app route. Universal links (`https://app.capital-wizard.com/<path>`, via the `applinks:` entitlement) and a custom-scheme fallback (`capital-wizard-ios://open?path=…`) — the OAuth callback shares the scheme under the `auth` host, so `SceneDelegate` offers each URL to the router first and anything it declines still reaches `AuthService`. The route is **stashed**, not delivered: a link can arrive while the user is signed out or before the WebView exists, so `WebViewApplication.getInitialUrl()` consumes it on a cold start and the `onDeepLink` subscriber routes it in place (via the bridge's `navigate` push) when the WebView is already live. Consuming clears it, so a reload never re-navigates. See `docs/deep-links.md` in the web repo.
- **ApplicationService** — Creates/manages `Application` instances. Currently instantiates `WebViewApplication` plus an `ApplicationCenter` "More" entry.
- **WindowsService** — Window management, root VC transitions (auth ↔ main app), color scheme (dark/light/system) with persistence via UserDefaults.

### Event System (`iOS/capital-wizard-ios/Utils/Event.swift`)

C#-style observer pattern. Services communicate via `Event<T>` with `+=`/`-=` subscription operators and `.invoke()`. This is the primary decoupling mechanism between services.

### Web-Native Bridge (`iOS/capital-wizard-ios/Modules/WebView/`)

- **Native → Web:** Token injection, color scheme updates via `WKUserScript` / `evaluateJavaScript`
- **Web → Native:** `WKScriptMessageHandler` on channel `"iosCW"`, JSON message parsing
- **WebApiCalls/WebApiResponses:** Typed protocol-based communication
- Shared `WKProcessPool` across WebViews for cookie sharing

### Application Protocol (`iOS/capital-wizard-ios/Modules/`)

`Application` protocol defines lifecycle: `awake()`, `start()`, `stop()`, `pause()`, `resume()`. Applications have priority levels (base/static/dynamic) and layout options (left/right/wide/background) designed for future multi-app and iPad split-view support. Two implementations exist:
- `WebViewApplication` — the primary content surface, loads `capital-wizard.com`.
- `ApplicationCenter` (`Modules/ApplicationCenter/`) — a "More" tab that hosts an `ApplicationStore`, profile popover, and grid of installable apps. Mostly scaffolding for the future multi-app model; only the WebView app currently has real content.

### UI (`iOS/capital-wizard-ios/UI/`)

- **Auth screens:** `LoginViewController`, `SignUpViewController`, `ResetPasswordViewController` with custom components (`GradientButton`, `ValidatedTextField`, `AnimatedCardView`)
- **Navigation:** `TabBarController` and `SidebarController`/`SplitViewController` stubs for future multi-app layout
- **All UI is programmatic** (no SwiftUI), with `Main.storyboard` only for initial launch

### Utils

- `ServiceManager` — singleton service registry with generic `register<T>`/`getService<T>`
- `LocalizationManager` — singleton wrapping a per-language `Bundle` lookup. Supports English and Ukrainian (`en`, `uk`); auto-selects `uk` when device language starts with `uk` or region is `UA`. Selection persists in UserDefaults under `app_language`. Strings live in `*.lproj/Localizable.strings`.
- `Validator` — email and password form validation
- `Queue` — generic queue data structure

---

## Android (`Android/`)

### Build & Run

```bash
# Build from command line
cd Android && ./gradlew assembleDebug

# Run tests
cd Android && ./gradlew test

# Install on connected device/emulator
cd Android && ./gradlew installDebug
```

**Namespace:** `com.capitalwizard.android`
**Target/Compile SDK:** 36 (Android 16) | **Min SDK:** 26 (Android 8.0) | **Java/Kotlin:** 17

Google Play requires the target SDK to stay within one year of the latest Android release (enforced each August 31) — bump `targetSdk`/`compileSdk` in `app/build.gradle.kts` yearly. No JDK is on the PATH on this Mac; prefix Gradle commands with `JAVA_HOME=/opt/homebrew/opt/openjdk@17`.

**Dependencies:** Supabase Kotlin SDK (BOM 3.1.1), Ktor 3.0.3 (HTTP client), Credential Manager 1.5.0-beta01 (Google Sign-In), AndroidX (AppCompat, Material, Lifecycle, WebKit, Splashscreen).

**Build config:** Version catalog at `gradle/libs.versions.toml`. ViewBinding enabled. Release builds use ProGuard minification + resource shrinking. ProGuard rules preserve Supabase, Ktor, Kotlinx Serialization, and `@JavascriptInterface` methods.

### Core Flow

```
CapitalWizardApp (registers AuthService in ServiceManager)
  → LoginActivity (splash screen, checks auth state via onLogin event)
  → AuthService.tryRestoreSession() (Supabase session auto-restore via sessionStatus flow)
  → On login: navigates to WebViewActivity → WebViewBridge injects tokens
  → WebViewBridge injects tokens via JS property getter before page load
  → Web app signals "app-ready" → splash overlay fades out
```

### Service Layer (`Android/.../services/`)

Uses **Service Locator pattern** via `ServiceManager` singleton. Same pattern as iOS.

- **AuthService** — Supabase Auth (email/password, Google OAuth via PKCE). Publishes `onLogin`/`onLogout` events. Deep link scheme: `capital-wizard-android://auth/callback`. Session status observed via `auth.sessionStatus` coroutine flow. Coroutine scope: `SupervisorJob() + Dispatchers.Main`.
- **DeepLinkService** — mirror of the iOS service: app links (`https://app.capital-wizard.com/<path>`, verified via `assetlinks.json`) plus a `capital-wizard-android://open?path=…` fallback, stashed until the WebView can show them. Links enter through `LoginActivity` (the launcher, `singleTask`), which offers the URI to the router before `AuthService`; `navigateToMain()` uses `CLEAR_TOP | SINGLE_TOP` so a link arriving while the app is backgrounded reuses the running `WebViewActivity` (via `onNewIntent`) instead of stacking a second one. Intent filters have no negation, so the manifest carries an allow-list of route prefixes mirroring the iOS association file's exclude rules — keep them in step. See `docs/deep-links.md` in the web repo.

### Event System (`Android/.../utils/Event.kt`)

Same C#-style observer pattern as iOS. `Event<T>` with `subscribe`/`unsubscribe` and `+=`/`-=` operators. `EventCallback<T>` wraps listener functions.

### Web-Native Bridge (`Android/.../webview/WebViewBridge.kt`)

- **Native → Web:** Token injection via JS property getter (`injectAuthScript()`), native identifier via `window.__capital_wizard_native = { platform: 'android' }`
- **Web → Native:** `@JavascriptInterface` on `"androidCW"` channel, JSON message parsing with `type` field
- **Message types:** `"system"` (api-ready, app-ready, logout), `"auth"`
- **Base URL:** `https://capital-wizard.com/`
- Splash reveal triggered by `"app-ready"` event with 15s timeout fallback

### UI (`Android/.../ui/`)

- **Auth screens:** `LoginActivity` with email/password, Google OAuth, splash screen (1.5s delay), email confirmation flow. Deep link handling for OAuth callbacks.
- **WebView:** `WebViewActivity` — full-screen WebView with pull-to-refresh (`SwipeRefreshLayout`), splash overlay animation (fade-out + scale), edge-to-edge layout with `WindowInsets`, back button WebView navigation, external links open in system browser, crash recovery via `RenderProcessGone`.
- **Theme:** Dark theme matching iOS (Material Components DayNight NoActionBar), transparent status/nav bars, custom splash theme.
- **All layouts are XML** with ViewBinding (`activity_login.xml`, `activity_webview.xml`)

### Android Manifest

- `INTERNET` permission
- `LoginActivity` — launcher, exported, handles `capital-wizard-android://auth/callback` deep links, the `capital-wizard-android://open?path=…` routing fallback, and the `autoVerify` app-link filter for `https://app.capital-wizard.com` route prefixes
- `WebViewActivity` — not exported, handles orientation + screen size config changes
- Clear-text traffic disabled (HTTPS only)

### Testing

No tests currently exist. `AndroidJUnitRunner` is declared as test instrumentation runner in build config.
