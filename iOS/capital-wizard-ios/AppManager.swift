//
//  AppManager.swift
//  capital-wizard-ios
//
//  Created by Roman on 07.02.2026.
//
import UIKit

class AppManager {
    init() {
        ServiceManager.shared.register(AuthService())
        ServiceManager.shared.register(ApplicationService())
        ServiceManager.shared.register(DeepLinkService())
        ServiceManager.shared.register(PushService())
    }

    func postInit() {
        SplashAnimationView.postStatus("Initializing services…")

        let windowsService: WindowsService? = ServiceManager.shared.getService()
        windowsService?.postInit()

        // Claims the notification-centre delegate. Has to happen during launch:
        // a notification that started the app is delivered once, immediately,
        // and a delegate set later never sees it.
        let pushService: PushService? = ServiceManager.shared.getService()
        pushService?.postInit()

        let authService: AuthService? = ServiceManager.shared.getService()
        authService?.postInit()
    }
}

protocol ErrorMessage {
    var description: String { get }
}
