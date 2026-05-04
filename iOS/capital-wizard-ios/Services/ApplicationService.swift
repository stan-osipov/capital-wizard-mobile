//
//  ApplicationService.swift
//  capital-wizard-ios
//
//  Created by Roman on 07.02.2026.
//

import Foundation
import UIKit

struct ApplicationUILayout: OptionSet {
    let rawValue: Int

    static let left       = ApplicationUILayout(rawValue: 1 << 0)
    static let right      = ApplicationUILayout(rawValue: 1 << 1)
    static let wide       = ApplicationUILayout(rawValue: 1 << 2)

    static let background = ApplicationUILayout(rawValue: 1 << 3)

    static let all: ApplicationUILayout = [.left, .right, .wide]

    static func layout(from string: String) -> ApplicationUILayout {
        if string == "w" {
            return .wide
        } else if string == "l" {
            return .left
        } else if string == "r" {
            return .right
        } else {
            return .all
        }
    }

    var debug: String {
        switch self {
        case .left:  return "left"
        case .right: return "right"
        case .wide:  return "wide"
        case .all:   return "all"
        case .background: return "backgroud"
        default:
            return ""
        }
    }
}

enum Priority {
    case baseApplication
    case staticApplication
    case dynamicApplication
}

protocol ApplicationUIData: AnyObject {
    var tabIcon: UIImage? { get }
    var bigIcon: UIImage? { get }

    var hasNavigationBar: Bool { get }
    var tagIndex:         Int  { get }

    var layout: ApplicationUILayout { get }
}

/// Base protocol for Applications.
protocol Application: AnyObject {
    var id:               String   { get }
    var name:             String   { get }
    var tabIcon:          UIImage? { get }
    var bigIcon:          UIImage? { get }
    var hasNavigationBar: Bool     { get }
    var tagIndex:         Int      { get set }

    var sideBarPriority:  Priority { get }

    var layout: ApplicationUILayout { get }

    /// Main view controller for application.
    var controller: ApplicationViewController? { get }

    /// Root view controller for application,
    /// can be `controller` itself or `UINavigationController` that containts `controller`.
    var rootController: UIViewController? { get set }

    /// Awake application. Initial awake of the application
    func awake()

    /// Start application method
    func start()

    /// Stops application, and clear all data for it.
    func stop()

    /// Pause application work, or move it into the collapsed(background) mode if can.
    func pause()

    /// Resume application from paused state
    func resume(layout: ApplicationUILayout?)
}

/// Delegate that inform listener that another tab bar element was selected.
protocol ApplicationsWindowsServiceDelegate {
    func onLayoutChanged(to layout: ViewUILayout, deSelected: Array<String>)
    func onCloseApplication(id: String, layout: ViewUILayout)
}

/// Applications service, manage all applications.
class ApplicationService: Service {

    var onApplicationsDidStart: Event<Void> = Event()

    private var applications: Dictionary<String, Application> = [:]
    private lazy var windowsService: WindowsService?  = ServiceManager.shared.getService()

    init() {
        /// Subscribe to auth events.
        /// We start applications when user login and stop them at logout.
        let authService: AuthService? = ServiceManager.shared.getService()
        authService?.onLogin  += EventCallback(startApplications)
        authService?.onLogout += EventCallback(stopAndClearApplications)
    }

    func startApplications() {
        SplashAnimationView.postStatus("Starting application…")

        // Single WebView loading the root URL — the web app handles its own navigation
        let appData = ApplicationData(id: "main", name: "Capital Wizard", apiName: "", baseUrl: "")
        let mainApp = WebViewApplication(appData: appData, hasNavigationBar: false, tagIndex: 0)
        mainApp.awake()
        mainApp.start()
        applications[mainApp.id] = mainApp

        // Present the WebView full-screen
        if let controller = mainApp.controller {
            windowsService?.mainController = controller
        }

        onApplicationsDidStart.invoke(())
    }

    func stopAndClearApplications() {
        applications.values.forEach { $0.stop() }
        applications.removeAll()
        windowsService?.mainController = nil

        // Clear WebView cookies and cache on logout
        WebViewApplication.cleareAllData()
    }

    // MARK: - Stubs (kept so unused files compile)

    static let defaultAppAmount = 4
    var applicationsAmount = 0
    var appStore: ApplicationStore = ApplicationStore()

    func addApplication<T: Application>(application: inout T, tag: Int, shouldAddTab: Bool = true, isColored: Bool = false) {}
    func switchTo(application: Application, for path: WindowTransitionPath = .right) {}
}
