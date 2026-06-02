//
//  TermsCheckbox.swift
//  capital-wizard-ios
//
//  Design-system checkbox: an 18px box with a 1.5px border-strong outline.
//  When checked it fills with the amber accent and shows an on-accent glyph.
//  Tap target is expanded to ≥44px via the surrounding hit area.
//

import UIKit

class TermsCheckbox: UIControl {

    private let box = UIView()
    private let checkmark = UIImageView()

    private lazy var windowsService: WindowsService? = ServiceManager.shared.getService()

    /// Toggled selection state. Notifies `.valueChanged` observers on tap.
    var isChecked: Bool = false {
        didSet { updateState(animated: true) }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var effectiveStyle: UIUserInterfaceStyle {
        if traitCollection.userInterfaceStyle != .unspecified {
            return traitCollection.userInterfaceStyle
        }
        return windowsService?.window.traitCollection.userInterfaceStyle ?? .dark
    }
    private var colors: AppColors { AppColors.colors(for: effectiveStyle) }

    private func setup() {
        box.translatesAutoresizingMaskIntoConstraints = false
        box.isUserInteractionEnabled = false
        box.layer.cornerRadius = 5
        box.layer.borderWidth = 1.5
        addSubview(box)

        let config = UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)
        checkmark.image = UIImage(systemName: "checkmark", withConfiguration: config)?
            .withRenderingMode(.alwaysTemplate)
        checkmark.contentMode = .center
        checkmark.alpha = 0
        checkmark.translatesAutoresizingMaskIntoConstraints = false
        checkmark.isUserInteractionEnabled = false
        box.addSubview(checkmark)

        NSLayoutConstraint.activate([
            // 44pt hit target with an 18pt visual box pinned to the leading/top.
            widthAnchor.constraint(equalToConstant: 44),
            heightAnchor.constraint(equalToConstant: 44),

            box.widthAnchor.constraint(equalToConstant: 18),
            box.heightAnchor.constraint(equalToConstant: 18),
            box.leadingAnchor.constraint(equalTo: leadingAnchor),
            box.topAnchor.constraint(equalTo: topAnchor, constant: 1),

            checkmark.centerXAnchor.constraint(equalTo: box.centerXAnchor),
            checkmark.centerYAnchor.constraint(equalTo: box.centerYAnchor)
        ])

        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        updateState(animated: false)
    }

    @objc private func tapped() {
        isChecked.toggle()
        sendActions(for: .valueChanged)
        // Little pop on toggle.
        UIView.animate(withDuration: 0.1, animations: {
            self.box.transform = CGAffineTransform(scaleX: 1.18, y: 1.18)
        }) { _ in
            UIView.animate(withDuration: 0.1) { self.box.transform = .identity }
        }
    }

    /// Visual emphasis when the user tries to continue without accepting.
    func shake() {
        let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
        shake.values = [-8, 8, -6, 6, -4, 4, 0]
        shake.duration = 0.4
        box.layer.add(shake, forKey: "shake")
        box.layer.borderColor = colors.errorRed.cgColor
    }

    private func updateState(animated: Bool) {
        let colors = self.colors
        let apply = {
            if self.isChecked {
                self.box.backgroundColor = colors.dsAccent
                self.box.layer.borderColor = colors.dsAccent.cgColor
                self.checkmark.tintColor = colors.dsOnAccent
                self.checkmark.alpha = 1
            } else {
                self.box.backgroundColor = .clear
                self.box.layer.borderColor = colors.dsBorderStrong.cgColor
                self.checkmark.alpha = 0
            }
        }
        if animated {
            UIView.animate(withDuration: 0.15, animations: apply)
        } else {
            apply()
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            updateState(animated: false)
        }
    }
}
