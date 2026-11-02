//
//  SceneDelegate.swift
//  capital-wizard-ios
//
//  Created by Roman on 07.02.2026.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }

        let window = UIWindow(windowScene: windowScene)
        window.makeKeyAndVisible()

        let windowsService = WindowsService(window: window)
        ServiceManager.shared.register(windowsService)

        // Stash a launch-time link BEFORE postInit(), which kicks off the auth
        // check that ends up building the WebView. Getting there first is what
        // lets the very first page load land on the linked route instead of the
        // app root — no visible redirect.
        captureLaunchLinks(connectionOptions)

        let appDelegate = UIApplication.shared.delegate as? AppDelegate
        appDelegate?.appManager?.postInit()

        self.window = window
    }

    /// Picks up a link that launched the app from cold: a universal link arrives
    /// as a browsing-web `NSUserActivity`, the custom scheme as a URL context,
    /// and a shared statement as a `file:` one.
    private func captureLaunchLinks(_ connectionOptions: UIScene.ConnectionOptions) {
        let deepLinkService: DeepLinkService? = ServiceManager.shared.getService()

        for activity in connectionOptions.userActivities
        where activity.activityType == NSUserActivityTypeBrowsingWeb {
            if deepLinkService?.handle(url: activity.webpageURL) == true { return }
        }

        for context in connectionOptions.urlContexts {
            if takeSharedFile(context) { return }
            if deepLinkService?.handle(url: context.url) == true { return }
        }
    }

    /// A statement handed to us by another app: Share → Capital Wizard, or
    /// "Open in", for a PDF/XLS/CSV. Declared in `Info.plist` under
    /// `CFBundleDocumentTypes`, which is what makes iOS LAUNCH the app with the
    /// file — a share extension cannot do that, which is why pictures (whose
    /// route is the extension) reach the app by a different door and land in the
    /// AI chat instead.
    ///
    /// Filed in the same durable inbox the extension writes to, rather than
    /// handed straight to the WebView: this runs before sign-in and before the
    /// first page load on a cold launch, and the inbox is what survives that.
    ///
    /// Returns whether the context was ours, so the deep-link and OAuth legs are
    /// never offered a file URL.
    private func takeSharedFile(_ context: UIOpenURLContext) -> Bool {
        guard context.url.isFileURL else { return false }
        #if CODING_LAB
        // Coding Lab declares no document types, so nothing can arrive here —
        // and it has no import wizard to deliver a statement to.
        return true
        #else
        let url = context.url
        let openInPlace = context.options.openInPlace
        // Reading, base64-encoding and writing up to 10 MB — not on the thread
        // that is about to draw the first frame.
        DispatchQueue.global(qos: .userInitiated).async {
            let scoped = openInPlace && url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                try SharedImageInbox.save(fileAt: url)
                // Without `LSSupportsOpeningDocumentsInPlace` iOS hands us a COPY
                // in Documents/Inbox, and that copy is ours to clear up. A file
                // opened in place belongs to another app — leave it alone.
                if !openInPlace { try? FileManager.default.removeItem(at: url) }
                CWLog.shared.log("Shared file filed for import", category: "Share")
                // A WebView that is already up delivers it now. On a cold launch
                // there is no observer yet and `app-ready` picks it up instead.
                NotificationCenter.default.post(name: SharedImageInbox.didReceive, object: nil)
            } catch {
                CWLog.shared.log("Shared file refused: \(error)", category: "Share")
                DispatchQueue.main.async { self.reportSharedFileFailure() }
            }
        }
        return true
        #endif
    }

    #if !CODING_LAB
    /// The one thing that can go wrong often enough to need saying: the file is
    /// bigger than the bridge into the WebView can carry.
    private func reportSharedFileFailure() {
        guard let root = window?.rootViewController else { return }
        let alert = UIAlertController(title: L("share.file_error.title"),
                                      message: L("share.file_error.message"),
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L("share.file_error.ok"), style: .default))
        // Whatever is frontmost owns the screen — on a cold launch that is still
        // the splash, and presenting on top of its presentation would be lost.
        var presenter: UIViewController = root
        while let presented = presenter.presentedViewController { presenter = presented }
        presenter.present(alert, animated: true)
    }
    #endif

    /// Universal link tapped while the app is already running.
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb else { return }
        let deepLinkService: DeepLinkService? = ServiceManager.shared.getService()
        deepLinkService?.handle(url: userActivity.webpageURL)
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let context = URLContexts.first else { return }

        // A shared statement goes first: `DeepLinkService.appPath` declines a
        // `file:` scheme and AuthService would be handed it next, so checking
        // here is what keeps the file out of the auth leg.
        if takeSharedFile(context) { return }

        let url = context.url

        // Routing links and the OAuth callback share the custom scheme, split by
        // host (`open` vs `auth`). Offer it to the router first; anything it
        // declines is the auth leg and still reaches AuthService untouched.
        let deepLinkService: DeepLinkService? = ServiceManager.shared.getService()
        if deepLinkService?.handle(url: url) == true { return }

        let authService: AuthService? = ServiceManager.shared.getService()
        authService?.onOpenUrl(url: url)
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
        // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (ex. an incoming phone call).
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
        // Use this method to undo the changes made on entering the background.
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // Use this method to save data, release shared resources, and store enough scene-specific state information
        // to restore the scene back to its current state.
    }


}

