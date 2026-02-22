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
        
        let scheme = windowsService?.colorScheme ?? .dark

        self.view.backgroundColor = AppColors(scheme: scheme).backgroundColor

        let logo = RoundImageView(image: UIImage(systemName: "chart.line.uptrend.xyaxis.circle")) // TODO: Update logo
        self.view.insertSubview(logo, at: 0)
        logo.translatesAutoresizingMaskIntoConstraints = false
        
        // TODO: Remove hardcode
        NSLayoutConstraint.activate([
            logo.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
            logo.centerYAnchor.constraint(equalTo: self.view.centerYAnchor),
            logo.heightAnchor.constraint(equalTo: self.view.heightAnchor, multiplier: 0.2),
            logo.widthAnchor.constraint(equalTo: logo.heightAnchor)
        ])
        logo.layer.cornerRadius = logo.frame.width/2.0
        logo.layer.masksToBounds = false
        logo.layer.borderWidth = 1
        logo.layer.borderColor = UIColor.systemBlue.cgColor
        
        logo.clipsToBounds = true
    }
    
    var isDarkMode: Bool {
        if #available(iOS 13.0, *) {
            return self.traitCollection.userInterfaceStyle == .dark
        }
        else {
            return false
        }
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if #available(iOS 13.0, *) {
            if self.traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
                delegate?.onColorThemeChanged(to: traitCollection.userInterfaceStyle)
            }
        } else {
            // Fallback on earlier versions
        }
    }
}
