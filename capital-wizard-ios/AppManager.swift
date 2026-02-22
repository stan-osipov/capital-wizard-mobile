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
    }

    func postInit() {
        let windowsService: WindowsService? = ServiceManager.shared.getService()
        windowsService?.postInit()

        let authService: AuthService? = ServiceManager.shared.getService()
        authService?.postInit()
    }
}

protocol ErrorMessage {
    var description: String { get }
}
