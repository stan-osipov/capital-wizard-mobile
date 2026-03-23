//
//  LaunchViewController.swift
//  capital-wizard-ios
//
//  Created by Roman on 07.02.2026.
//

import UIKit

protocol ColorSchemeDelegate: NSObjectProtocol {
    func onColorThemeChanged(to style: UIUserInterfaceStyle)
}

class LaunchViewController: UIViewController {

    weak var delegate: ColorSchemeDelegate?

    private lazy var windowsService: WindowsService? = ServiceManager.shared.getService()

    override func viewDidLoad() {
        super.viewDidLoad()

        let splash = SplashAnimationView()
        splash.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(splash)

        NSLayoutConstraint.activate([
            splash.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            splash.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            splash.topAnchor.constraint(equalTo: view.topAnchor),
            splash.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: -

    var isDarkMode: Bool {
        if #available(iOS 13.0, *) {
            return self.traitCollection.userInterfaceStyle == .dark
        } else {
            return false
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if #available(iOS 13.0, *) {
            if self.traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
                delegate?.onColorThemeChanged(to: traitCollection.userInterfaceStyle)
            }
        }
    }
}
