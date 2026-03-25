//
//  WindowsService.swift
//  capital-wizard-ios
//
//  Created by Roman on 07.02.2026.
//

import UIKit

// MARK: - Protocols (kept for compilation of unused files)

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

// MARK: - Color Scheme

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

            gradientFirst   = UIColor(red: 139/255, green: 92/255,  blue: 246/255, alpha: 1)
            gradientSecond  = UIColor(red: 168/255, green: 85/255,  blue: 247/255, alpha: 1)
        }
    }
}

struct WindowsServiceConst {
    static let colorSchemeKey   = "color_scheme"
    static let tabBarIconInsets = UIEdgeInsets(top: 3, left: 3, bottom: 3, right: 3)
}

// MARK: - WindowsService

class WindowsService: NSObject, Service {
    let window: UIWindow

    private var launchVC: LaunchViewController

    /// The single main view controller shown after login (set by ApplicationService).
    var mainController: UIViewController?

    var colorScheme:          ColorScheme
    var onColorSchemeChanged: Event<ColorScheme> = Event()
    var applicationsDelegate: ApplicationsWindowsServiceDelegate?

    var colors: AppColors {
        AppColors(scheme: colorScheme)
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

        launchVC.delegate = self
        window.rootViewController = launchVC
    }

    func postInit() {
        let authService: AuthService? = ServiceManager.shared.getService()

        authService?.onLogin += EventCallback { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self?.window.rootViewController = self?.launchVC
                guard let controller = self?.mainController else { return }
                self?.showViewController(vc: controller, animated: false)
            }
        }

        authService?.onLogout += EventCallback { [weak self] in
            guard let self = self else { return }
            if let mainController = self.mainController {
                mainController.dismiss(animated: false) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.showLogin()
                    }
                }
            } else {
                self.showLogin()
            }
        }
    }

    func showLogin() {
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

    func showViewController(vc: UIViewController, animated: Bool = true, callback: (() -> Void)? = nil) {
        vc.modalPresentationStyle = .fullScreen
        self.launchVC.present(vc, animated: animated, completion: callback)
    }

    // MARK: - Stubs (kept so other files compile)

    func add(application: Application) {}
    func update(application: Application) {}
    func remove(application: Application) {}
    func show(application: Application, with layout: ApplicationUILayout?) {}
    func update(badge: Int, for application: Application) {}
    func removeAllTabBars() {}

    func createTabController(isHome: Bool = false,
                             hideNavigationBar: Bool = false,
                             with title: String,
                             and image: UIImage?,
                             tag: Int,
                             isColored: Bool,
                             vc: UIViewController) -> UIViewController { vc }

    func presentPopover(_ popover: UIViewController,
                        barItem: UIBarButtonItem? = nil,
                        with sourceRect: CGRect? = nil,
                        direction: UIPopoverArrowDirection = .up,
                        sourceView: UIView? = nil) {}
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
            break
        }
    }
}

// MARK: - Kept for compilation of unused files

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
