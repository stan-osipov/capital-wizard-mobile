//
//  GradientButton.swift
//  capital-wizard-ios
//
//  Created by Roman on 07.02.2026.
//

import UIKit

class GradientButton: UIButton {
    private let gradientLayer     = CAGradientLayer()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private var originalTitle: String?
    
    private lazy var windwosService: WindowsService? = ServiceManager.shared.getService()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupGradient()
        setupActivityIndicator()
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    private func setupGradient() {
        guard let colors = windwosService?.colors else {
            return
        }
        
        gradientLayer.colors       = [colors.gradientFirst.cgColor,
                                      colors.gradientSecond.cgColor]
        gradientLayer.startPoint   = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint     = CGPoint(x: 1, y: 0.5)
        gradientLayer.cornerRadius = 8
        layer.insertSublayer(gradientLayer, at: 0)
        
        setTitleColor(.white, for: .normal)
        titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        
        addTarget(self, action: #selector(touchDown), for: .touchDown)
        addTarget(self, action: #selector(touchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
    }
    
    private func setupActivityIndicator() {
        activityIndicator.color = .white
        activityIndicator.hidesWhenStopped = true
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(activityIndicator)
        
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
    }
    
    @objc private func touchDown() {
        UIView.animate(withDuration: 0.1) {
            self.transform = CGAffineTransform(scaleX: 0.97, y: 0.97)
            self.alpha     = 0.9
        }
    }
    
    @objc private func touchUp() {
        UIView.animate(withDuration: 0.1) {
            self.transform = .identity
            self.alpha     = 1
        }
    }
    
    func startLoading() {
        originalTitle = title(for: .normal)
        setTitle("", for: .normal)
        activityIndicator.startAnimating()
        isUserInteractionEnabled = false
    }
    
    func stopLoading() {
        activityIndicator.stopAnimating()
        setTitle(originalTitle, for: .normal)
        isUserInteractionEnabled = true
    }
    
    func showSuccess(completion: (() -> Void)? = nil) {
        guard let colors = windwosService?.colors else {
            completion?()
            return
        }
        
        let checkmark = UIImageView(image: UIImage(systemName: "checkmark"))
        checkmark.tintColor = .white
        checkmark.alpha = 0
        checkmark.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        checkmark.translatesAutoresizingMaskIntoConstraints = false
        addSubview(checkmark)
        
        NSLayoutConstraint.activate([
            checkmark.centerXAnchor.constraint(equalTo: centerXAnchor),
            checkmark.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        
        originalTitle = title(for: .normal)
        setTitle("", for: .normal)
        
        // Success green gradient
        gradientLayer.colors = [colors.successGreen.cgColor,
                                colors.successGreen.cgColor]
        
        UIView.animate(withDuration: 0.3, animations: {
            checkmark.alpha     = 1
            checkmark.transform = .identity
        }) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.gradientLayer.colors = [colors.gradientFirst.cgColor,
                                             colors.gradientSecond.cgColor]
                checkmark.removeFromSuperview()
                self.setTitle(self.originalTitle, for: .normal)
                completion?()
            }
        }
    }
}
