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

/// User-facing theme preference persisted in `UserDefaults`.
/// Default (unset) is `.system` — the app follows the device appearance.
enum ThemePreference: String {
    case system = "system"
    case light  = "light"
    case dark   = "dark"

    var overrideStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    /// Maps a web `mode` string onto the native preference.
    /// `auto → .system`, `light → .light`, `dark`/`dark-soft → .dark`.
    /// Note: `dark-soft` collapses to `.dark` here — the exact web string is
    /// preserved separately in `WindowsServiceConst.webThemeKey`.
    init(webMode: String) {
        switch webMode {
        case "light":            self = .light
        case "dark", "dark-soft": self = .dark
        default:                 self = .system   // "auto" and anything unknown
        }
    }

    /// The web `mode` string that corresponds to this preference, used when the
    /// native side drives the WebView. `.system → auto`. This is lossy for
    /// `dark-soft` (becomes `dark`); callers that have a saved web string should
    /// prefer it when it still resolves back to the same preference.
    var webMode: String {
        switch self {
        case .system: return "auto"
        case .light:  return "light"
        case .dark:   return "dark"
        }
    }
}

/// Small hex convenience initialiser so the palette below reads exactly like
/// the web / Android design-system tokens (e.g. `UIColor(hex: 0xF59E0B)`).
extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >> 8)  & 0xFF) / 255
        let b = CGFloat( hex        & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: alpha)
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
    var cardBackground:  UIColor
    var cardBorder:      UIColor

    var inputBackground: UIColor
    var inputBorder:     UIColor
    var textSecondary:   UIColor
    var linkColor:       UIColor

    var textPrimary:     UIColor

    // MARK: - Design-system tokens (shared with web + Android)

    /// Page background (behind the auth card).
    var dsBackground:   UIColor
    /// Elevated surface (social buttons, etc.).
    var dsSurface:      UIColor
    var dsSurface2:     UIColor
    var dsSurfaceHover: UIColor
    var dsBorder:       UIColor
    var dsBorderStrong: UIColor
    var dsText:         UIColor
    var dsTextMuted:    UIColor
    var dsTextSubtle:   UIColor
    /// Amber accent — links, focus rings, selection, checkbox fill.
    var dsAccent:       UIColor
    /// Soft amber halo used for focus rings.
    var dsAccentSoft:   UIColor
    /// Foreground drawn on top of the amber accent (e.g. checkbox glyph).
    var dsOnAccent:     UIColor

    /// Colour behind the keyboard / bottom safe-area.  Matches the iOS
    /// dark-mode keyboard backdrop so its rounded corners blend in and the
    /// bottom row (`,` / `0` / `⌫`) no longer floats on a mismatched bg.
    var keyboardBackground: UIColor

    init(scheme: ColorScheme) {
        if scheme.isDarkMode {
            blurEffect      = .dark
            keyboardBackground = UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1) // systemGray6 dark

            separatorLine   = UIColor(red: 3/255,  green: 140/255, blue: 140/255, alpha: 1)
            unselectedColor = .white

            gradientFirst   = UIColor(red: 139/255, green: 92/255,  blue: 246/255, alpha: 1)
            gradientSecond  = UIColor(red: 168/255, green: 85/255,  blue: 247/255, alpha: 1)

            // DARK design-system palette
            dsBackground   = UIColor(hex: 0x121317)
            dsSurface      = UIColor(hex: 0x1A1B20)
            dsSurface2     = UIColor(hex: 0x1F2025)
            dsSurfaceHover = UIColor(hex: 0x25272C)
            dsBorder       = UIColor(hex: 0x2C2E34)
            dsBorderStrong = UIColor(hex: 0x3A3D44)
            dsText         = UIColor(hex: 0xF2F3F4)
            dsTextMuted    = UIColor(hex: 0xA6AAB2)
            dsTextSubtle   = UIColor(hex: 0x7C808A)
            dsAccent       = UIColor(hex: 0xFBBF24)
            dsAccentSoft   = UIColor(hex: 0xFBBF24, alpha: 0.20)
            dsOnAccent     = UIColor(hex: 0x211A0E)
        } else {
            blurEffect      = .systemUltraThinMaterialLight
            keyboardBackground = UIColor(red: 209/255, green: 213/255, blue: 219/255, alpha: 1) // light keyboard bg
            separatorLine   = UIColor(red: 65/255,  green: 203/255, blue: 229/255, alpha: 1)
            unselectedColor = .black

            gradientFirst   = UIColor(red: 139/255, green: 92/255,  blue: 246/255, alpha: 1)
            gradientSecond  = UIColor(red: 168/255, green: 85/255,  blue: 247/255, alpha: 1)

            // LIGHT design-system palette
            dsBackground   = UIColor(hex: 0xFAFAFB)
            dsSurface      = UIColor(hex: 0xFFFFFF)
            dsSurface2     = UIColor(hex: 0xF3F4F6)
            dsSurfaceHover = UIColor(hex: 0xECEEF0)
            dsBorder       = UIColor(hex: 0xE5E7E9)
            dsBorderStrong = UIColor(hex: 0xD5D8DB)
            dsText         = UIColor(hex: 0x1B1D23)
            dsTextMuted    = UIColor(hex: 0x696D77)
            dsTextSubtle   = UIColor(hex: 0x8C9099)
            dsAccent       = UIColor(hex: 0xF59E0B)
            dsAccentSoft   = UIColor(hex: 0xF59E0B, alpha: 0.16)
            dsOnAccent     = UIColor(hex: 0xFFFFFF)
        }

        // Map the design-system tokens onto the legacy names so existing
        // screens (navigation, webview chrome, …) keep working unchanged.
        backgroundColor = dsBackground
        cardBackground  = dsSurface
        cardBorder      = dsBorder
        inputBackground = dsBackground
        inputBorder     = dsBorder
        textSecondary   = dsTextMuted
        textPrimary     = dsText
        tintColor       = dsText
        linkColor       = dsAccent
    }

    /// Resolve the palette for a concrete *effective* interface style.
    /// Used by views that read `traitCollection.userInterfaceStyle` so they
    /// pick up the system appearance when the theme preference is `.system`.
    static func colors(for style: UIUserInterfaceStyle) -> AppColors {
        AppColors(scheme: style == .dark ? .dark : .light)
    }
}

struct WindowsServiceConst {
    static let colorSchemeKey   = "color_scheme"
    static let themePreferenceKey = "cw_theme_pref"
    /// Exact web `mode` string (`light` | `dark` | `dark-soft` | `auto`) as last
    /// reported by the WebView. Stored verbatim so it round-trips losslessly.
    static let webThemeKey      = "cw_web_theme"
    /// Web accent id (`amber` | `indigo` | … | `mono`) as last reported by the
    /// WebView. Device-local preference, never the database.
    static let webAccentKey     = "cw_web_accent"
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

    /// Persisted user theme preference. Default (unset) follows the system.
    var themePreference: ThemePreference {
        get {
            let raw = UserDefaults.standard.string(forKey: WindowsServiceConst.themePreferenceKey)
            return raw.flatMap(ThemePreference.init(rawValue:)) ?? .system
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: WindowsServiceConst.themePreferenceKey)
        }
    }

    /// Exact web `mode` string last reported by / seeded into the WebView
    /// (`light` | `dark` | `dark-soft` | `auto`). `nil` until the web reports
    /// one. Used to seed `localStorage['cw-theme']` losslessly on launch.
    var savedWebTheme: String? {
        get { UserDefaults.standard.string(forKey: WindowsServiceConst.webThemeKey) }
        set {
            if let newValue = newValue {
                UserDefaults.standard.set(newValue, forKey: WindowsServiceConst.webThemeKey)
            } else {
                UserDefaults.standard.removeObject(forKey: WindowsServiceConst.webThemeKey)
            }
        }
    }

    /// Web accent id last reported by the WebView (`amber` | … | `mono`).
    /// `nil` until the web reports one. Seeds `localStorage['cw-accent']`.
    var savedWebAccent: String? {
        get { UserDefaults.standard.string(forKey: WindowsServiceConst.webAccentKey) }
        set {
            if let newValue = newValue {
                UserDefaults.standard.set(newValue, forKey: WindowsServiceConst.webAccentKey)
            } else {
                UserDefaults.standard.removeObject(forKey: WindowsServiceConst.webAccentKey)
            }
        }
    }

    /// Persists the exact web theme/accent strings reported by the WebView and
    /// mirrors the mode onto the native `ThemePreference` so the auth/splash
    /// chrome matches. `accent` may be `nil` if the message omitted it.
    func applyWebTheme(mode: String, accent: String?) {
        savedWebTheme = mode
        if let accent = accent, !accent.isEmpty {
            savedWebAccent = accent
        }
        setThemePreference(ThemePreference(webMode: mode))
    }

    /// The web `mode` string to push when the native side changes the theme.
    /// Prefers the saved web string when it still maps back to the current
    /// preference (so a `dark-soft` choice survives a native dark/dark toggle).
    var webModeForCurrentPreference: String {
        let pref = themePreference
        if let saved = savedWebTheme, ThemePreference(webMode: saved) == pref {
            return saved
        }
        return pref.webMode
    }

    var colors: AppColors {
        AppColors(scheme: colorScheme)
    }

    init(window: UIWindow) {
        self.window = window

        // Resolve the initial scheme from the saved preference, falling back
        // to the live system appearance when following the system.
        let pref = UserDefaults.standard.string(forKey: WindowsServiceConst.themePreferenceKey)
            .flatMap(ThemePreference.init(rawValue:)) ?? .system
        let systemIsDark = window.traitCollection.userInterfaceStyle == .dark
        switch pref {
        case .light: self.colorScheme = .light
        case .dark:  self.colorScheme = .dark
        case .system: self.colorScheme = systemIsDark ? .systemDark : .systemLight
        }

        launchVC = LaunchViewController()

        window.backgroundColor = .clear
        window.overrideUserInterfaceStyle = pref.overrideStyle

        super.init()

        launchVC.delegate = self
        window.rootViewController = launchVC
    }

    /// Re-applies the persisted theme preference to the window. `system`
    /// follows the device appearance (`.unspecified`); `light`/`dark` force it.
    func applyThemePreference() {
        let pref = themePreference
        window.overrideUserInterfaceStyle = pref.overrideStyle

        let effectiveIsDark: Bool
        switch pref {
        case .light: effectiveIsDark = false
        case .dark:  effectiveIsDark = true
        case .system: effectiveIsDark = window.traitCollection.userInterfaceStyle == .dark
        }

        let resolved: ColorScheme = pref == .system
            ? (effectiveIsDark ? .systemDark : .systemLight)
            : (effectiveIsDark ? .dark : .light)

        if resolved != colorScheme {
            colorScheme = resolved
            onColorSchemeChanged.invoke(colorScheme)
        }
    }

    /// Persists a new theme preference and applies it immediately.
    func setThemePreference(_ pref: ThemePreference) {
        themePreference = pref
        applyThemePreference()
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
        // Bridge the legacy scheme-based API onto the persisted preference so
        // both entry points stay in sync.
        switch scheme {
        case .light:                    setThemePreference(.light)
        case .dark:                     setThemePreference(.dark)
        case .systemLight, .systemDark: setThemePreference(.system)
        }
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
        // Only react to system appearance changes while we're following the
        // system. A forced light/dark preference ignores the device toggle.
        guard themePreference == .system else { return }

        let color: ColorScheme = style == .dark ? .systemDark : .systemLight
        if color != colorScheme {
            colorScheme = color
            // Stay on `.unspecified` so the window keeps tracking the system.
            window.overrideUserInterfaceStyle = .unspecified
            onColorSchemeChanged.invoke(color)
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
