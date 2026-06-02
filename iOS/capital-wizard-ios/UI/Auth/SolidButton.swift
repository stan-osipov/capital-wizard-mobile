//
//  SolidButton.swift
//  capital-wizard-ios
//
//  Primary auth button for the design system.
//  Filled with the *text* colour, label drawn in the *background* colour:
//    • Light theme → near-black fill, light label.
//    • Dark theme  → near-white fill, dark label.
//  Exposes the same loading/success API as `GradientButton` so it is a
//  drop-in replacement for the auth primary action.
//

import UIKit

class SolidButton: UIButton {
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private var originalTitle: String?

    private lazy var windowsService: WindowsService? = ServiceManager.shared.getService()

    /// When `false` the button dims to 0.4 and ignores taps (used to gate the
    /// sign-up primary behind the Terms checkbox).
    var isFormEnabled: Bool = true {
        didSet { applyEnabledState() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupButton()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupButton() {
        layer.cornerRadius = 11
        layer.masksToBounds = true
        titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)

        setupActivityIndicator()
        applyColors()

        addTarget(self, action: #selector(touchDown), for: .touchDown)
        addTarget(self, action: #selector(touchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
    }

    private func applyColors() {
        let style = effectiveStyle
        let colors = AppColors.colors(for: style)
        // Fill = text colour, label = background colour (two-accent rule).
        backgroundColor = colors.dsText
        setTitleColor(colors.dsBackground, for: .normal)
        activityIndicator.color = colors.dsBackground
    }

    private var effectiveStyle: UIUserInterfaceStyle {
        if traitCollection.userInterfaceStyle != .unspecified {
            return traitCollection.userInterfaceStyle
        }
        return windowsService?.window.traitCollection.userInterfaceStyle ?? .dark
    }

    private func setupActivityIndicator() {
        activityIndicator.hidesWhenStopped = true
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    private func applyEnabledState() {
        isUserInteractionEnabled = isFormEnabled
        UIView.animate(withDuration: 0.2) {
            self.alpha = self.isFormEnabled ? 1.0 : 0.4
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            applyColors()
        }
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
            self.alpha     = self.isFormEnabled ? 1 : 0.4
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
        isUserInteractionEnabled = isFormEnabled
    }

    func showSuccess(completion: (() -> Void)? = nil) {
        let colors = AppColors.colors(for: effectiveStyle)

        let checkmark = UIImageView(image: UIImage(systemName: "checkmark"))
        checkmark.tintColor = colors.dsBackground
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

        let previousBackground = backgroundColor
        backgroundColor = colors.successGreen
        checkmark.tintColor = .white

        UIView.animate(withDuration: 0.3, animations: {
            checkmark.alpha     = 1
            checkmark.transform = .identity
        }) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.backgroundColor = previousBackground
                checkmark.removeFromSuperview()
                self.setTitle(self.originalTitle, for: .normal)
                completion?()
            }
        }
    }
}
