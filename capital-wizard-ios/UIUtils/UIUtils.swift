//
//  UIUtils.swift
//  capital-wizard-ios
//
//  Created by Roman on 07.02.2026.
//

import UIKit

class RoundImageView: UIImageView {
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }
}

class CustomTitleView: UIView {
    override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.layoutFittingExpandedSize.width, height: UIView.noIntrinsicMetric)
    }
}

class RoundButton: UIButton {
    private var isImageRounded: Bool = true
    private var showGrarient:   Bool = false
    private var gradient:       CAGradientLayer?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    init(isImageRounded: Bool = true, showGrarient: Bool = false) {
        self.isImageRounded = isImageRounded
        self.showGrarient   = showGrarient
        super.init(frame: .zero)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()

        layer.cornerRadius = bounds.height / 2
        if isImageRounded {
            imageView?.layer.cornerRadius = frame.height/2
        }
        
        show()
    }
    
    func show() {
        if showGrarient {
            gradient?.removeFromSuperlayer()
            
            let gradient = CAGradientLayer()
            gradient.frame = bounds
            let startPoint: CGPoint = CGPoint(x: 0.5, y: 0)
            let endPoint:   CGPoint = CGPoint(x: 0.5, y: 1)
            gradient.startPoint = startPoint
            gradient.endPoint   = endPoint
            let fromColor  = UIColor(red: 72/255, green: 203/255, blue: 211/255, alpha: 1)
            let toColor    = UIColor(red: 37/255, green: 105/255, blue: 109/255, alpha: 1)
            gradient.colors = [fromColor, toColor]

            let shape = CAShapeLayer()
            shape.lineWidth = 5
            shape.path = UIBezierPath(roundedRect: bounds, cornerRadius: frame.height/2).cgPath
            shape.strokeColor = UIColor.white.cgColor
            shape.fillColor   = UIColor.clear.cgColor
            gradient.mask = shape

            self.layer.addSublayer(gradient)
            self.gradient = gradient
            gradient.zPosition = 0
        }
    }
}

extension UIImage {
    func withRoundedBackground(
        backgroundColor: UIColor = .clear,
        iconColor: UIColor? = nil,
        size: CGSize = CustomTabBarConst.itemSize,
        cornerRadius: CGFloat = CustomTabBarConst.cornerRadius
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
            backgroundColor.setFill()
            path.fill()

            let maxIconBox = CGSize(width: size.width * 0.6, height: size.height * 0.6)

            let widthRatio = maxIconBox.width / self.size.width
            let heightRatio = maxIconBox.height / self.size.height
            let scale = min(widthRatio, heightRatio)

            let finalIconSize = CGSize(
                width: self.size.width * scale,
                height: self.size.height * scale
            )

            let iconOrigin = CGPoint(
                x: (size.width - finalIconSize.width) / 2,
                y: (size.height - finalIconSize.height) / 2
            )
            let iconRect = CGRect(origin: iconOrigin, size: finalIconSize)

            var imageToDraw = self
            if let iconColor = iconColor {
                imageToDraw = self.tintedImage(with: iconColor)
            }

            imageToDraw.draw(in: iconRect)
        }
    }
    
    func tintedImage(with color: UIColor) -> UIImage {
        let rect = CGRect(origin: .zero, size: size)

        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        color.setFill()
        guard let context = UIGraphicsGetCurrentContext(), let cgImage = self.cgImage else {
            return self
        }

        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1.0, y: -1.0)

        context.clip(to: rect, mask: cgImage)
        context.fill(rect)

        let tintedImage = UIGraphicsGetImageFromCurrentImageContext() ?? self
        UIGraphicsEndImageContext()
        return tintedImage
    }
}
