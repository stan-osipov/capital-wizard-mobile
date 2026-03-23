# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Structure

Monorepo with platform-specific native apps:

```
iOS/          — Xcode project (Swift/UIKit)
Android/      — Gradle project (Kotlin)
```

Both apps are **hybrid native wrappers** — native authentication wrapping a WebView that loads `capital-wizard.com`. Post-login, auth tokens are injected into the web context via JavaScript bridge.

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

Uses **Service Locator pattern** via `ServiceManager.shared`. Services register at startup in `AppManager.init()`.

- **AuthService** — Supabase Auth (email/password, Google OAuth via PKCE). Publishes `onLogin`/`onLogout` events. OAuth callback URL scheme: `capital-wizard-ios://auth/callback`.
- **ApplicationService** — Creates/manages `Application` instances. Currently instantiates a single `WebViewApplication`.
- **WindowsService** — Window management, root VC transitions (auth ↔ main app), color scheme (dark/light/system) with persistence via UserDefaults.

### Event System (`iOS/capital-wizard-ios/Utils/Event.swift`)

C#-style observer pattern. Services communicate via `Event<T>` with `+=`/`-=` subscription operators and `.invoke()`. This is the primary decoupling mechanism between services.

### Web-Native Bridge (`iOS/capital-wizard-ios/Modules/WebView/`)

- **Native → Web:** Token injection, color scheme updates via `WKUserScript` / `evaluateJavaScript`
- **Web → Native:** `WKScriptMessageHandler` on channel `"iosCW"`, JSON message parsing
- **WebApiCalls/WebApiResponses:** Typed protocol-based communication
- Shared `WKProcessPool` across WebViews for cookie sharing

### Application Protocol (`iOS/capital-wizard-ios/Modules/`)

`Application` protocol defines lifecycle: `awake()`, `start()`, `stop()`, `pause()`, `resume()`. Applications have priority levels (base/static/dynamic) and layout options (left/right/wide/background) designed for future multi-app and iPad split-view support. Currently only `WebViewApplication` is active.

### UI (`iOS/capital-wizard-ios/UI/`)

- **Auth screens:** `LoginViewController`, `SignUpViewController`, `ResetPasswordViewController` with custom components (`GradientButton`, `ValidatedTextField`, `AnimatedCardView`)
- **Navigation:** `TabBarController` and `SidebarController`/`SplitViewController` stubs for future multi-app layout
- **All UI is programmatic** (no SwiftUI), with `Main.storyboard` only for initial launch

### Utils

- `ServiceManager` — singleton service registry with generic `register<T>`/`getService<T>`
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
**Target/Compile SDK:** 35 (Android 15) | **Min SDK:** 26 (Android 8.0) | **Java/Kotlin:** 17

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
- `LoginActivity` — launcher, exported, handles `capital-wizard-android://auth/callback` deep links
- `WebViewActivity` — not exported, handles orientation + screen size config changes
- Clear-text traffic disabled (HTTPS only)

### Testing

No tests currently exist. `AndroidJUnitRunner` is declared as test instrumentation runner in build config.
