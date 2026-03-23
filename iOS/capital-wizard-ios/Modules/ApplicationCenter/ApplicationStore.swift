//
//  ApplicationStore.swift
//  capital-wizard-ios
//
//  Created by Roman on 07.02.2026.
//

import UIKit

enum ApplicationType {
    case web
    case native
    case iFrameWeb
}

struct ApplicationData {
    var id:      String
    var name:    String
    var tabIcon: UIImage?
    var bigIcon: UIImage?
    
    var baseUrl: String
    
    var type: ApplicationType = .web
    
    var sidebarPriority: Priority = .dynamicApplication
    var layout:          ApplicationUILayout  = [ .all ]
    
    var orientation: UIInterfaceOrientationMask = .all
    
    init(application: Application) {
        self.id       = application.id
        self.name     = application.name
        self.tabIcon  = application.tabIcon
        self.bigIcon  = application.bigIcon
        self.type     = .native
        self.layout   = application.layout
        self.baseUrl  = ""
    }
    
    init(id: String, name: String, tabIcon: UIImage? = nil, bigIcon: UIImage? = nil, apiName: String, baseUrl: String, orientation: UIInterfaceOrientationMask) {
        self.id          = id
        self.name        = name
        self.tabIcon     = tabIcon
        self.bigIcon     = bigIcon
        self.baseUrl     = baseUrl
        self.orientation = orientation
    }
    
    init(id: String, name: String, tabIcon: UIImage? = nil, bigIcon: UIImage? = nil, apiName: String, baseUrl: String) {
        self.id      = id
        self.name    = name
        self.tabIcon = tabIcon
        self.bigIcon = bigIcon
        self.baseUrl = baseUrl
    }
}

// (Roman) TODO: Move to separete class.
class ApplicationStore: NSObject {
    
    /// (Roman) TODO: Right now we just store all apps in dict, but in future this dict will only be used as cache
    ///             and we will get all app from app store from our server.
    var applications: Dictionary<String, ApplicationData> = [:]
    
    var dynamicWebbApps: Dictionary<String, ApplicationData> = [:]
    
    override init() {
        super.init()
        
        initialLoad()
    }
    
    
    func getAppData(for id: String) -> ApplicationData? {
        // (Roman) TODO: Check if we dont have app in cached get it from server
        
        return applications[id]
    }
    
    func initialLoad() {
        // (Roman) TODO: Load from server

        let dashboardIcon    = UIImage(systemName: "rectangle.grid.2x2")
        let dashboardBigIcon = UIImage(systemName: "rectangle.grid.2x2")?.withRenderingMode(.alwaysTemplate)
        var dashboard        = ApplicationData(id: "dashboard",
                                               name: "Dashboard",
                                               tabIcon: dashboardIcon,
                                               bigIcon: dashboardBigIcon,
                                               apiName: "",
                                               baseUrl: "dashboard")
        dashboard.sidebarPriority = .staticApplication

        let transactionsIcon    = UIImage(systemName: "banknote")
        let transactionsBigIcon = UIImage(systemName: "banknote")?.withRenderingMode(.alwaysTemplate)
        var transactions        = ApplicationData(id: "transactions",
                                                  name: "Transactions",
                                                  tabIcon: transactionsIcon,
                                                  bigIcon: transactionsBigIcon,
                                                  apiName: "transactions",
                                                  baseUrl: "transactions")
        transactions.sidebarPriority = .staticApplication

        let peopleIcon    = UIImage(systemName: "person.3")
        let peopleBigIcon = UIImage(systemName: "person.3")?.withRenderingMode(.alwaysTemplate)
        var people        = ApplicationData(id: "people",
                                            name: "People",
                                            tabIcon: peopleIcon,
                                            bigIcon: peopleBigIcon,
                                            apiName: "",
                                            baseUrl: "people")
        people.sidebarPriority = .staticApplication

        let assetsIcon    = UIImage(systemName: "briefcase")
        let assetsBigIcon = UIImage(systemName: "briefcase")?.withRenderingMode(.alwaysTemplate)
        let assets        = ApplicationData(id: "assets",
                                            name: "Assets",
                                            tabIcon: assetsIcon,
                                            bigIcon: assetsBigIcon,
                                            apiName: "",
                                            baseUrl: "assets")

        let profileIcon    = UIImage(systemName: "person.crop.circle")
        let profileBigIcon = UIImage(systemName: "person.crop.circle")?.withRenderingMode(.alwaysTemplate)
        var profile        = ApplicationData(id: "profile",
                                             name: "Profile",
                                             tabIcon: profileIcon,
                                             bigIcon: profileBigIcon,
                                             apiName: "",
                                             baseUrl: "profile")
        profile.sidebarPriority = .dynamicApplication

        let settingsIcon    = UIImage(systemName: "gearshape")
        let settingsBigIcon = UIImage(systemName: "gearshape")?.withRenderingMode(.alwaysTemplate)
        let settings        = ApplicationData(id: "settings",
                                              name: "Settings",
                                              tabIcon: settingsIcon,
                                              bigIcon: settingsBigIcon,
                                              apiName: "",
                                              baseUrl: "settings")

        applications[dashboard.id]    = dashboard
        applications[transactions.id] = transactions
        applications[people.id]       = people
        applications[assets.id]       = assets
        applications[profile.id]      = profile
        applications[settings.id]     = settings
    }
}
