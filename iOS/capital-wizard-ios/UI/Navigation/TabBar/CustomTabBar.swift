//
//  CustomTabBar.swift
//  capital-wizard-ios
//
//  Created by Roman on 07.02.2026.
//

import UIKit

struct CustomTabBarConst {
    static let cornerRadius: CGFloat = 8
    static let itemSize:     CGSize  = CGSize(width: 38, height: 38)
    static let darkBackgroundColor   = UIColor(red: 40/255,  green: 149/255, blue: 234/255, alpha: 1)
    static let lightBackgroundColor  = UIColor(red: 28/255, green: 194/255, blue: 224/255, alpha: 1)
}

class CustomTabBar: UITabBar {
    
    private var selectedBackgroundView: UIView?
    private var selectedIndex: Int = .zero
    
    private var scheme: ColorScheme = .systemLight

    override func layoutSubviews() {
        super.layoutSubviews()

        if selectedBackgroundView == nil {
            let view = UIView()
            if scheme.isDarkMode {
                view.backgroundColor = CustomTabBarConst.darkBackgroundColor
            } else {
                view.backgroundColor = CustomTabBarConst.lightBackgroundColor
            }
            view.layer.cornerRadius = CustomTabBarConst.cornerRadius
            view.clipsToBounds      = true
            insertSubview(view, at: .zero)
            selectedBackgroundView = view
            selectedBackgroundView?.tintColor = .clear
        }
        
        updateSelected(index: selectedIndex)
    }
    
    func updateLabelSizes() {
        let tabBarButtons = self.subviews.filter { $0 is UIControl }
        tabBarButtons.forEach { button in
            guard let label = button.subviews.filter( { $0 is UILabel }).first as? UILabel else {
                return
            }

            label.adjustsFontSizeToFitWidth = false
            label.textAlignment = .center
            label.lineBreakMode = .byTruncatingTail
            label.numberOfLines = 1
            
            label.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(greaterThanOrEqualTo: button.leadingAnchor),
                label.trailingAnchor.constraint(lessThanOrEqualTo: button.trailingAnchor)
            ])
        }
    }
    
    func updateColor(scheme: ColorScheme) {
        if scheme.isDarkMode {
            selectedBackgroundView?.backgroundColor = CustomTabBarConst.darkBackgroundColor
        } else {
            selectedBackgroundView?.backgroundColor = CustomTabBarConst.lightBackgroundColor
        }
        self.scheme = scheme
    }

    func updateSelected(index: Int) {
        self.selectedIndex = index
        guard let items = items else {
            return
        }
        
        var button: UIView?
        if index >= items.count {
            button = getTabBarButton(at: items.count - 1)
        } else {
            button = getTabBarButton(at: index)
        }
        
        guard let button = button else {
            return
        }
        
        guard let view = selectedBackgroundView else {
            return
        }
        
        guard let imageView = button.subviews.filter({ $0 is UIImageView }).first as? UIImageView else {
            return
        }
        button.insertSubview(view, at: .zero)
        
        view.translatesAutoresizingMaskIntoConstraints = false
        
        view.widthAnchor.constraint(equalTo: imageView.widthAnchor).isActive     = true
        view.heightAnchor.constraint(equalTo: imageView.heightAnchor).isActive   = true
        view.centerXAnchor.constraint(equalTo: imageView.centerXAnchor).isActive = true
        view.centerYAnchor.constraint(equalTo: imageView.centerYAnchor).isActive = true
        
        self.tintColor = nil
        imageView.tintColor = .white
        let color = AppColors(scheme: scheme)
        guard let label = button.subviews.filter( { $0 is UILabel }).first as? UILabel else {
            return
        }
        
        label.tintColor = color.tintColor
        
        guard index >= 4 else {
            return
        }
        label.adjustsFontSizeToFitWidth = false
        label.textAlignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.numberOfLines = 1
        
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(greaterThanOrEqualTo: button.leadingAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: button.trailingAnchor)
        ])
    }
}

extension UITabBar {
    func getTabBarButton(at index: Int) -> UIView? {
        let tabBarButtons = self.subviews.filter { $0 is UIControl }
        guard index >= .zero, index < tabBarButtons.count else {
            return nil
        }
        return tabBarButtons[index]
    }
}
