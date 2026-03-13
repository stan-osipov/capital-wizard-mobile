//
//  SplashAnimationView.swift
//  capital-wizard-ios
//

import UIKit

class SplashAnimationView: UIView {

    // MARK: - Colors

    private let purple   = UIColor(red: 139/255, green: 92/255,  blue: 246/255, alpha: 1)
    private let indigo   = UIColor(red: 99/255,  green: 102/255, blue: 241/255, alpha: 1)
    private let violet   = UIColor(red: 168/255, green: 85/255,  blue: 247/255, alpha: 1)
    private let slate900 = UIColor(red: 15/255,  green: 23/255,  blue: 42/255,  alpha: 1)

    let createdAt = CACurrentMediaTime()

    // MARK: - Animated view references

    private var ambientView: UIView?
    private var ringViews: [UIView] = []
    private var orbitView1: UIView?
    private var orbitView2: UIView?
    private var iconView: UIView?
    private var titleLabel: UILabel?
    private var stopped = false

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        buildUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildUI()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Window lifecycle

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil && !stopped {
            applyAnimations()
            // Re-apply animations when app returns from background
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(onForeground),
                name: UIApplication.willEnterForegroundNotification,
                object: nil
            )
        } else {
            NotificationCenter.default.removeObserver(
                self,
                name: UIApplication.willEnterForegroundNotification,
                object: nil
            )
        }
    }

    @objc private func onForeground() {
        guard !stopped else { return }
        // Small delay to let the system settle after foregrounding
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.applyAnimations()
        }
    }

    // MARK: - Build views (no animations here)

    private func buildUI() {
        backgroundColor = slate900

        // ── Ambient background glow ──
        let ambientSize: CGFloat = 400
        let ambient = UIView()
        ambient.translatesAutoresizingMaskIntoConstraints = false
        addSubview(ambient)
        ambientView = ambient

        NSLayoutConstraint.activate([
            ambient.centerXAnchor.constraint(equalTo: centerXAnchor),
            ambient.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -40),
            ambient.widthAnchor.constraint(equalToConstant: ambientSize),
            ambient.heightAnchor.constraint(equalToConstant: ambientSize)
        ])

        let ag = CAGradientLayer()
        ag.type = .radial
        ag.colors = [
            purple.withAlphaComponent(0.18).cgColor,
            indigo.withAlphaComponent(0.07).cgColor,
            UIColor.clear.cgColor
        ]
        ag.locations = [0, 0.5, 1]
        ag.startPoint = CGPoint(x: 0.5, y: 0.5)
        ag.endPoint = CGPoint(x: 1, y: 1)
        ag.frame = CGRect(x: 0, y: 0, width: ambientSize, height: ambientSize)
        ambient.layer.addSublayer(ag)

        // ── Logo container ──
        let logoSize: CGFloat = 160
        let logoContainer = UIView()
        logoContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(logoContainer)

        NSLayoutConstraint.activate([
            logoContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            logoContainer.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -40),
            logoContainer.widthAnchor.constraint(equalToConstant: logoSize),
            logoContainer.heightAnchor.constraint(equalToConstant: logoSize)
        ])

        // ── Ripple pulse rings ──
        let ringBase: CGFloat = 100
        for _ in 0..<3 {
            let ringView = UIView()
            ringView.translatesAutoresizingMaskIntoConstraints = false
            logoContainer.addSubview(ringView)

            NSLayoutConstraint.activate([
                ringView.centerXAnchor.constraint(equalTo: logoContainer.centerXAnchor),
                ringView.centerYAnchor.constraint(equalTo: logoContainer.centerYAnchor),
                ringView.widthAnchor.constraint(equalToConstant: ringBase),
                ringView.heightAnchor.constraint(equalToConstant: ringBase)
            ])

            let shape = CAShapeLayer()
            shape.path = UIBezierPath(ovalIn: CGRect(x: 0, y: 0,
                                                      width: ringBase, height: ringBase)).cgPath
            shape.fillColor = UIColor.clear.cgColor
            shape.strokeColor = purple.withAlphaComponent(0.35).cgColor
            shape.lineWidth = 1.5
            ringView.layer.addSublayer(shape)

            ringViews.append(ringView)
        }

        // ── Orbital gradient arc ──
        let orbitSize: CGFloat = 136

        let ov1 = UIView()
        ov1.translatesAutoresizingMaskIntoConstraints = false
        logoContainer.addSubview(ov1)
        orbitView1 = ov1

        NSLayoutConstraint.activate([
            ov1.centerXAnchor.constraint(equalTo: logoContainer.centerXAnchor),
            ov1.centerYAnchor.constraint(equalTo: logoContainer.centerYAnchor),
            ov1.widthAnchor.constraint(equalToConstant: orbitSize),
            ov1.heightAnchor.constraint(equalToConstant: orbitSize)
        ])

        let arcPath = UIBezierPath(arcCenter: CGPoint(x: orbitSize / 2, y: orbitSize / 2),
                                    radius: orbitSize / 2,
                                    startAngle: 0,
                                    endAngle: .pi * 2,
                                    clockwise: true).cgPath

        let arc1 = CAShapeLayer()
        arc1.path = arcPath
        arc1.fillColor = UIColor.clear.cgColor
        arc1.lineWidth = 2.5
        arc1.lineCap = .round
        arc1.strokeStart = 0
        arc1.strokeEnd = 0.22

        let grad1 = CAGradientLayer()
        grad1.frame = CGRect(x: 0, y: 0, width: orbitSize, height: orbitSize)
        grad1.colors = [purple.cgColor, indigo.cgColor, violet.cgColor]
        grad1.startPoint = CGPoint(x: 0, y: 0)
        grad1.endPoint = CGPoint(x: 1, y: 1)
        grad1.mask = arc1
        ov1.layer.addSublayer(grad1)

        // Second arc
        let ov2 = UIView()
        ov2.translatesAutoresizingMaskIntoConstraints = false
        logoContainer.addSubview(ov2)
        orbitView2 = ov2

        NSLayoutConstraint.activate([
            ov2.centerXAnchor.constraint(equalTo: logoContainer.centerXAnchor),
            ov2.centerYAnchor.constraint(equalTo: logoContainer.centerYAnchor),
            ov2.widthAnchor.constraint(equalToConstant: orbitSize),
            ov2.heightAnchor.constraint(equalToConstant: orbitSize)
        ])

        let arc2 = CAShapeLayer()
        arc2.path = arcPath
        arc2.fillColor = UIColor.clear.cgColor
        arc2.lineWidth = 1.5
        arc2.lineCap = .round
        arc2.strokeStart = 0
        arc2.strokeEnd = 0.15

        let grad2 = CAGradientLayer()
        grad2.frame = CGRect(x: 0, y: 0, width: orbitSize, height: orbitSize)
        grad2.colors = [violet.cgColor, purple.withAlphaComponent(0.4).cgColor]
        grad2.startPoint = CGPoint(x: 1, y: 0)
        grad2.endPoint = CGPoint(x: 0, y: 1)
        grad2.mask = arc2
        ov2.layer.addSublayer(grad2)

        // ── Center "$" icon ──
        let iconSize: CGFloat = 64
        let iv = UIView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.clipsToBounds = false
        logoContainer.addSubview(iv)
        iconView = iv

        let gradient = CAGradientLayer()
        gradient.colors = [purple.cgColor, indigo.cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        gradient.frame = CGRect(x: 0, y: 0, width: iconSize, height: iconSize)
        gradient.cornerRadius = 18
        iv.layer.insertSublayer(gradient, at: 0)

        iv.layer.shadowColor = purple.cgColor
        iv.layer.shadowOffset = .zero
        iv.layer.shadowRadius = 28
        iv.layer.shadowOpacity = 0.7

        let symbol = UILabel()
        symbol.text = "$"
        symbol.font = .systemFont(ofSize: 32, weight: .bold)
        symbol.textColor = .white
        symbol.textAlignment = .center
        symbol.translatesAutoresizingMaskIntoConstraints = false
        iv.addSubview(symbol)

        NSLayoutConstraint.activate([
            iv.centerXAnchor.constraint(equalTo: logoContainer.centerXAnchor),
            iv.centerYAnchor.constraint(equalTo: logoContainer.centerYAnchor),
            iv.widthAnchor.constraint(equalToConstant: iconSize),
            iv.heightAnchor.constraint(equalToConstant: iconSize),
            symbol.centerXAnchor.constraint(equalTo: iv.centerXAnchor),
            symbol.centerYAnchor.constraint(equalTo: iv.centerYAnchor)
        ])

        // ── Title ──
        let title = UILabel()
        let attributed = NSAttributedString(
            string: "Capital Wizard",
            attributes: [
                .kern: 4.0,
                .font: UIFont.systemFont(ofSize: 26, weight: .light),
                .foregroundColor: UIColor.white.withAlphaComponent(0.9)
            ]
        )
        title.attributedText = attributed
        title.textAlignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false
        title.alpha = 0
        addSubview(title)
        titleLabel = title

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: logoContainer.bottomAnchor, constant: 28),
            title.centerXAnchor.constraint(equalTo: centerXAnchor)
        ])
    }

    // MARK: - Apply animations (called when in window hierarchy)

    private func applyAnimations() {
        // Ambient breathe
        if let ambient = ambientView {
            ambient.layer.removeAllAnimations()
            let breathe = CABasicAnimation(keyPath: "transform.scale")
            breathe.fromValue = 0.85
            breathe.toValue = 1.2
            breathe.duration = 4.0
            breathe.autoreverses = true
            breathe.repeatCount = .infinity
            breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            ambient.layer.add(breathe, forKey: "breathe")
        }

        // Ripple rings
        for (i, ringView) in ringViews.enumerated() {
            ringView.layer.removeAllAnimations()

            let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
            scaleAnim.fromValue = 0.6
            scaleAnim.toValue = 2.8
            scaleAnim.duration = 3.0

            let fadeAnim = CABasicAnimation(keyPath: "opacity")
            fadeAnim.fromValue = 0.7
            fadeAnim.toValue = 0.0
            fadeAnim.duration = 3.0

            let group = CAAnimationGroup()
            group.animations = [scaleAnim, fadeAnim]
            group.duration = 3.0
            group.repeatCount = .infinity
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            group.timeOffset = Double(i) * 1.0
            ringView.layer.add(group, forKey: "ripple")
        }

        // Orbit 1
        if let ov1 = orbitView1 {
            ov1.layer.removeAllAnimations()
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = CGFloat.pi * 2
            spin.duration = 3.0
            spin.repeatCount = .infinity
            spin.timingFunction = CAMediaTimingFunction(name: .linear)
            ov1.layer.add(spin, forKey: "orbit")
        }

        // Orbit 2
        if let ov2 = orbitView2 {
            ov2.layer.removeAllAnimations()
            let spin2 = CABasicAnimation(keyPath: "transform.rotation.z")
            spin2.fromValue = 0
            spin2.toValue = -CGFloat.pi * 2
            spin2.duration = 4.5
            spin2.repeatCount = .infinity
            spin2.timingFunction = CAMediaTimingFunction(name: .linear)
            ov2.layer.add(spin2, forKey: "orbit2")
        }

        // Icon float + glow
        if let iv = iconView {
            iv.layer.removeAllAnimations()

            let float = CABasicAnimation(keyPath: "transform.translation.y")
            float.fromValue = -5
            float.toValue = 5
            float.duration = 2.5
            float.autoreverses = true
            float.repeatCount = .infinity
            float.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            iv.layer.add(float, forKey: "float")

            let glow = CABasicAnimation(keyPath: "shadowRadius")
            glow.fromValue = 22
            glow.toValue = 38
            glow.duration = 2.5
            glow.autoreverses = true
            glow.repeatCount = .infinity
            glow.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            iv.layer.add(glow, forKey: "glow")
        }

        // Title fade in
        if let title = titleLabel, title.alpha < 1 {
            UIView.animate(withDuration: 0.8, delay: 0.2, options: .curveEaseOut) {
                title.alpha = 1
            }
        }
    }

    // MARK: - Cleanup

    func stopAllAnimations() {
        stopped = true
        NotificationCenter.default.removeObserver(self)
        func strip(_ v: UIView) {
            v.layer.removeAllAnimations()
            v.layer.sublayers?.forEach { $0.removeAllAnimations() }
            v.subviews.forEach { strip($0) }
        }
        strip(self)
    }
}
