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
    /// as a browsing-web `NSUserActivity`, the custom scheme as a URL context.
    private func captureLaunchLinks(_ connectionOptions: UIScene.ConnectionOptions) {
        let deepLinkService: DeepLinkService? = ServiceManager.shared.getService()

        for activity in connectionOptions.userActivities
        where activity.activityType == NSUserActivityTypeBrowsingWeb {
            if deepLinkService?.handle(url: activity.webpageURL) == true { return }
        }

        for context in connectionOptions.urlContexts {
            if deepLinkService?.handle(url: context.url) == true { return }
        }
    }

    /// Universal link tapped while the app is already running.
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb else { return }
        let deepLinkService: DeepLinkService? = ServiceManager.shared.getService()
        deepLinkService?.handle(url: userActivity.webpageURL)
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }

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

