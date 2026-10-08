import UIKit

/// Geometry from the approved Coding Lab Experiment icon (48-unit viewbox).
enum CodingLabMark {
    static func outline(in rect: CGRect) -> CGPath {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 21, y: 6))
        path.addLine(to: CGPoint(x: 21, y: 18))
        path.addLine(to: CGPoint(x: 9.5, y: 37.5))
        path.addQuadCurve(to: CGPoint(x: 13, y: 42), controlPoint: CGPoint(x: 8, y: 42))
        path.addLine(to: CGPoint(x: 35, y: 42))
        path.addQuadCurve(to: CGPoint(x: 38.5, y: 37.5), controlPoint: CGPoint(x: 40, y: 42))
        path.addLine(to: CGPoint(x: 27, y: 18))
        path.addLine(to: CGPoint(x: 27, y: 6))
        path.addLine(to: CGPoint(x: 21, y: 6))
        var transform = CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: rect.width / 48, y: rect.height / 48)
        return path.cgPath.copy(using: &transform)!
    }
}
