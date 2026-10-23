import UIKit

/// Native counterpart of FlaskLoader.tsx / flask-loader.css. The same 48-unit
/// paths, 96pt glyph, 22pt caption gap and wall-clock phases also run on Android.
/// The web owns the fill/flood exit once its first painted frame takes over.
final class CodingLabSplashView: UIView {
    private var timer: Timer?
    private var stopped = false
    private let caption = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true
        caption.attributedText = NSAttributedString(string: L("loader.caption"), attributes: [.kern: 0.66])
        caption.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        caption.textAlignment = .center
        addSubview(caption)
        accessibilityLabel = caption.text
        isAccessibilityElement = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        timer?.invalidate()
        timer = nil
        guard window != nil, !stopped else { return }
        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in self?.setNeedsDisplay() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
    func stopAnimating() { stopped = true; timer?.invalidate(); timer = nil }
    deinit { timer?.invalidate() }

    private var stageTop: CGFloat {
        (bounds.height + safeAreaInsets.top - safeAreaInsets.bottom - 129) / 2
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        caption.frame = CGRect(x: 12, y: stageTop + 118, width: bounds.width - 24, height: 14)
    }

    // CSS cubic-bezier, solved for x before evaluating y. Same as Android's
    // PathInterpolator; using just y(t) would produce a different speed curve.
    private func ease(_ x: Double, _ x1: Double, _ x2: Double) -> Double {
        var lo = 0.0, hi = 1.0
        for _ in 0..<18 {
            let t = (lo + hi) / 2, u = 1 - t
            if 3*u*u*t*x1 + 3*u*t*t*x2 + t*t*t < x { lo = t } else { hi = t }
        }
        let t = (lo + hi) / 2
        return 3*(1-t)*t*t + t*t*t
    }
    private func phase(_ seconds: Double, delay: Double = 0) -> Double {
        let t = Date().timeIntervalSince1970 - delay
        return t.truncatingRemainder(dividingBy: seconds) / seconds
    }

    override func draw(_ rect: CGRect) {
        guard let c = UIGraphicsGetCurrentContext() else { return }
        let dark = traitCollection.userInterfaceStyle == .dark
        let soft = dark && UserDefaults.standard.string(forKey: WindowsServiceConst.webThemeKey) == "dark-soft"
        let bg = UIColor(oklchL: soft ? 0.24 : dark ? 0.16 : 0.985, chroma: soft ? 0.008 : dark ? 0.005 : 0.003, hueDegrees: soft ? 248 : 240)
        let ink = UIColor(oklchL: soft ? 0.86 : dark ? 0.96 : 0.18, chroma: soft ? 0.005 : dark ? 0.003 : 0.01, hueDegrees: soft ? 248 : 240)
        caption.textColor = UIColor(oklchL: soft ? 0.52 : dark ? 0.55 : 0.62, chroma: 0.008, hueDegrees: soft ? 248 : 240)
        let accent = AppColors.webAccent(isDark: dark, soft: soft).accent
        bg.setFill(); c.fill(bounds)
        c.saveGState()
        c.translateBy(x: (bounds.width - 96) / 2, y: stageTop)
        c.scaleBy(x: 2, y: 2)
        let reduced = UIAccessibility.isReduceMotionEnabled
        // Match the web's reduced-motion pulse; no moving liquid, bubbles or steam.
        if reduced { c.setAlpha(CGFloat(1 - 0.55 * (1 - cos(phase(1.4) * 2 * .pi)) / 2)) }
        let glass = UIBezierPath()
        glass.move(to: CGPoint(x:21,y:6)); glass.addLine(to: CGPoint(x:21,y:18))
        glass.addLine(to: CGPoint(x:9.5,y:37.5))
        glass.addQuadCurve(to: CGPoint(x:13,y:42), controlPoint: CGPoint(x:8,y:42))
        glass.addLine(to: CGPoint(x:35,y:42))
        glass.addQuadCurve(to: CGPoint(x:38.5,y:37.5), controlPoint: CGPoint(x:40,y:42))
        glass.addLine(to: CGPoint(x:27,y:18)); glass.addLine(to: CGPoint(x:27,y:6))
        c.saveGState()
        c.addPath(glass.cgPath); c.closePath(); c.clip()
        c.translateBy(x: reduced ? 0 : CGFloat(-12 + 12 * phase(1.4)), y:29)
        let wave = UIBezierPath(); wave.move(to: CGPoint(x:-48,y:0))
        for x in stride(from: -48, to: 96, by: 12) {
            wave.addQuadCurve(to: CGPoint(x:x+6,y:0), controlPoint: CGPoint(x:Double(x)+3,y:-2.6))
            wave.addQuadCurve(to: CGPoint(x:x+12,y:0), controlPoint: CGPoint(x:Double(x)+9,y:2.6))
        }
        wave.addLine(to: CGPoint(x:96,y:60)); wave.addLine(to: CGPoint(x:-48,y:60)); wave.close()
        accent.setFill(); wave.fill(); c.restoreGState()
        if !reduced {
            let bubbles: [(Double,Double,Double,Double,Double)] = [(20,38,1.7,0,-2),(26,39,1.3,0.8,2),(23,37,2,1.6,-1)]
            for (x,y,r,delay,dx) in bubbles {
                let p = phase(1.4, delay:delay), move = ease(p,0.4,0.6)
                let alpha = p < 0.12 ? ease(p/0.12,0.4,0.6) : p < 0.75 ? 1 : 1-ease((p-0.75)/0.25,0.4,0.6)
                c.saveGState(); c.setAlpha(CGFloat(alpha))
                let bubble = UIBezierPath(ovalIn: CGRect(x:x+dx*move-r,y:y-36*move-r,width:r*2,height:r*2))
                accent.setFill(); bg.setStroke(); bubble.lineWidth = 1.1; bubble.fill(); bubble.stroke()
                c.restoreGState()
            }
        }
        ink.setStroke(); glass.lineWidth = 3.4; glass.lineCapStyle = .round; glass.lineJoinStyle = .round; glass.stroke()
        let cap = UIBezierPath(); cap.move(to: CGPoint(x:18.5,y:6)); cap.addLine(to: CGPoint(x:29.5,y:6))
        cap.lineWidth = 3.4; cap.lineCapStyle = .round; cap.stroke()
        if !reduced {
            for i in 0..<3 {
                let p = phase(1.8,delay:Double(i)*0.45), y = i == 1 ? 2.0 : 3.0
                let x = Double(21+i*3), dx = i == 1 ? 1.6 : -1.6
                let alpha = p < 0.35 ? 0.7*ease(p/0.35,0,0.58) : 0.7*(1-ease((p-0.35)/0.65,0,0.58))
                c.saveGState(); c.setAlpha(CGFloat(alpha)); c.translateBy(x:0,y:CGFloat(3-12*ease(p,0,0.58)))
                let steam = UIBezierPath(); steam.move(to: CGPoint(x:x,y:y))
                steam.addQuadCurve(to: CGPoint(x:x,y:y-4),controlPoint: CGPoint(x:x+dx,y:y-2))
                steam.addQuadCurve(to: CGPoint(x:x,y:y-8),controlPoint: CGPoint(x:x-dx,y:y-6))
                steam.lineWidth = 2; steam.lineCapStyle = .round; steam.stroke(); c.restoreGState()
            }
        }
        c.restoreGState()
    }
}
