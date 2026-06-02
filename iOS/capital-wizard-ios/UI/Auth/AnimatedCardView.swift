//
//  AnimatedCardView.swift
//  capital-wizard-ios
//
//  Created by Roman on 07.02.2026.
//

import UIKit

class AnimatedCardView: UIView {
    private lazy var windowsService: WindowsService? = ServiceManager.shared.getService()

    /// Guards the entrance spring so it runs only on first appearance. When the
    /// card is revealed again (e.g. another screen is dismissed on top of it),
    /// `viewWillAppear` fires once more — re-springing there adds a hitch at the
    /// tail of the transition, so we just snap to the resting state instead.
    private var hasAnimated = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupCard()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupCard() {
        // Design system: the auth card is transparent — no fill, border,
        // shadow or corner radius. Only the entrance animation remains.
        backgroundColor = .clear
        alpha = 0
        transform = CGAffineTransform(translationX: 0, y: 30).scaledBy(x: 0.95, y: 0.95)
    }

    func animateIn() {
        // Only spring on the first appearance. On subsequent reveals just
        // ensure the resting state so we don't re-animate at the tail of a
        // dismiss transition.
        guard !hasAnimated else {
            alpha = 1
            transform = .identity
            return
        }
        hasAnimated = true
        UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0.8) {
            self.alpha = 1
            self.transform = .identity
        }
    }
}
