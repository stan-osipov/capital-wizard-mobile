//
//  AnimatedCardView.swift
//  capital-wizard-ios
//
//  Created by Roman on 07.02.2026.
//

import UIKit

class AnimatedCardView: UIView {
    private lazy var windowsService: WindowsService? = ServiceManager.shared.getService()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupCard()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupCard() {
        backgroundColor    = windowsService?.colors.cardBackground
        layer.cornerRadius = 16
        layer.borderWidth  = 1
        layer.borderColor  = windowsService?.colors.cardBorder.cgColor
        alpha = 0
        transform = CGAffineTransform(translationX: 0, y: 30).scaledBy(x: 0.95, y: 0.95)
    }

    func animateIn() {
        UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0.8) {
            self.alpha = 1
            self.transform = .identity
        }
    }
}
