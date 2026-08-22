//
//  AppDelegate.swift
//  capital-wizard-ios
//
//  Created by Roman on 07.02.2026.
//

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var appManager: AppManager?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Start capturing stdout/stderr early so the bug reporter can attach the
        // native log (see CWLog + WebViewCommunication `request-logs`).
        CWLog.shared.start()
        let device = UIDevice.current
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        CWLog.shared.log("App launch — v\(appVersion) (\(build)), iOS \(device.systemVersion), \(device.model)", category: "App")
        appManager = AppManager()
        return true
    }

    // MARK: - Remote notifications
    //
    // APNs only ever calls the app delegate, so both outcomes are handed
    // straight to PushService, which owns the registration and answers the web
    // app's request.

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let pushService: PushService? = ServiceManager.shared.getService()
        pushService?.didRegister(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        let pushService: PushService? = ServiceManager.shared.getService()
        pushService?.didFailToRegister(error: error)
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return .all
        }
        return .portrait
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }


}

