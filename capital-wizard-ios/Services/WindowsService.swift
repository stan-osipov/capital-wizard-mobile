//
//  WindowsService.swift
//  capital-wizard-ios
//
//  Created by Roman on 07.02.2026.
//

import UIKit

protocol DockingDelegate: AnyObject {
    func onLayoutChanged(to layout: ViewUILayout, deSelected: Array<String>)
    func onClose(item: BarItem, layout: ViewUILayout)
    func animationControllerForTransition(fromVC: UIViewController,
                                          to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning?
}

protocol NavigationContainer: AnyObject {
    func add(application: Application)
    func update(application: Application)
    func remove(application: Application)
    func show(application: Application, with layout: ApplicationUILayout?)
    func update(badge: Int, for application: Application)
    func removeAll()
}

extension NavigationContainer {
    func update(application: Application) {}
}

enum ColorScheme: UInt8 {
    case light       = 0
    case dark        = 1
    case systemLight = 2
    case systemDark  = 3
    
    var isDarkMode: Bool {
        switch self {
        case .dark, .systemDark:
            return true
        case .light, .systemLight:
            return false
        }
    }
}

struct AppColors {
    var blurEffect:      UIBlurEffect.Style
    var backgroundColor: UIColor
    var tabBarCollor:    UIColor = UIColor(red: 15/255, green: 24/255, blue: 43/255, alpha: 1)
    var separatorLine:   UIColor
    var tintColor:       UIColor
    var unselectedColor: UIColor
    
    var gradientFirst:   UIColor
    var gradientSecond:  UIColor

    var successGreen    = UIColor(red: 34/255,  green: 197/255, blue: 94/255,  alpha: 1)
    var errorRed        = UIColor(red: 239/255, green: 68/255,  blue: 68/255,  alpha: 1)
    var cardBackground  = UIColor(red: 30/255,  green: 41/255,  blue: 59/255,  alpha: 1)
    var cardBorder      = UIColor(red: 51/255,  green: 65/255,  blue: 85/255,  alpha: 1)
    
    var inputBackground = UIColor(red: 30/255,  green: 41/255,  blue: 59/255,  alpha: 1)
    var inputBorder     = UIColor(red: 71/255,  green: 85/255,  blue: 105/255, alpha: 1)
    var textSecondary   = UIColor(red: 148/255, green: 163/255, blue: 184/255, alpha: 1)
    var linkColor       = UIColor(red: 139/255, green: 92/255,  blue: 246/255, alpha: 1)
    
    var textPrimary     = UIColor.white
    
    init(scheme: ColorScheme) {
        if scheme.isDarkMode {
            blurEffect      = .dark
            backgroundColor = UIColor(red: 15/255,  green: 23/255,  blue: 42/255,  alpha: 1)

            separatorLine   = UIColor(red: 3/255,  green: 140/255, blue: 140/255, alpha: 1)
            tintColor       = .white
            unselectedColor = .white
            
            gradientFirst   = UIColor(red: 139/255, green: 92/255,  blue: 246/255, alpha: 1)
            gradientSecond  = UIColor(red: 168/255, green: 85/255,  blue: 247/255, alpha: 1)
        } else {
            blurEffect      = .systemUltraThinMaterialLight
            backgroundColor = UIColor(red: 252/255, green: 254/255, blue: 255/255, alpha: 1)
            separatorLine   = UIColor(red: 65/255,  green: 203/255, blue: 229/255, alpha: 1)
            tintColor       = .black
            unselectedColor = .black
            
            // TODO: Add white
            gradientFirst   = UIColor(red: 139/255, green: 92/255,  blue: 246/255, alpha: 1)
            gradientSecond  = UIColor(red: 168/255, green: 85/255,  blue: 247/255, alpha: 1)
        }
    }
}

struct WindowsServiceConst {
    static let colorSchemeKey   = "color_scheme"
    static let tabBarIconInsets = UIEdgeInsets(top: 3, left: 3, bottom: 3, right: 3)
}

class WindowsService: NSObject, Service {
    let window: UIWindow

    private var navigationContainer: (UIViewController & NavigationContainer)?

    private var launchVC: LaunchViewController

    var colorScheme:          ColorScheme
    var onColorSchemeChanged: Event<ColorScheme> = Event()
    var applicationsDelegate:  ApplicationsWindowsServiceDelegate?
    
    var colors: AppColors {
        AppColors(scheme: colorScheme)
    }
    
    private var nextPath: WindowTransitionPath?

    var mainController: UIViewController? {
        navigationContainer
    }

    init(window: UIWindow) {
        self.window      = window
        self.colorScheme = .dark

        launchVC = LaunchViewController()

        window.backgroundColor = .clear
        switch self.colorScheme {
        case .light:
            window.overrideUserInterfaceStyle = .light
        case .dark:
            window.overrideUserInterfaceStyle = .dark
        case .systemLight, .systemDark:
            window.overrideUserInterfaceStyle = .unspecified
        }
       
        super.init()

        if UIDevice.current.userInterfaceIdiom != .pad {
            let tabBar = TabBarController(colorSchemeDelegate: self)
            tabBar.dockingDelegate = self
            navigationContainer = tabBar
        } else {
            let split = SplitViewController(style: .doubleColumn)
            split.dockingDelegate    = self
            split.colorSchemeDelegate = self
            navigationContainer = split
        }

        launchVC.delegate = self

        window.rootViewController = launchVC
    }

    func postInit() {
        let authService: AuthService? = ServiceManager.shared.getService()

        authService?.onLogin += EventCallback { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: {
                self?.window.rootViewController = self?.launchVC
                guard let controller = self?.mainController else {
                    return
                }

                self?.showViewController(vc: controller)
            })
        }

        authService?.onLogout += EventCallback { [weak self] in
            self?.mainController?.dismiss(animated: false, completion: {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: {
                    self?.showLogin()
                })
            })
        }
    }

    func showLogin() {
        if window.rootViewController is LoginViewController { return }
        window.rootViewController = LoginViewController()
    }
    
    func updateColorScheme(to scheme: ColorScheme) {
        colorScheme = scheme
        switch scheme {
        case .light:
            window.overrideUserInterfaceStyle = .light
        case .dark:
            window.overrideUserInterfaceStyle = .dark
        case .systemLight, .systemDark:
            window.overrideUserInterfaceStyle = .unspecified
        }
        onColorSchemeChanged.invoke(colorScheme)
    }
    
    func add(application: Application) {
        navigationContainer?.add(application: application)
    }

    func update(application: Application) {
        navigationContainer?.update(application: application)
    }

    func remove(application: Application) {
        navigationContainer?.remove(application: application)
    }

    func show(application: Application, with layout: ApplicationUILayout?) {
        navigationContainer?.show(application: application, with: layout)
    }

    func update(badge: Int, for application: Application) {
        navigationContainer?.update(badge: badge, for: application)
    }

    func removeAllTabBars() {
        navigationContainer?.removeAll()
    }
    
    func showViewController(vc: UIViewController, callback: (() -> Void)? = nil) {
        vc.modalPresentationStyle = .fullScreen
        self.launchVC.present(vc, animated: true, completion: callback)
    }
    
    func createTabController(isHome: Bool = false,
                             hideNavigationBar: Bool = false,
                             with title: String,
                             and image: UIImage?,
                             tag: Int,
                             isColored: Bool,
                             vc: UIViewController) -> UIViewController {
        
        if hideNavigationBar {
            vc.tabBarItem = createTabBarItem(image: image, coloredIcon: isColored, title: title, tag: tag)
            return vc
        }
        
        let nav = NavigationController(rootViewController: vc)
        nav.tabBarItem = createTabBarItem(image: image, coloredIcon: isColored, title: title, tag: tag)
        nav.viewControllers.first?.navigationItem.title = title
        
        guard isHome else {
            return nav
        }
        
        let navBar = UINavigationBar()
        navBar.translatesAutoresizingMaskIntoConstraints = false;
        nav.view.addSubview(navBar)
        NSLayoutConstraint.activate([
            navBar.topAnchor.constraint(equalTo: nav.navigationBar.safeAreaLayoutGuide.topAnchor),
            navBar.widthAnchor.constraint(equalTo: nav.navigationBar.widthAnchor),
            navBar.heightAnchor.constraint(equalTo: nav.navigationBar.heightAnchor),
        ])
        
        return nav
    }
    
    func createTabBarItem(image: UIImage?, coloredIcon: Bool, title: String, tag: Int) -> UITabBarItem {
        var normalImage: UIImage?
        var selectedImage: UIImage?
        if coloredIcon {
            normalImage =  image?
                .withRoundedBackground(backgroundColor: .lightGray.withAlphaComponent(0.22))
                .withRenderingMode(.alwaysOriginal)
            selectedImage = image?
                .withRoundedBackground()
                .withRenderingMode(.alwaysOriginal)
        } else {
            normalImage = image?
                .withRenderingMode(.alwaysTemplate)
                .withRoundedBackground(backgroundColor: .lightGray.withAlphaComponent(0.05), iconColor: .white)
            selectedImage = image?
                .withRenderingMode(.alwaysTemplate)
                .withRoundedBackground(iconColor: .white)
        }
        
        let item           = UITabBarItem()
        item.title         = title
        item.image         = normalImage
        item.selectedImage = selectedImage
        item.tag           = tag
        item.imageInsets   = WindowsServiceConst.tabBarIconInsets
        
        return item
    }
    
    func presentPopover(_ popover: UIViewController,
                        barItem: UIBarButtonItem? = nil,
                        with sourceRect: CGRect? = nil,
                        direction: UIPopoverArrowDirection = .up,
                        sourceView: UIView? = nil) {
        popover.modalPresentationStyle = .popover

        if let presented = mainController?.presentedViewController {
            presented.dismiss(animated: true) { [weak self] in
                guard let mainController = self?.mainController else { return }
                if let ppc = popover.popoverPresentationController {
                    ppc.permittedArrowDirections = direction
                    ppc.sourceView = sourceView ?? mainController.view
                    if let rect = sourceRect { ppc.sourceRect = rect }
                    if let delegate = mainController as? UIPopoverPresentationControllerDelegate {
                        ppc.delegate = delegate
                    }
                    mainController.present(popover, animated: true, completion: nil)
                }
            }
            return
        }

        if let ppc = popover.popoverPresentationController {
            ppc.permittedArrowDirections = direction
            ppc.sourceView = sourceView ?? mainController?.view
            if let rect = sourceRect { ppc.sourceRect = rect }
            if let delegate = mainController as? UIPopoverPresentationControllerDelegate {
                ppc.delegate = delegate
            }
            mainController?.present(popover, animated: true, completion: nil)
        }
    }

    func presentAlert(_ alert: UIAlertController) {
        mainController?.present(alert, animated: true)
    }

    func addView(rect: CGRect) -> UIView {
        let view = UIView(frame: rect)
        mainController?.view.addSubview(view)
        return view
    }
    
    func addViewOnTop(_ view: UIView) {
        window.addSubview(view)
        window.bringSubviewToFront(view)
    }
}

extension WindowsService: DockingDelegate {
    func onLayoutChanged(to layout: ViewUILayout, deSelected: Array<String>) {
        applicationsDelegate?.onLayoutChanged(to: layout, deSelected: deSelected)
    }

    func onClose(item: BarItem, layout: ViewUILayout) {
        applicationsDelegate?.onCloseApplication(id: item.id, layout: layout)
    }
    
    func animationControllerForTransition(fromVC: UIViewController,
                                          to toVC: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? {

        if let path = nextPath {
            nextPath = nil
            return CustomTransition(from: fromVC, to: toVC, path: path)
        }
        return CustomTransition(from: fromVC, to: toVC, path: .left)
    }
}

extension WindowsService: ColorSchemeDelegate {
    func onColorThemeChanged(to style: UIUserInterfaceStyle) {
        switch colorScheme {
        case .systemDark, .systemLight:
            let color: ColorScheme = style == .dark ? .systemDark : .systemLight
            if color != colorScheme {
                colorScheme = color
                onColorSchemeChanged.invoke(color)
                switch color {
                case .light:
                    window.overrideUserInterfaceStyle = .light
                case .dark:
                    window.overrideUserInterfaceStyle = .dark
                case .systemLight, .systemDark:
                    window.overrideUserInterfaceStyle = .unspecified
                }
            }
        default:
            // We dont change anything because user choset color scheme by himself.
            break
        }
    }
}

enum WindowTransitionPath {
    case left
    case right
    case up
    case down
}

class CustomTransition: NSObject, UIViewControllerAnimatedTransitioning {
    let fromVC: UIViewController
    let toVC: UIViewController
    let path: WindowTransitionPath
    private let transitionDuration: Double = 0.5
    
    init(from vc: UIViewController, to toVC: UIViewController, path: WindowTransitionPath) {
        self.fromVC = vc
        self.toVC   = toVC
        self.path   = path
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        return TimeInterval(transitionDuration)
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        guard let toView = toVC.view, let fromView = fromVC.view else {
            transitionContext.completeTransition(false)
            return
        }

        let frame = transitionContext.initialFrame(for: fromVC)
        var fromFrameEnd = frame
        var toFrameStart = frame
        fromFrameEnd.origin.x   = path == .left ? frame.origin.x - frame.width : frame.origin.x + frame.width
        toFrameStart.origin.x   = path == .left ? frame.origin.x + frame.width : frame.origin.x - frame.width

        toView.frame = toFrameStart

        DispatchQueue.main.async {
            transitionContext.containerView.addSubview(toView)
            UIView.animate(withDuration: self.transitionDuration, animations: {
                fromView.frame = fromFrameEnd
                toView.frame = frame
            }, completion: {success in
                fromView.removeFromSuperview()
                transitionContext.completeTransition(success)
            })
        }
    }
}
