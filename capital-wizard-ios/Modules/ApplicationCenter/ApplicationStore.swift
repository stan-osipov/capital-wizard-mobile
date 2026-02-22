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
        
        let profileIcon    = UIImage(systemName: "house")
        let profileBigIcon = UIImage(named: "house")?.withRenderingMode(.alwaysTemplate)
        var profile        = ApplicationData(id: "profile",
                                             name: "Organizations",
                                             tabIcon: profileIcon,
                                             bigIcon: profileBigIcon,
                                             apiName: "",
                                             baseUrl: "profile")
        profile.sidebarPriority = .baseApplication

        let homeIcon    = UIImage(named: "icon_iframe_network_board_valu_portal_w")
        let homeBigIcon = UIImage(named: "icon_iframe_network_board_valu_portal_w")?.withRenderingMode(.alwaysTemplate)
        var home        = ApplicationData(id: "iframe_network_board_valu",
                                          name: "Portal",
                                          tabIcon: homeIcon,
                                          bigIcon: homeBigIcon,
                                          apiName: "",
                                          baseUrl: "https://portal.valu-social.com/")
        home.type   = .iFrameWeb

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

        let assetsIcon    = UIImage(systemName: "briefcase")
        let assetsBigIcon = UIImage(systemName: "briefcase")?.withRenderingMode(.alwaysTemplate)
        let assets        = ApplicationData(id: "assets",
                                            name: "Assets",
                                            tabIcon: assetsIcon,
                                            bigIcon: assetsBigIcon,
                                            apiName: "",
                                            baseUrl: "assets")
        
        let peopleIcon    = UIImage(systemName: "person.3")
        let peopleBigIcon = UIImage(systemName: "person.3")?.withRenderingMode(.alwaysTemplate)
        let people        = ApplicationData(id:"people",
                                            name: "People",
                                            tabIcon: peopleIcon,
                                            bigIcon: peopleBigIcon,
                                            apiName: "",
                                            baseUrl: "people")
        
        let settingsIcon    = UIImage(systemName: "gearshape")
        let settingsBigIcon = UIImage(systemName: "gearshape")?.withRenderingMode(.alwaysTemplate)
        var settings        = ApplicationData(id: "settings",
                                            name: "Settings",
                                            tabIcon: settingsIcon,
                                            bigIcon: settingsBigIcon,
                                            apiName: "",
                                            baseUrl: "settings")

        applications[profile.id]      = profile
        applications[dashboard.id]    = dashboard
        applications[transactions.id] = transactions
        applications[assets.id]       = assets
        applications[people.id]       = people
        applications[settings.id]     = settings
    }
}
