//  capital-wizard-ios
//
//  Created by Roman on 07.02.2026.
//
import UIKit

/// SImple wrapper for UITabBarController
class TabBarController: UITabBarController {
    private var blurEffectView: UIVisualEffectView?
        
    weak var colorSchemeDelegate: ColorSchemeDelegate?
    weak var dockingDelegate:     DockingDelegate?
    
    private var customTabBar: CustomTabBar
    
    private var items: Array<BarItem> = []
    private var itemViewControllers: Array<UIViewController> {
        items.map { $0.vc }
    }
    private var currentSelectedTabTag: Int = 0

    private lazy var windowService:      WindowsService? = ServiceManager.shared.getService()
    private lazy var colorChangeHandler: EventCallback   = EventCallback(onColorSchemeChanged(_:))
    
    init(colorSchemeDelegate: ColorSchemeDelegate?) {
        let tabBar        = CustomTabBar()
        self.customTabBar = tabBar
        super.init(nibName: nil, bundle: nil)
        
        self.setValue(tabBar, forKey: "tabBar")
        
        self.colorSchemeDelegate = colorSchemeDelegate
        
        delegate = self
        
        let applicationService: ApplicationService? = ServiceManager.shared.getService()
        applicationService?.onApplicationsDidStart += EventCallback({ [weak self] in
            self?.customTabBar.updateLabelSizes()
        })
    }
    
    required init?(coder: NSCoder) {
        let tabBar        = CustomTabBar()
        self.customTabBar = tabBar
        super.init(coder: coder)
        
        self.setValue(tabBar, forKey: "tabBar")
        
        delegate = self
    }
    
    func add(application: Application) {
        guard !items.contains(where: { $0.id == application.id }) else {
            return
        }
        guard let vc = application.rootController else {
            return
        }

        items.append(BarItem(id: application.id, name: application.name, icon: nil, vc: vc, layout: application.layout))
        self.setViewControllers(itemViewControllers, animated: true)
    }
    
    func remove(application: Application) {
        guard let index = items.firstIndex(where: { $0.id == application.id }) else {
            return
        }
        items.remove(at: index)
        
        self.setViewControllers(itemViewControllers, animated: false)
    }
    
    func show(application: Application, with layout: ApplicationUILayout?) {
        let index = application.tagIndex >= ApplicationService.defaultAppAmount ? ApplicationService.defaultAppAmount : application.tagIndex
        self.selectedIndex = index
        customTabBar.updateSelected(index: index)
        guard let item = items.first(where: { $0.id ==  application.id}) else {
            return
        }
        
        var deSelected: Array<String> = []
        if let deSelectedId = items.first(where: { $0.vc.tabBarItem.tag == currentSelectedTabTag })?.id {
            deSelected.append(deSelectedId)
        }
        dockingDelegate?.onLayoutChanged(to: .wide(item), deSelected: deSelected)
        
        currentSelectedTabTag = application.tagIndex
    }
    
    func update(badge: Int, for application: Application) {
        let value = badge > 0 ? "\(badge)" : nil
        application.controller?.tabBarItem.badgeValue = value
        application.controller?.tabBarItem.badgeColor = .systemGreen
    }
    
    func removeAll() {
        items.removeAll()
        self.setViewControllers([], animated: true)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
                
        guard let colorScheme = windowService?.colorScheme else {
            // TODO: Maybe show some error, because if can't get window service something doesnt work right
            return
        }
        
        windowService?.onColorSchemeChanged += colorChangeHandler
        
        customTabBar.updateColor(scheme: colorScheme)
        
        let colors = AppColors(scheme: colorScheme)
        
        self.tabBar.backgroundColor         = colors.tabBarCollor
        self.tabBar.unselectedItemTintColor = colors.unselectedColor
        self.tabBar.tintColor               = nil
        
        let blurEffect = UIBlurEffect(style: colors.blurEffect)
        if let blurEffectView = blurEffectView {
            blurEffectView.effect = blurEffect
        } else {
            let blurEffectView = UIVisualEffectView(effect: blurEffect)
            blurEffectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            blurEffectView.backgroundColor  = colors.backgroundColor
            
            self.blurEffectView = blurEffectView
            
            self.tabBar.insertSubview(blurEffectView, at: .zero)
            blurEffectView.frame = self.tabBar.bounds
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        windowService?.onColorSchemeChanged -= colorChangeHandler
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if #available(iOS 13.0, *) {
            if self.traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
                colorSchemeDelegate?.onColorThemeChanged(to: traitCollection.userInterfaceStyle)
            }
        } else {
            // Fallback on earlier versions
        }
    }
    
    private func onColorSchemeChanged(_ scheme: ColorScheme) {
        let colors = AppColors(scheme: scheme)
        
        self.tabBar.backgroundColor         = colors.tabBarCollor
        self.tabBar.unselectedItemTintColor = colors.unselectedColor
        self.tabBar.tintColor               = nil

        let blurEffect = UIBlurEffect(style: colors.blurEffect)
        blurEffectView?.effect = blurEffect
        customTabBar.updateColor(scheme: scheme)
    }
}

extension TabBarController: UITabBarControllerDelegate {
    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        let selected = viewController.tabBarItem.tag
        guard let item = items.first(where: { $0.vc.tabBarItem.tag ==  selected}) else {
            return
        }
        
        var deSelected: Array<String> = []
        if let id = items.first(where: { $0.vc.tabBarItem.tag == currentSelectedTabTag })?.id {
            deSelected.append(id)
        }
        
        dockingDelegate?.onLayoutChanged(to: .wide(item), deSelected: deSelected)
        
        currentSelectedTabTag = selected
        customTabBar.updateSelected(index: currentSelectedTabTag)
        
        guard let tabBarItems = customTabBar.subviews
                .filter({ $0 is UIControl }) as? [UIControl],
              let index = tabBarController.viewControllers?.firstIndex(of: viewController),
              index < tabBarItems.count else { return }

        let tabBarItemView = tabBarItems[index]

        UIView.animate(withDuration: 0.1,
                       animations: {
            tabBarItemView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        }, completion: { _ in
            UIView.animate(withDuration: 0.2) {
                tabBarItemView.transform = CGAffineTransform.identity
            }
        })
    }

    func tabBarController(_ tabBarController: UITabBarController,
                          animationControllerForTransitionFrom fromVC: UIViewController,
                          to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return dockingDelegate?.animationControllerForTransition(fromVC: fromVC, to: toVC)
    }
}

extension TabBarController: NavigationContainer {}

extension TabBarController: UIPopoverPresentationControllerDelegate {

    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        return .popover
    }

    func popoverPresentationControllerDidDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) {

    }

    func popoverPresentationControllerShouldDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) -> Bool {
        return true
    }
}
