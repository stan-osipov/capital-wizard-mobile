//
//  SocialButton.swift
//  capital-wizard-ios
//
//  Secondary auth button used for the social providers (Google + Apple).
//  Surface fill + 1px border-strong, an icon on the leading edge and a
//  centred label. Both providers share this style so neither competes with
//  the primary action (which is a solid text-colour fill).
//

import UIKit

class SocialButton: UIButton {

    enum Provider {
        case google
        case apple
    }

    private let provider: Provider
    private let iconView = UIImageView()
    private let label = UILabel()

    private lazy var windowsService: WindowsService? = ServiceManager.shared.getService()

    init(provider: Provider, title: String) {
        self.provider = provider
        super.init(frame: .zero)
        setupButton(title: title)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Updates the visible title. The button renders its title through a
    /// private label, so locale changes must be applied through this setter.
    func updateTitle(_ title: String) {
        label.text = title
    }

    private func setupButton(title: String) {
        layer.cornerRadius = 11
        layer.borderWidth = 1

        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.isUserInteractionEnabled = false
        addSubview(iconView)

        label.text = title
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isUserInteractionEnabled = false
        addSubview(label)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),

            // Centre the label across the whole button; keep clear of the icon.
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: iconView.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -18)
        ])

        applyColors()

        addTarget(self, action: #selector(touchDown), for: .touchDown)
        addTarget(self, action: #selector(touchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
    }

    private var effectiveStyle: UIUserInterfaceStyle {
        if traitCollection.userInterfaceStyle != .unspecified {
            return traitCollection.userInterfaceStyle
        }
        return windowsService?.window.traitCollection.userInterfaceStyle ?? .dark
    }

    private func applyColors() {
        let colors = AppColors.colors(for: effectiveStyle)
        backgroundColor = colors.dsSurface
        layer.borderColor = colors.dsBorderStrong.cgColor
        label.textColor = colors.dsText

        switch provider {
        case .google:
            iconView.image = GoogleIconRenderer.render(size: 20)
        case .apple:
            // Monochrome Apple glyph tinted with the current text colour.
            let config = UIImage.SymbolConfiguration(pointSize: 19, weight: .medium)
            iconView.image = UIImage(systemName: "applelogo", withConfiguration: config)?
                .withRenderingMode(.alwaysTemplate)
            iconView.tintColor = colors.dsText
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            applyColors()
        }
    }

    @objc private func touchDown() {
        let colors = AppColors.colors(for: effectiveStyle)
        UIView.animate(withDuration: 0.1) {
            self.transform = CGAffineTransform(scaleX: 0.98, y: 0.98)
            self.backgroundColor = colors.dsSurfaceHover
        }
    }

    @objc private func touchUp() {
        let colors = AppColors.colors(for: effectiveStyle)
        UIView.animate(withDuration: 0.1) {
            self.transform = .identity
            self.backgroundColor = colors.dsSurface
        }
    }
}
