//
//  PushService.swift
//  capital-wizard-ios
//

import UIKit
import SafariServices
import UserNotifications

/// Everything the web app needs to store one row in `push_devices`.
struct PushRegistration {
    let token: String
    /// `sandbox` or `production` — which APNs host will accept this token.
    let environment: String
    let bundleId: String
    let deviceName: String
    let appVersion: String
}

/// Owns this device's APNs registration.
///
/// The shell never decides *when* to ask: the web app does, by posting
/// `request-push-token` once someone is signed in. That keeps the permission
/// prompt away from the launch screen, where it would land before anyone has
/// seen what the app is for — and iOS only ever asks once, so a refusal there
/// would be permanent.
///
/// The answer is always sent back, token or not, so the web side can stop
/// waiting either way.
class PushService: NSObject, Service {

    /// Fires with the registration, or `nil` when permission was refused or APNs
    /// declined to issue a token.
    var onRegistration: Event<PushRegistration?> = Event()

    private(set) var registration: PushRegistration?

    /// Why the last answer carried no token: `denied` (the user said no) or
    /// `error` (APNs/authorization failed). Nil after a success. Rides along
    /// with the bridge answer so the web app can record a real refusal in its
    /// decline log without ever mistaking an outage for one.
    private(set) var lastFailureReason: String?

    /// True between a web request and APNs answering, so a second request while
    /// the first is in flight doesn't queue a duplicate prompt.
    private var requestInFlight = false

    /// Fired when a tapped notification carries an external page. Subscribers
    /// that can show it immediately call `consumePendingExternalURL()`; ignoring
    /// the event leaves it stashed, exactly like DeepLinkService.
    var onExternalURL: Event<Void> = Event()

    private var pendingExternalURL: URL?

    /// Fired when a tapped notification carried a `sendId` — the click-tracking
    /// handle minted by the send-push function. Subscribers with a live bridge
    /// call `consumePendingOpenReports()` and forward them to the web app,
    /// which reports them via its authenticated RPC; ignoring the event leaves
    /// them stashed for the app-ready flush, exactly like the external URL.
    var onOpenRecorded: Event<Void> = Event()

    /// A queue, not a single slot: taps can outpace the bridge (tap → app warm
    /// but mid-reload → background → tap again), and dropping the older id
    /// would undercount the send it belonged to.
    private var pendingOpenSendIds: [String] = []

    /// Ceiling on the stash. Anything past this is not a person tapping
    /// notifications, and the web side caps what it relays at the same order.
    private static let pendingOpenReportsMax = 20

    func postInit() {
        // Must be set before the app finishes launching, or a notification that
        // launched the app is delivered to nobody.
        UNUserNotificationCenter.current().delegate = self

        // Backstop for the case the WebView never reports ready — a signed-out
        // user taps a link and lands on the auth screen, which has no bridge to
        // flush the stash. Consuming is one-shot, so whichever path gets there
        // first wins and the other finds nothing.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(flushPendingExternalURL),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    /// Returns the stashed page and clears it, so a link is only ever opened
    /// once — a later app-ready must not re-open a page already shown.
    func consumePendingExternalURL() -> URL? {
        guard let url = pendingExternalURL else { return nil }
        pendingExternalURL = nil
        return url
    }

    /// Returns the stashed tap ids and clears them, so a tap is only ever
    /// reported once — a later app-ready must not re-send ids already handed
    /// over (the server dedups per account regardless, but the bridge should
    /// not rely on that).
    func consumePendingOpenReports() -> [String] {
        let ids = pendingOpenSendIds
        pendingOpenSendIds = []
        return ids
    }

    /// Stashes the click-tracking id of a tapped notification and announces it.
    /// The value arrived over the network, so it is capped, never parsed — the
    /// web side validates the shape before its RPC ever sees it.
    private func recordOpen(sendId: String) {
        guard !sendId.isEmpty, sendId.count <= 64 else { return }
        guard pendingOpenSendIds.count < Self.pendingOpenReportsMax else { return }

        CWLog.shared.log("Notification tap recorded (send …\(sendId.suffix(8)))", category: "Push")
        pendingOpenSendIds.append(sendId)
        onOpenRecorded.invoke(())
    }

    @objc private func flushPendingExternalURL() {
        // Late enough that a cold launch has finished swapping in its real root
        // view controller. Presenting before that is what left the app stuck
        // behind a Safari sheet with its WebView never reporting ready.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let url = self?.consumePendingExternalURL() else { return }
            Self.presentExternal(url)
        }
    }

    // MARK: - Web-driven registration

    /// Answers the web app's `request-push-token`.
    func requestRegistration() {
        // Already registered this launch — answer straight away rather than
        // waiting on another APNs round trip.
        if let registration = registration {
            onRegistration.invoke(registration)
            return
        }
        guard !requestInFlight else { return }
        requestInFlight = true

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            guard let self = self else { return }

            if let error = error {
                CWLog.shared.log("Notification authorization failed: \(error.localizedDescription)", category: "Push")
                self.lastFailureReason = "error"
                self.finish(with: nil)
                return
            }
            guard granted else {
                CWLog.shared.log("Notifications refused by the user", category: "Push")
                self.lastFailureReason = "denied"
                self.finish(with: nil)
                return
            }

            // registerForRemoteNotifications is UIKit and main-thread only; the
            // authorization callback arrives on an arbitrary queue.
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    // MARK: - Permission status

    /// The OS notification permission as it stands right now, in the vocabulary
    /// the web app reads (`granted` / `denied` / `undetermined`).
    ///
    /// Answers a question the `push_devices` registry cannot: a row stays alive
    /// after the user switches notifications off in Settings, so every send is
    /// still accepted by APNs and then quietly discarded by the phone. Only
    /// UNUserNotificationCenter knows, and only when asked.
    ///
    /// `.provisional` and `.ephemeral` count as granted — both deliver, just
    /// more quietly, and telling somebody their notifications are off when they
    /// are arriving would be wrong.
    func readPermission(_ completion: @escaping (String) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let value: String
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                value = "granted"
            case .denied:
                value = "denied"
            case .notDetermined:
                value = "undetermined"
            @unknown default:
                value = "undetermined"
            }
            DispatchQueue.main.async { completion(value) }
        }
    }

    /// Opens this app's page in Settings, where notifications can be switched
    /// back on.
    ///
    /// The only way out of `denied`: iOS asks for notification permission
    /// exactly once per install, so once refused there is no prompt left to
    /// show and the fix has to happen outside the app.
    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        DispatchQueue.main.async {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - APNs callbacks (forwarded by AppDelegate)

    func didRegister(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        let device = UIDevice.current
        let info = Bundle.main.infoDictionary

        let registration = PushRegistration(
            token: token,
            environment: Self.apnsEnvironment(),
            bundleId: Bundle.main.bundleIdentifier ?? "",
            deviceName: device.name,
            appVersion: info?["CFBundleShortVersionString"] as? String ?? ""
        )
        self.registration = registration
        self.lastFailureReason = nil

        CWLog.shared.log("APNs token registered (\(registration.environment), …\(token.suffix(8)))", category: "Push")
        finish(with: registration)
    }

    func didFailToRegister(error: Error) {
        CWLog.shared.log("APNs registration failed: \(error.localizedDescription)", category: "Push")
        lastFailureReason = "error"
        finish(with: nil)
    }

    private func finish(with registration: PushRegistration?) {
        requestInFlight = false
        DispatchQueue.main.async { [weak self] in
            self?.onRegistration.invoke(registration)
        }
    }

    // MARK: - Environment

    /// Which APNs host will accept this device's token.
    ///
    /// A token minted against the development gateway is rejected by the
    /// production one and vice versa, so this has to be right or every send
    /// comes back `BadDeviceToken`.
    ///
    /// Debug builds are always development. For everything else the embedded
    /// provisioning profile is the authority — an ad-hoc or development-signed
    /// Release build is still sandbox, which a bare `#if DEBUG` would miss.
    static func apnsEnvironment() -> String {
        #if DEBUG
        return "sandbox"
        #else
        return provisionedApsEnvironment() == "development" ? "sandbox" : "production"
        #endif
    }

    /// Reads `aps-environment` out of `embedded.mobileprovision`. The file is a
    /// CMS blob with a plain-text plist inside it, so we slice the plist out and
    /// parse that rather than trying to decode the signature around it.
    private static func provisionedApsEnvironment() -> String? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              // isoLatin1 maps every byte to a character, so the binary wrapper
              // can't fail the decode the way UTF-8 would.
              let text = String(data: data, encoding: .isoLatin1),
              let start = text.range(of: "<?xml"),
              let end = text.range(of: "</plist>") else {
            return nil
        }

        let plist = String(text[start.lowerBound..<end.upperBound])
        guard let keyRange = plist.range(of: "<key>aps-environment</key>"),
              let openTag = plist.range(of: "<string>", range: keyRange.upperBound..<plist.endIndex),
              let closeTag = plist.range(of: "</string>", range: openTag.upperBound..<plist.endIndex) else {
            return nil
        }
        return String(plist[openTag.upperBound..<closeTag.lowerBound])
    }
}

// MARK: - Presentation & taps

extension PushService: UNUserNotificationCenterDelegate {

    /// Show the banner even while the app is in the foreground. The WebView
    /// fills the screen and has no in-app notification surface of its own, so
    /// suppressing it would just lose the message.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    /// A tap.
    ///
    /// The payload carries EITHER a `route` or a `url`, never both, and the two
    /// go to deliberately different places:
    ///
    ///  - `route` is an in-app screen, handed to DeepLinkService so the existing
    ///    stash-then-consume machinery places it (the WebView may not exist yet
    ///    on a cold start, and that path is already solved).
    ///  - `url` is somewhere else on the web, opened in a Safari view controller
    ///    — a separate surface that cannot see the app's session. Routing it into
    ///    the main WebView instead would hand an outside page a signed-in origin.
    ///
    /// The server already decided which is which; the shell must not re-classify.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        defer { completionHandler() }

        let userInfo = response.notification.request.content.userInfo

        // Every tap is counted, whatever it opens — the click metric must not
        // depend on whether the composer attached a link.
        if let sendId = userInfo["sendId"] as? String {
            recordOpen(sendId: sendId)
        }

        if let route = userInfo["route"] as? String, !route.isEmpty {
            CWLog.shared.log("Notification tapped → \(route)", category: "Push")
            let deepLinkService: DeepLinkService? = ServiceManager.shared.getService()
            deepLinkService?.handle(routePath: route)
            return
        }

        if let link = userInfo["url"] as? String, !link.isEmpty {
            openExternal(link)
        }
    }

    /// Stashes an external page rather than showing it on the spot.
    ///
    /// A tap can launch the app from cold, and presenting a modal *during* that
    /// launch is what leaves it wedged: the sheet goes up over a root view
    /// controller that is still being swapped in, and the WebView underneath —
    /// now covered — never renders, so it never reports `app-ready` and the
    /// splash waits forever. Same reasoning as DeepLinkService: hold it, and let
    /// whoever becomes ready first consume it.
    ///
    /// https is re-checked even though the server enforced it: this value
    /// arrived over the network, and `SFSafariViewController` traps on a
    /// non-http(s) URL rather than declining politely.
    private func openExternal(_ link: String) {
        guard let url = URL(string: link), url.scheme?.lowercased() == "https" else {
            CWLog.shared.log("Notification carried an unusable url — ignoring", category: "Push")
            return
        }

        CWLog.shared.log("Notification tapped → external \(url.host ?? "")", category: "Push")
        pendingExternalURL = url
        onExternalURL.invoke(())
    }

    /// Shows an external page in an in-app Safari view controller, tinted with
    /// the user's chosen accent so it still feels like our app. Call only once
    /// the app is actually up — see `openExternal`.
    static func presentExternal(_ url: URL) {
        DispatchQueue.main.async {
            guard let presenter = topViewController() else { return }

            // Already showing something modal (including a previous Safari
            // sheet) — presenting on top would stack browsers.
            guard !(presenter is SFSafariViewController) else { return }

            let isDark = presenter.traitCollection.userInterfaceStyle == .dark
            let safari = SFSafariViewController(url: url)
            safari.preferredControlTintColor = AppColors.webAccent(isDark: isDark).accent
            safari.dismissButtonStyle = .close
            presenter.present(safari, animated: true)
        }
    }

    /// Whatever is actually on screen right now. A tap can land while a modal is
    /// already up (the app may have been mid-anything when it was backgrounded),
    /// and presenting on a covered controller silently does nothing.
    static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first

        var top = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
            ?? scene?.windows.first?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
