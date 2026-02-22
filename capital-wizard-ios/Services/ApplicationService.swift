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

    static let defaultAppAmount = 4

    var applicationsAmount = 0
    var appStore: ApplicationStore

    private var appCenter: ApplicationCenter?

    init() {
        self.appStore = ApplicationStore()

        /// Subscribe to auth events.
        /// We start applications when user login and stop them at logout.
        let authService: AuthService? = ServiceManager.shared.getService()
        authService?.onLogin  += EventCallback(startApplications)
        authService?.onLogout += EventCallback(stopAndClearApplications)
    }

    func startApplications() {
        windowsService?.applicationsDelegate = self
        
        if let profileData = appStore.getAppData(for: "profile") {
            var profile: Application = WebViewApplication(appData: profileData, hasNavigationBar: false, tagIndex: applicationsAmount)
            addApplication(application: &profile, tag: applicationsAmount)
        }

        if let dashboardData = appStore.getAppData(for: "dashboard") {
            var dashboard: Application = WebViewApplication(appData: dashboardData, hasNavigationBar: false, tagIndex: applicationsAmount)
            addApplication(application: &dashboard, tag: applicationsAmount)
        }
        
        if let transactionsData = appStore.getAppData(for: "transactions") {
            var transactions: Application = WebViewApplication(appData: transactionsData, hasNavigationBar: false, tagIndex: applicationsAmount)
            addApplication(application: &transactions, tag: applicationsAmount)
        }
        
        var appCenter: ApplicationCenter = ApplicationCenter()
        addApplication(application: &appCenter, tag: applicationsAmount)
        self.appCenter = appCenter
        appStore.applications[appCenter.id] = ApplicationData(application: appCenter)
        
        appCenter.startDynamiccApplications()

        if let profile = getApplication(id: "profile") {
            switchTo(application: profile)
        } else {
            switchTo(application: appCenter)
        }

        onApplicationsDidStart.invoke(())
    }

    func stopAndClearApplications() {
        windowsService?.applicationsDelegate = nil

        applications.values.forEach { application in
            application.stop()
        }
        windowsService?.removeAllTabBars()
        applications.removeAll()

        applicationsAmount = .zero
    }

    func addApplication<T: Application>(application: inout T, tag: Int, shouldAddTab: Bool = true, isColored: Bool = false) {
        application.awake()

        if let controller = application.controller {
            if let tabBarItem = windowsService?.createTabController(hideNavigationBar: !application.hasNavigationBar,
                                                                    with: application.name,
                                                                    and: application.tabIcon,
                                                                    tag: tag,
                                                                    isColored: isColored,
                                                                    vc: controller) {
                application.rootController = tabBarItem
                application.tagIndex       = tag
                if shouldAddTab {
                    windowsService?.add(application: application)
                }
            }
        }
        applications[application.id] = application
        applicationsAmount += 1

        application.start()
    }

    func removeApplication(_ application: Application) {
        application.stop()
        applications.removeValue(forKey: application.id)
        applicationsAmount -= 1
        if UIDevice.current.userInterfaceIdiom == .pad {
            windowsService?.remove(application: application)
        }
    }
}

extension ApplicationService {
    func getApplication(id: String) -> Application? {
        return applications.values.first { $0.id == id }
    }

    private func showApplication(_ application: Application, with layout: ApplicationUILayout?) {
        if application.tagIndex >= ApplicationService.defaultAppAmount {
            appCenter?.showApplication(application)
        }
        windowsService?.show(application: application, with: layout)
    }

    func switchTo(application: Application, for path: WindowTransitionPath = .right) {
        showApplication(application, with: application.layout)
    }
}

extension ApplicationService: ApplicationsWindowsServiceDelegate {
    private func getApplication(byTag tag: Int) -> Application? {
        return applications.values.first { $0.tagIndex == tag }
    }

    private func pause(applications: Array<Application?>) {
        applications.forEach { application in
            application?.pause()
        }
    }

    private func resume(application: Application?, layout: ApplicationUILayout?) {
        application?.resume(layout: layout)
    }

    func onLayoutChanged(to layout: ViewUILayout, deSelected: Array<String>) {
        let deSelected = deSelected.map( { getApplication(id: $0 ) })
        pause(applications: deSelected)

        var selected: Array<Application?> = []

        switch layout {
        case .split(let left, let right):
            if let left = left {
                let application = getApplication(id: left.id)
                resume(application: application, layout: .left)
                selected.append(application)
            }
            if let right = right {
                let application = getApplication(id: right.id)
                resume(application: application, layout: .right)

                selected.append(application)
            }
        case .wide(let barItem):
            let application = getApplication(id: barItem.id)
            resume(application: application, layout: .wide)

            selected.append(application)
        case .none:
            return
        }

        appCenter?.setSelected(applications: selected)
    }

    func onCloseApplication(id: String, layout: ViewUILayout) {
        let application = getApplication(id: id)

        if let application = application, application.sideBarPriority == .dynamicApplication {
            appCenter?.hideApplication(application)
        }

        switch layout {
        case .wide(let item):
            guard item.id == id else {
                return
            }

            guard let appCenter = appCenter else {
                return
            }
            showApplication(appCenter, with: .wide)
        case .split(left: let left, right: let right):
            if let left = left, left.id == id, let right = right {
                guard let application = getApplication(id: right.id) else {
                    return
                }
                showApplication(application, with: .wide)
            }
            if let right = right, right.id == id, let left = left{
                guard let application = getApplication(id: left.id) else {
                    return
                }
                showApplication(application, with: .wide)
            }
        default:
            break
        }
    }
}
