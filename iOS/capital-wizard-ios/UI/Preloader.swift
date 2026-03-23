//
//  Preloader.swift
//  capital-wizard-ios
//
//  Created by Roman on 07.02.2026.
//

import UIKit

/// Simple fullscreen Preloader view with UIActivityIndicatorView
class Preloader: UIView {
    private var indicator: UIActivityIndicatorView?
        
    init(in view: UIView) {
        super.init(frame: view.frame)
        setupView(in: view)
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    func show() {
        self.isHidden = false
        indicator?.startAnimating()
    }
    
    func hide() {
        self.isHidden = true
        indicator?.stopAnimating()
    }
    
    private func setupView(in view: UIView) {
        self.isOpaque = true
        
        self.backgroundColor = .clear
        
        view.addSubview(self)
        self.translatesAutoresizingMaskIntoConstraints = false
        self.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        self.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        self.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        self.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
  
        
        let blurEffect = UIBlurEffect(style: UIBlurEffect.Style.systemChromeMaterialDark)
        let blurEffectView = UIVisualEffectView(effect: blurEffect)
        blurEffectView.backgroundColor = .clear
        blurEffectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        self.addSubview(blurEffectView)
        blurEffectView.frame = self.bounds
        
        
        let indicator = UIActivityIndicatorView()
            
        indicator.style = .large
        indicator.color = .white

        indicator.autoresizingMask = [
            .flexibleLeftMargin, .flexibleRightMargin,
            .flexibleTopMargin, .flexibleBottomMargin
        ]
        
        indicator.center = CGPoint(
            x: self.bounds.midX,
            y: self.bounds.midY
        )
        self.addSubview(indicator)
        
        self.indicator = indicator
    }
}
