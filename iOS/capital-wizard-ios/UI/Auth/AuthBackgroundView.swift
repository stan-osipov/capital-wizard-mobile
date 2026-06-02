//
//  AuthBackgroundView.swift
//  capital-wizard-ios
//
//  Shared backdrop for the auth screens: the design-system page background
//  with a soft amber glow bleeding in from the top-left corner. The glow is
//  visible in both light and dark themes (stronger in light).
//

import UIKit

class AuthBackgroundView: UIView {

    private let glowLayer = CAGradientLayer()

    private lazy var windowsService: WindowsService? = ServiceManager.shared.getService()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        // Radial gradient anchored at the top-left, fading to clear.
        glowLayer.type = .radial
        glowLayer.startPoint = CGPoint(x: 0.0, y: 0.0)
        glowLayer.endPoint   = CGPoint(x: 1.0, y: 1.0)
        glowLayer.locations  = [0.0, 1.0]
        layer.addSublayer(glowLayer)
        applyColors()
    }

    private var effectiveStyle: UIUserInterfaceStyle {
        if traitCollection.userInterfaceStyle != .unspecified {
            return traitCollection.userInterfaceStyle
        }
        return windowsService?.window.traitCollection.userInterfaceStyle ?? .dark
    }

    private func applyColors() {
        let style = effectiveStyle
        let colors = AppColors.colors(for: style)
        backgroundColor = colors.dsBackground

        // Light theme carries a brighter amber bloom than dark.
        let glowAlpha: CGFloat = style == .dark ? 0.26 : 0.42
        let glow = colors.dsAccent.withAlphaComponent(glowAlpha)
        glowLayer.colors = [glow.cgColor, colors.dsAccent.withAlphaComponent(0).cgColor]
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Make the glow roughly a corner bloom: a square ~1.4× the width,
        // pinned to the top-left so it reads as a side glow.
        let dimension = bounds.width * 1.4
        glowLayer.frame = CGRect(x: -dimension * 0.35,
                                 y: -dimension * 0.35,
                                 width: dimension,
                                 height: dimension)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            applyColors()
        }
    }
}
