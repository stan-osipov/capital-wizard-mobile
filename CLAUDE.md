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

**Dependencies:** Supabase Kotlin SDK, Ktor (HTTP client), Credential Manager (Google Sign-In).

### Core Flow

```
CapitalWizardApp (registers services) → MainActivity (checks auth state)
  → AuthService.tryRestoreSession() (checks existing Supabase session)
  → On login: navigates to WebViewActivity → WebViewBridge injects tokens
  → WebViewBridge injects tokens via window.__capital_wizard.auth(data)
```

### Service Layer (`Android/.../services/`)

Uses **Service Locator pattern** via `ServiceManager` singleton. Same pattern as iOS.

- **AuthService** — Supabase Auth (email/password, Google OAuth). Publishes `onLogin`/`onLogout` events. Deep link scheme: `capital-wizard-android://auth/callback`.

### Event System (`Android/.../utils/Event.kt`)

Same C#-style observer pattern as iOS. `Event<T>` with `subscribe`/`unsubscribe` and `invoke()`.

### Web-Native Bridge (`Android/.../webview/`)

- **Native → Web:** Token injection via `evaluateJavascript()`
- **Web → Native:** `@JavascriptInterface` on `"androidCW"` channel, JSON message parsing
- Same `window.__capital_wizard.auth(data)` / `window.__capital_wizard.system(data)` protocol as iOS

### UI (`Android/.../ui/`)

- **Auth screens:** `LoginActivity` with email/password and Google sign-in
- **WebView:** `WebViewActivity` — full-screen WebView with pull-to-refresh, splash screen
- **Theme:** Dark theme matching iOS dark mode colors
