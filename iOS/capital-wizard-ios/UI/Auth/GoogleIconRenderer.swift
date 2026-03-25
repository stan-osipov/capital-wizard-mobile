//
//  GoogleIconRenderer.swift
//  capital-wizard-ios
//

import UIKit

enum GoogleIconRenderer {
    static func render(size: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { ctx in
            let cg = ctx.cgContext
            let center = CGPoint(x: size / 2, y: size / 2)
            let outerRadius = size / 2
            let innerRadius = size * 0.28
            let barHeight = size * 0.18

            let blue   = UIColor(red: 66/255,  green: 133/255, blue: 244/255, alpha: 1)
            let red    = UIColor(red: 234/255, green: 67/255,  blue: 53/255,  alpha: 1)
            let yellow = UIColor(red: 251/255, green: 188/255, blue: 5/255,   alpha: 1)
            let green  = UIColor(red: 52/255,  green: 168/255, blue: 83/255,  alpha: 1)

            // Draw 4 colored arc segments (outer ring of "G")
            // Angles: 0° is right (3 o'clock), going clockwise
            // Red: top-left quadrant (-150° to -45°)
            drawArc(cg, center: center, outer: outerRadius, inner: innerRadius,
                    startDeg: -150, endDeg: -45, color: red)

            // Yellow: bottom-left quadrant (-210° to -150°)
            drawArc(cg, center: center, outer: outerRadius, inner: innerRadius,
                    startDeg: -210, endDeg: -150, color: yellow)

            // Green: bottom quadrant (-270° to -210°)
            drawArc(cg, center: center, outer: outerRadius, inner: innerRadius,
                    startDeg: -270, endDeg: -210, color: green)

            // Blue: right quadrant (-45° to 0° and the horizontal bar)
            drawArc(cg, center: center, outer: outerRadius, inner: innerRadius,
                    startDeg: -45, endDeg: 0, color: blue)

            // Blue horizontal bar (the flat part of the "G")
            let barRect = CGRect(
                x: center.x - size * 0.02,
                y: center.y - barHeight / 2,
                width: outerRadius + size * 0.02,
                height: barHeight
            )
            cg.setFillColor(blue.cgColor)
            cg.fill(barRect)

        }.withRenderingMode(.alwaysOriginal)
    }

    private static func drawArc(_ cg: CGContext,
                                center: CGPoint,
                                outer: CGFloat,
                                inner: CGFloat,
                                startDeg: CGFloat,
                                endDeg: CGFloat,
                                color: UIColor) {
        let startRad = startDeg * .pi / 180
        let endRad = endDeg * .pi / 180

        let path = CGMutablePath()
        path.addArc(center: center, radius: outer,
                    startAngle: startRad, endAngle: endRad, clockwise: false)
        path.addArc(center: center, radius: inner,
                    startAngle: endRad, endAngle: startRad, clockwise: true)
        path.closeSubpath()

        cg.setFillColor(color.cgColor)
        cg.addPath(path)
        cg.fillPath()
    }
}
