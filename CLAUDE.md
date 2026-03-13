# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

This is an Xcode project (no CocoaPods/Carthage). Open `capital-wizard-ios.xcodeproj` in Xcode.

```bash
# Build from command line
xcodebuild -project capital-wizard-ios.xcodeproj -scheme capital-wizard-ios -sdk iphonesimulator build

# Run tests
xcodebuild -project capital-wizard-ios.xcodeproj -scheme capital-wizard-ios -sdk iphonesimulator test
```

**Dependency:** Supabase Swift SDK via Swift Package Manager (resolved through Xcode project, no Package.swift at root).

## Architecture

**Hybrid native wrapper app** — native iOS authentication wrapping a WKWebView that loads `capital-wizard.com`. Post-login, auth tokens are injected into the web context via JavaScript bridge.

### Core Flow

```
AppDelegate → AppManager (registers services) → SceneDelegate (sets up window)
  → WindowsService (subscribes to auth events, manages root VC transitions)
  → AuthService.postInit() (checks existing Supabase session)
  → On login: ApplicationService.startApplications() → WebViewApplication loads web app
  → WebViewCommunication injects tokens via window.__capital_wizard.auth(data)
```

### Service Layer (`Services/`)

Uses **Service Locator pattern** via `ServiceManager.shared`. Services register at startup in `AppManager.init()`.

- **AuthService** — Supabase Auth (email/password, Google OAuth via PKCE). Publishes `onLogin`/`onLogout` events. OAuth callback URL scheme: `capital-wizard-ios://auth/callback`.
- **ApplicationService** — Creates/manages `Application` instances. Currently instantiates a single `WebViewApplication`.
- **WindowsService** — Window management, root VC transitions (auth ↔ main app), color scheme (dark/light/system) with persistence via UserDefaults.

### Event System (`Utils/Event.swift`)

C#-style observer pattern. Services communicate via `Event<T>` with `+=`/`-=` subscription operators and `.invoke()`. This is the primary decoupling mechanism between services.

### Web-Native Bridge (`Modules/WebView/`)

- **Native → Web:** Token injection, color scheme updates via `WKUserScript` / `evaluateJavaScript`
- **Web → Native:** `WKScriptMessageHandler` on channel `"iosCW"`, JSON message parsing
- **WebApiCalls/WebApiResponses:** Typed protocol-based communication
- Shared `WKProcessPool` across WebViews for cookie sharing

### Application Protocol (`Modules/`)

`Application` protocol defines lifecycle: `awake()`, `start()`, `stop()`, `pause()`, `resume()`. Applications have priority levels (base/static/dynamic) and layout options (left/right/wide/background) designed for future multi-app and iPad split-view support. Currently only `WebViewApplication` is active.

### UI (`UI/`)

- **Auth screens:** `LoginViewController`, `SignUpViewController`, `ResetPasswordViewController` with custom components (`GradientButton`, `ValidatedTextField`, `AnimatedCardView`)
- **Navigation:** `TabBarController` and `SidebarController`/`SplitViewController` stubs for future multi-app layout
- **All UI is programmatic** (no SwiftUI), with `Main.storyboard` only for initial launch

### Utils

- `ServiceManager` — singleton service registry with generic `register<T>`/`getService<T>`
- `Validator` — email and password form validation
- `Queue` — generic queue data structure
