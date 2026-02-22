//
//  ApplicationCenter.swift
//  capital-wizard-ios
//
//  Created by Roman on 07.02.2026.
//

import UIKit

class ApplicationCenter: NSObject, Application {
    var id:       String   = "app-center"
    var name:     String   = "Application Center"
    var tabIcon:  UIImage? = UIImage(systemName: "magnifyingglass")
    var bigIcon:  UIImage? = UIImage(systemName: "magnifyingglass")?.withRenderingMode(.alwaysTemplate)
    var tagIndex: Int      = -1

    var sideBarPriority:  Priority = .baseApplication
    var hasNavigationBar: Bool                = true
    var layout:           ApplicationUILayout = [ .all ]

    private var selectedApplication: Application?

    private lazy var applicationService: ApplicationService?           = ServiceManager.shared.getService()
    private lazy var windowsService:     WindowsService?               = ServiceManager.shared.getService()

    private lazy var colorChangeEvent:  EventCallback<ColorScheme> = EventCallback(onColorSchemeChanged)

    var rootController: UIViewController?
    var controller: ApplicationViewController?

    private var appCenterController: ApplicationCenterController? {
        controller as? ApplicationCenterController
    }

    private var applications: Array<Application> = []

    private var defaultApplicationsId: Array<String> = []

    func awake() {
        controller = ApplicationCenterController()
        controller?.application = self

        appCenterController?.delegate = self
    }

    func start() {
        windowsService?.onColorSchemeChanged += colorChangeEvent
    }

    func stop() {
        windowsService?.onColorSchemeChanged -= colorChangeEvent
    }

    func resume(layout: ApplicationUILayout?) {
    }

    func pause() {
    }

    private var applicationsAmount: Int {
        applicationService?.applicationsAmount ?? 0
    }
    
    func startDynamiccApplications() {
        guard let appStore = applicationService?.appStore else {
            return
        }
        
        var applications: Array<Application> = []
        
        if let assetsData = appStore.getAppData(for: "assets") {
            var assets: Application = WebViewApplication(appData: assetsData, hasNavigationBar: false, tagIndex: applicationsAmount)
            applicationService?.addApplication(application: &assets, tag: applicationsAmount, shouldAddTab: false)
            applications.append(assets)
        }
        
        if let peopleData = appStore.getAppData(for: "people") {
            var people: Application = WebViewApplication(appData: peopleData, hasNavigationBar: false, tagIndex: applicationsAmount)
            applicationService?.addApplication(application: &people, tag: applicationsAmount, shouldAddTab: false)
            applications.append(people)
        }
        
        if let settingsData = appStore.getAppData(for: "settings") {
            var settings: Application = WebViewApplication(appData: settingsData, hasNavigationBar: false, tagIndex: applicationsAmount)
            applicationService?.addApplication(application: &settings, tag: applicationsAmount, shouldAddTab: false)
            applications.append(settings)
        }
        
        appCenterController?.data = applications
    }

    func setSelected(applications: Array<Application?>) {
        if UIDevice.current.userInterfaceIdiom == .pad {
            appCenterController?.selectedApplications = applications
        } else {
            appCenterController?.selectedApplications = [selectedApplication]
        }
    }

    func showApplication(_ application: Application) {
        if UIDevice.current.userInterfaceIdiom == .phone, let selectedApplication = selectedApplication {
            if application.id == selectedApplication.id {
                return
            }
            windowsService?.remove(application: selectedApplication)
        } else if UIDevice.current.userInterfaceIdiom == .pad, applications.count >= ApplicationService.defaultAppAmount {
            if !applications.contains(where: { $0.id == application.id }) {
                let application = applications.removeFirst()
                windowsService?.remove(application: application)
            }
        }

        selectedApplication = application

        guard UIDevice.current.userInterfaceIdiom == .phone ||
              (UIDevice.current.userInterfaceIdiom == .pad && !applications.contains(where: { $0.id == application.id })) else {
            return
        }
        windowsService?.add(application: application)
        applications.append(application)
    }

    func hideApplication(_ application: Application) {
        if UIDevice.current.userInterfaceIdiom == .phone, let selectedApplication = selectedApplication {
            windowsService?.remove(application: selectedApplication)
        } else if UIDevice.current.userInterfaceIdiom == .pad {
            guard let index = applications.firstIndex(where: { $0.id == application.id }) else {
                return
            }
            let application = applications.remove(at: index)
            windowsService?.remove(application: application)
        }
    }

    private func onColorSchemeChanged(_ scheme: ColorScheme) {
        appCenterController?.onColorSchemeChanged(scheme)
    }
}

extension ApplicationCenter: ApplicationCenterControllerDelegate {
    func onAppChosen(_ application: Application) {
        applicationService?.switchTo(application: application)
    }
}
