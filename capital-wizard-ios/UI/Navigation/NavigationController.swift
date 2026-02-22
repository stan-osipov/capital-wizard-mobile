//
//  NavigationController.swift
//  capital-wizard-ios
//
//  Created by Roman on 07.02.2026.
//

import UIKit

class NavigationController: UINavigationController {
    private lazy var windowService:      WindowsService? = ServiceManager.shared.getService()
    private lazy var colorChangeHandler: EventCallback   = EventCallback(onColorSchemeChanged(_:))
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        guard let scheme = windowService?.colorScheme else {
            return
        }
        
        windowService?.onColorSchemeChanged += colorChangeHandler
        
        let efftect: UIBlurEffect.Style = scheme.isDarkMode ? .systemChromeMaterialDark : .light
        
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = UIBlurEffect(style: efftect)

        navigationBar.backgroundColor                     = .clear
        UINavigationBar.appearance().standardAppearance   = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance    = appearance
    }
    
    deinit {
        windowService?.onColorSchemeChanged -= colorChangeHandler
    }
    
    private func onColorSchemeChanged(_ scheme: ColorScheme) {
        let efftect: UIBlurEffect.Style = scheme.isDarkMode ? .systemChromeMaterialDark : .regular

        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = UIBlurEffect(style: efftect)

        UINavigationBar.appearance().standardAppearance   = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance    = appearance

        navigationBar.backgroundColor      = .clear
        navigationBar.standardAppearance   = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance    = appearance
    }
}
