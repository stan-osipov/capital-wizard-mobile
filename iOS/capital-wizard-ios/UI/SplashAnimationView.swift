//
//  SplashAnimationView.swift
//  capital-wizard-ios
//
//  "Line Draw" boot loader — the Capital Wizard W mark plotted as a rising
//  chart line. A faint full W (track) sits underneath; an amber stroke draws
//  itself along it, holds, fades, and repeats. Wordmark + a mono status
//  caption sit below. Theme-aware (light + dark) via the design-system tokens.
//
//  Source of truth: design_handoff_loader/ (README.md + "Line Draw Loader.html").
//

import UIKit

class SplashAnimationView: UIView {

    // MARK: - Geometry constants

    /// The W mark, traced from the app icon, on a 0–100 coordinate space.
    /// M13 45 L31 83 L45 34 L63.5 66 L87 18 — an asymmetric, upward-trending
    /// chart zig-zag (NOT a symmetric W).
    private static let markPoints: [CGPoint] = [
        CGPoint(x: 13,   y: 45),
        CGPoint(x: 31,   y: 83),
        CGPoint(x: 45,   y: 34),
        CGPoint(x: 63.5, y: 66),
        CGPoint(x: 87,   y: 18)
    ]

    /// 118pt mark centered in a 130pt box.
    private static let boxSize: CGFloat   = 130
    private static let markSize: CGFloat  = 118
    /// Stroke width 6 in the 0–100 space, scaled to the box.
    private static let baseStrokeWidth: CGFloat = 6

    /// 2.4s draw loop, cubic-bezier(0.65, 0, 0.35, 1), infinite.
    private static let drawDuration: CFTimeInterval = 2.4
    /// Trailing dots cycle.
    private static let dotsInterval: TimeInterval = 1.4

    let createdAt = CACurrentMediaTime()

    // MARK: - Layer / view references

    private let markContainer = UIView()
    private let trackLayer = CAShapeLayer()
    private let lineLayer  = CAShapeLayer()
    private let wordmarkLabel = UILabel()
    private var statusLabel: UILabel?
    /// Separate label for the animated trailing dots so the cycling timer never
    /// fights the status text driven through `postStatus`.
    private let dotsLabel = UILabel()

    private var dotsTimer: Timer?
    private var dotsStep = 0
    private var stopped = false

    /// The draw loop starts exactly once, after the view is in a window and the
    /// shape layers have real geometry — so the first cycle can't be interrupted
    /// by an early (path-less) start or a second lifecycle callback.
    private var didStartDraw = false
    private var lastLaidOutBounds: CGRect = .zero

    // MARK: - Theme

    /// Resolve the effective interface style from the view's own trait
    /// collection, falling back to the window when the preference is `.system`.
    private var effectiveStyle: UIUserInterfaceStyle {
        if traitCollection.userInterfaceStyle != .unspecified {
            return traitCollection.userInterfaceStyle
        }
        return window?.traitCollection.userInterfaceStyle ?? .dark
    }

    private var colors: AppColors { AppColors.colors(for: effectiveStyle) }

    // MARK: - Status updates

    static let statusNotification = Notification.Name("SplashStatusUpdate")

    nonisolated static func postStatus(_ text: String) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: statusNotification, object: nil, userInfo: ["text": text])
        }
    }

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
        dotsTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Window lifecycle

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil && !stopped {
            applyThemeColors()
            startDrawIfNeeded()
            // Re-apply animations when the app returns from background.
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
        // Small delay to let the system settle after foregrounding.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self = self, !self.stopped else { return }
            // Only resume if the draw was actually cleared (e.g. the system
            // removed it during a real background trip). Never restart an
            // in-flight cycle — that's what made the first run stutter.
            if self.lineLayer.animation(forKey: "cwDraw") == nil {
                self.applyAnimations()
            }
        }
    }

    // MARK: - Build views (no animations here)

    private func buildUI() {
        backgroundColor = colors.dsBackground

        // ── Mark container (130pt box, centered, lifted to leave room for the
        //    wordmark + caption below) ──
        markContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(markContainer)

        // Track: faint full W underneath.
        trackLayer.fillColor = UIColor.clear.cgColor
        trackLayer.lineCap = .round
        trackLayer.lineJoin = .round

        // Line: amber W that draws itself.
        lineLayer.fillColor = UIColor.clear.cgColor
        lineLayer.lineCap = .round
        lineLayer.lineJoin = .round
        lineLayer.strokeEnd = 0
        // Amber glow ≈ CSS drop-shadow(0 0 6px var(--accent-soft)).
        lineLayer.shadowRadius = 6
        lineLayer.shadowOpacity = 1
        lineLayer.shadowOffset = .zero

        markContainer.layer.addSublayer(trackLayer)
        markContainer.layer.addSublayer(lineLayer)

        // ── Wordmark "Capital Wizard": 21pt semibold, letter-spacing -0.01 ──
        wordmarkLabel.attributedText = makeWordmarkText()
        wordmarkLabel.textAlignment = .center
        wordmarkLabel.numberOfLines = 1
        wordmarkLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(wordmarkLabel)

        // ── Status caption row: status text + animated trailing dots ──
        let status = UILabel()
        status.text = defaultCaption()
        status.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        status.textColor = colors.dsTextSubtle
        status.textAlignment = .right
        status.numberOfLines = 1
        status.setContentHuggingPriority(.required, for: .horizontal)
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusLabel = status

        dotsLabel.text = UIAccessibility.isReduceMotionEnabled ? "\u{2026}" : ""
        dotsLabel.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        dotsLabel.textColor = colors.dsTextSubtle
        dotsLabel.textAlignment = .left
        dotsLabel.numberOfLines = 1
        dotsLabel.setContentHuggingPriority(.required, for: .horizontal)
        dotsLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        // Hold the dots column at a fixed width so the centered status text
        // doesn't shift as the dots cycle (· → ·· → ···).
        let captionStack = UIStackView(arrangedSubviews: [status, dotsLabel])
        captionStack.axis = .horizontal
        captionStack.alignment = .firstBaseline
        captionStack.spacing = 0
        captionStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(captionStack)

        NSLayoutConstraint.activate([
            // Mark box: centered horizontally, slightly above center so the
            // wordmark below keeps the group visually balanced.
            markContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            markContainer.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -28),
            markContainer.widthAnchor.constraint(equalToConstant: Self.boxSize),
            markContainer.heightAnchor.constraint(equalToConstant: Self.boxSize),

            // Wordmark: 40pt below the mark.
            wordmarkLabel.topAnchor.constraint(equalTo: markContainer.bottomAnchor, constant: 40),
            wordmarkLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            wordmarkLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            wordmarkLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),

            // Caption: pinned ~54pt above the bottom safe-area, centered.
            captionStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            captionStack.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -54),
            captionStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            captionStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),

            // Reserve a steady width for up to three dots.
            dotsLabel.widthAnchor.constraint(equalToConstant: 22)
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onStatusUpdate(_:)),
            name: SplashAnimationView.statusNotification,
            object: nil
        )
    }

    /// "Capital Wizard" — 21pt semibold, letter-spacing -0.01em (≈ -0.21pt at 21pt).
    private func makeWordmarkText() -> NSAttributedString {
        NSAttributedString(
            string: "Capital Wizard",
            attributes: [
                .font: UIFont.systemFont(ofSize: 21, weight: .semibold),
                .kern: -0.21,
                .foregroundColor: colors.dsText
            ]
        )
    }

    /// Localized "Crunching the numbers" if the key exists, else the literal.
    private func defaultCaption() -> String {
        let key = "loader.caption"
        let resolved = L(key)
        // `L` returns the key itself when the string is missing.
        return resolved == key ? "Crunching the numbers" : resolved
    }

    // MARK: - Geometry

    /// Builds the W path scaled to a 118pt mark centered in the 130pt box.
    private func makeMarkPath() -> CGPath {
        let scale = Self.markSize / 100.0          // 0–100 space → 118pt
        let inset = (Self.boxSize - Self.markSize) / 2  // center in the box
        let path = UIBezierPath()
        for (i, p) in Self.markPoints.enumerated() {
            let point = CGPoint(x: inset + p.x * scale, y: inset + p.y * scale)
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path.cgPath
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        // (Re)build the shape only when the box geometry actually changes, so a
        // routine layout pass never disturbs an in-flight draw.
        let bounds = markContainer.bounds
        if bounds != lastLaidOutBounds {
            lastLaidOutBounds = bounds
            let width = Self.baseStrokeWidth * (Self.markSize / 100.0)  // stroke 6 scaled
            let path = makeMarkPath()
            for layer in [trackLayer, lineLayer] {
                layer.frame = bounds
                layer.path = path
                layer.lineWidth = width
            }
        }

        // The path is ready now — safe to begin the draw (runs once).
        startDrawIfNeeded()
    }

    /// Begins the draw loop the first time the view is both in a window and laid
    /// out with real geometry. The `didStartDraw` guard prevents a second
    /// lifecycle callback (re-layout / re-attach / a launch-time foreground
    /// event) from wiping the partial first cycle and restarting it.
    private func startDrawIfNeeded() {
        guard !stopped, !didStartDraw, window != nil, markContainer.bounds.width > 0 else { return }
        didStartDraw = true
        applyAnimations()
    }

    // MARK: - Theme colors

    /// Applies every directly-set color from the resolved palette. Safe to call
    /// repeatedly (initial build, window attach, and live appearance changes).
    private func applyThemeColors() {
        let colors = self.colors
        backgroundColor = colors.dsBackground

        trackLayer.strokeColor = colors.dsBorder.cgColor
        lineLayer.strokeColor  = colors.dsAccent.cgColor
        lineLayer.shadowColor  = colors.dsAccentSoft.cgColor

        wordmarkLabel.attributedText = makeWordmarkText()
        statusLabel?.textColor = colors.dsTextSubtle
        dotsLabel.textColor = colors.dsTextSubtle
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            applyThemeColors()
        }
    }

    @objc private func onStatusUpdate(_ notification: Notification) {
        guard let text = notification.userInfo?["text"] as? String else { return }
        statusLabel?.text = text
    }

    // MARK: - Apply animations (called when in window hierarchy)

    private func applyAnimations() {
        lineLayer.removeAllAnimations()

        // Reduced motion: show the completed amber W, no draw loop, static "…".
        guard !UIAccessibility.isReduceMotionEnabled else {
            lineLayer.strokeEnd = 1
            lineLayer.opacity = 1
            dotsTimer?.invalidate()
            dotsTimer = nil
            dotsLabel.text = "\u{2026}"
            return
        }

        // Grouped keyframe draw: strokeEnd 0→1 over the first 55%, hold drawn
        // until 80%, then fade opacity 1→0 by 100%. `strokeEnd` is the UIKit
        // equivalent of the handoff's stroke-dashoffset draw.
        let timing = CAMediaTimingFunction(controlPoints: 0.65, 0, 0.35, 1)

        // Per-segment easing: a CAKeyframeAnimation ignores a single
        // `timingFunction` (its segments would interpolate linearly). Supplying
        // a `timingFunctions` array (one per segment, count == keyTimes - 1)
        // applies the cubic-bezier to each segment — matching how the CSS
        // `animation-timing-function` eases between every keyframe in the handoff.
        let draw = CAKeyframeAnimation(keyPath: "strokeEnd")
        draw.values = [0, 1, 1]
        draw.keyTimes = [0, 0.55, 1]
        draw.timingFunctions = [timing, timing]

        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1, 1, 0]
        fade.keyTimes = [0, 0.8, 1]
        fade.timingFunctions = [timing, timing]

        let group = CAAnimationGroup()
        group.animations = [draw, fade]
        group.duration = Self.drawDuration
        group.repeatCount = .infinity
        group.isRemovedOnCompletion = false
        group.fillMode = .both
        lineLayer.add(group, forKey: "cwDraw")

        startDotsTimer()
    }

    // MARK: - Trailing dots

    private func startDotsTimer() {
        dotsTimer?.invalidate()
        dotsStep = 0
        dotsLabel.text = ""
        // 4-step cycle ("" → · → ·· → ···) over `dotsInterval`, matching the
        // CSS steps(4, end) loop.
        let timer = Timer.scheduledTimer(withTimeInterval: Self.dotsInterval / 4,
                                         repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.dotsStep = (self.dotsStep + 1) % 4
            self.dotsLabel.text = String(repeating: "\u{00b7}", count: self.dotsStep)
        }
        RunLoop.main.add(timer, forMode: .common)
        dotsTimer = timer
    }

    // MARK: - Cleanup

    func stopAllAnimations() {
        stopped = true
        dotsTimer?.invalidate()
        dotsTimer = nil
        NotificationCenter.default.removeObserver(self)
        func strip(_ v: UIView) {
            v.layer.removeAllAnimations()
            v.layer.sublayers?.forEach { $0.removeAllAnimations() }
            v.subviews.forEach { strip($0) }
        }
        strip(self)
    }
}
