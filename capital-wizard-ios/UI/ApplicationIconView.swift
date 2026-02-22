//
//  ApplicationIconView.swift
//  capital-wizard-ios
//
//  Created by Roman on 07.02.2026.
//

import UIKit

class ApplicationIconView: UIView {
    private var container:  UIView?
    private var imageView:  UIImageView?
    private var badgeLabel: UILabel?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    init() {
        super.init(frame: .zero)
        setupView()
    }
    
    func update(icon: UIImage?, tintColor: UIColor, backgroundColor: UIColor) {
        imageView?.image           = icon
        imageView?.tintColor       = tintColor
        container?.backgroundColor = backgroundColor
    }
    
    func setBadge(_ count: Int?) {
        if let count = count, count > 0 {
            badgeLabel?.isHidden = false
            badgeLabel?.text = "\(count)"
        } else {
            badgeLabel?.isHidden = true
        }
    }
    
    func addConstraint(to view: UIView, sizeMultiplier: CGFloat) {
        self.translatesAutoresizingMaskIntoConstraints = false
        container?.translatesAutoresizingMaskIntoConstraints = false
        imageView?.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel?.translatesAutoresizingMaskIntoConstraints = false

        self.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: sizeMultiplier).isActive = true
        self.widthAnchor.constraint(equalTo: self.heightAnchor).isActive = true
        
        guard let container = container else {
            return
        }
        guard let imageView = imageView else {
            return
        }
        guard let badgeLabel = badgeLabel else {
            return
        }
        
        container.heightAnchor.constraint(equalTo: self.heightAnchor, multiplier: 0.9).isActive = true
        container.widthAnchor.constraint(equalTo: container.heightAnchor).isActive = true
        container.centerXAnchor.constraint(equalTo: self.centerXAnchor).isActive = true
        container.centerYAnchor.constraint(equalTo: self.centerYAnchor).isActive = true
        
        imageView.heightAnchor.constraint(equalTo: container.heightAnchor, multiplier: 0.6).isActive = true
        imageView.widthAnchor.constraint(equalTo: imageView.heightAnchor).isActive = true
        imageView.centerXAnchor.constraint(equalTo: container.centerXAnchor).isActive = true
        imageView.centerYAnchor.constraint(equalTo: container.centerYAnchor).isActive = true
        
        badgeLabel.topAnchor.constraint(equalTo: self.topAnchor, constant: -4).isActive = true
        badgeLabel.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: 4).isActive = true
        badgeLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 16).isActive = true
        badgeLabel.widthAnchor.constraint(greaterThanOrEqualTo: badgeLabel.heightAnchor).isActive = true
    }
    
    private func setupView() {
        self.backgroundColor = .clear
        
        let view = UIView()
        
        view.layer.cornerRadius  = 8
        view.layer.masksToBounds = true
        view.backgroundColor     = .lightGray.withAlphaComponent(0.2)
        
        self.addSubview(view)
        self.container = view
        
        let imageView = UIImageView()
        imageView.layer.cornerRadius  = 4
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.layer.masksToBounds = true
        view.addSubview(imageView)
        
        let badge = UILabel()
        badge.backgroundColor = .systemGreen
        badge.textColor       = .white
        badge.font            = UIFont.systemFont(ofSize: 11, weight: .bold)
        badge.textAlignment   = .center
        
        badge.layer.cornerRadius        = 4
        badge.layer.masksToBounds       = true
        badge.adjustsFontSizeToFitWidth = true
        badge.minimumScaleFactor        = 0.5

        self.addSubview(badge)
        self.bringSubviewToFront(badge)
        
        self.badgeLabel = badge
        badge.isHidden  = true
        
        self.imageView = imageView
    }
}
