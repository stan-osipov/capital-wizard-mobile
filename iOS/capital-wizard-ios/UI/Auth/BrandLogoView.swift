//
//  BrandLogoView.swift
//  capital-wizard-ios
//
//  Capital Wizard brand logo tile — the "W" chart zig-zag mark drawn in a
//  white stroke inside a rounded tile with a dark vertical-gradient fill.
//  Mirrors the web/Android `.cw-logo` mark used in the auth app-bar lockup.
//
//  The mark path is authored on a 0–100 coordinate space
//  (`M16 32 L38 74 L50 48 L62 74 L84 32`) and scaled to the requested tile
//  size, matching the design handoff (`reference/icons.jsx` → `Logo`).
//

import UIKit

class BrandLogoView: UIView {

    private let gradientLayer = CAGradientLayer()
    private let markLayer = CAShapeLayer()

    /// Side length of the square tile (e.g. 30 in the mobile app-bar).
    private let size: CGFloat

    init(size: CGFloat = 30) {
        self.size = size
        super.init(frame: CGRect(x: 0, y: 0, width: size, height: size))
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize {
        CGSize(width: size, height: size)
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        // Corner radius 9 on a 30pt tile, scaled proportionally for other sizes.
        layer.cornerRadius = size * (9.0 / 30.0)
        layer.masksToBounds = false

        // Subtle drop shadow (matches `box-shadow: 0 1px 2px rgba(0,0,0,0.4)`).
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.4
        layer.shadowRadius = 2
        layer.shadowOffset = CGSize(width: 0, height: 1)

        // Vertical-ish gradient fill: 155deg #2c2d31 → #131316.
        gradientLayer.colors = [
            UIColor(hex: 0x2C2D31).cgColor,
            UIColor(hex: 0x131316).cgColor
        ]
        // 155deg ≈ down-and-slightly-left. Approximate with a near-vertical sweep.
        gradientLayer.startPoint = CGPoint(x: 0.30, y: 0.0)
        gradientLayer.endPoint   = CGPoint(x: 0.70, y: 1.0)
        gradientLayer.cornerRadius = layer.cornerRadius
        gradientLayer.masksToBounds = true
        layer.addSublayer(gradientLayer)

        // The "W" chart mark: white stroke, round caps/joins, above the fill.
        markLayer.fillColor = nil
        markLayer.strokeColor = UIColor.white.cgColor
        markLayer.lineCap = .round
        markLayer.lineJoin = .round
        layer.addSublayer(markLayer)

        // Inset hairline border drawn as a separate layer so it sits above
        // the gradient (1px @ 6% white).
        let border = CALayer()
        border.borderColor = UIColor.white.withAlphaComponent(0.06).cgColor
        border.borderWidth = 1
        border.cornerRadius = layer.cornerRadius
        border.name = "insetBorder"
        layer.addSublayer(border)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
        markLayer.frame = bounds

        // Scale the 0–100 design path to the tile bounds.
        let scale = bounds.width / 100.0
        let path = UIBezierPath()
        let pts: [(CGFloat, CGFloat)] = [
            (16, 32), (38, 74), (50, 48), (62, 74), (84, 32)
        ]
        path.move(to: CGPoint(x: pts[0].0 * scale, y: pts[0].1 * scale))
        for p in pts.dropFirst() {
            path.addLine(to: CGPoint(x: p.0 * scale, y: p.1 * scale))
        }
        markLayer.path = path.cgPath
        // Stroke width 13 on the 0–100 space, scaled to the tile.
        markLayer.lineWidth = 13 * scale

        if let border = layer.sublayers?.first(where: { $0.name == "insetBorder" }) {
            border.frame = bounds
            border.cornerRadius = layer.cornerRadius
        }

        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: layer.cornerRadius).cgPath
    }
}
