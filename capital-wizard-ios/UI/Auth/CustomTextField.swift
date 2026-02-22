//
//  CustomTextField.swift
//  capital-wizard-ios
//
//  Created by Roman on 07.02.2026.
//
import UIKit

/*
 Custom text feild for auth
 */
class CustomTextField: UIView {
    let textField = UITextField()
    
    private lazy var windowsService: WindowsService? = ServiceManager.shared.getService()
    
    init(placeholder: String, isSecure: Bool = false) {
        super.init(frame: .zero)
        setupView(placeholder: placeholder, isSecure: isSecure)
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    private func setupView(placeholder: String, isSecure: Bool) {
        guard let colors = windowsService?.colors else {
            return
        }
        backgroundColor    = colors.inputBackground
        layer.cornerRadius = 8
        layer.borderWidth  = 1
        layer.borderColor  = colors.inputBorder.cgColor
        
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: colors.textSecondary]
        )
        textField.textColor              = colors.textPrimary
        textField.isSecureTextEntry      = isSecure
        textField.font                   = .systemFont(ofSize: 16)
        textField.autocapitalizationType = .none
        addSubview(textField)
        
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            textField.topAnchor.constraint(equalTo: topAnchor),
            textField.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 50)
        ])
    }
}
