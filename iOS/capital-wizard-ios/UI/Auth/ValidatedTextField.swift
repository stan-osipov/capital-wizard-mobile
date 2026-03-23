//
//  ValidatedTextField.swift
//  capital-wizard-ios
//
//  Created by Roman on 07.02.2026.
//

import UIKit

class ValidatedTextField: UIView {
    let textField = UITextField()
    private let errorLabel = UILabel()
    private let containerView = UIView()
    private var rightIcon: UIImageView?
    
    var text: String { textField.text ?? "" }
    var onTextChanged: ((String) -> Void)?
    
    private var isSecure: Bool = false
    private var showToggle: Bool = false
    
    private lazy var windowsService: WindowsService? = ServiceManager.shared.getService()
    
    init(placeholder: String, isSecure: Bool = false, showPasswordToggle: Bool = false) {
        self.isSecure = isSecure
        self.showToggle = showPasswordToggle
        super.init(frame: .zero)
        setupView(placeholder: placeholder, isSecure: isSecure)
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    private func setupView(placeholder: String, isSecure: Bool) {
        // Container
        containerView.backgroundColor = windowsService?.colors.inputBackground
        containerView.layer.cornerRadius = 8
        containerView.layer.borderWidth = 1
        containerView.layer.borderColor = windowsService?.colors.inputBorder.cgColor
        containerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(containerView)
        
        // Text Field
        textField.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: windowsService?.colors.textSecondary]
        )
        textField.textColor = windowsService?.colors.textPrimary
        textField.isSecureTextEntry = isSecure
        textField.font = .systemFont(ofSize: 16)
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.addTarget(self, action: #selector(textDidChange), for: .editingChanged)
        containerView.addSubview(textField)
        
        // Password Toggle
        if showToggle && isSecure {
            let toggleBtn = UIButton(type: .custom)
            toggleBtn.setImage(UIImage(systemName: "eye.slash.fill"), for: .normal)
            toggleBtn.setImage(UIImage(systemName: "eye.fill"), for: .selected)
            toggleBtn.tintColor = windowsService?.colors.textSecondary
            toggleBtn.addTarget(self, action: #selector(togglePassword(_:)), for: .touchUpInside)
            toggleBtn.translatesAutoresizingMaskIntoConstraints = false
            containerView.addSubview(toggleBtn)
            
            NSLayoutConstraint.activate([
                toggleBtn.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
                toggleBtn.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
                toggleBtn.widthAnchor.constraint(equalToConstant: 30),
                textField.trailingAnchor.constraint(equalTo: toggleBtn.leadingAnchor, constant: -8)
            ])
        } else {
            textField.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16).isActive = true
        }
        
        // Error Label
        errorLabel.font = .systemFont(ofSize: 12)
        errorLabel.textColor = windowsService?.colors.errorRed
        errorLabel.alpha = 0
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(errorLabel)
        
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.heightAnchor.constraint(equalToConstant: 50),
            
            textField.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            textField.topAnchor.constraint(equalTo: containerView.topAnchor),
            textField.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            
            errorLabel.topAnchor.constraint(equalTo: containerView.bottomAnchor, constant: 4),
            errorLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            errorLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            errorLabel.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    
    @objc private func textDidChange() {
        onTextChanged?(text)
        // Clear error when typing
        if errorLabel.alpha > 0 {
            clearError()
        }
    }
    
    @objc private func togglePassword(_ sender: UIButton) {
        sender.isSelected.toggle()
        textField.isSecureTextEntry = !sender.isSelected
    }
    
    func showError(_ message: String) {
        errorLabel.text = message
        containerView.layer.borderColor = windowsService?.colors.errorRed.cgColor
        
        // Shake animation
        let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
        shake.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        shake.values = [-12, 12, -8, 8, -4, 4, 0]
        shake.duration = 0.5
        containerView.layer.add(shake, forKey: "shake")
        
        // Fade in error
        UIView.animate(withDuration: 0.3) {
            self.errorLabel.alpha = 1
        }
    }
    
    func clearError() {
        UIView.animate(withDuration: 0.2) {
            self.errorLabel.alpha = 0
            self.containerView.layer.borderColor = self.windowsService?.colors.inputBorder.cgColor
        }
    }
    
    func showSuccess() {
        containerView.layer.borderColor = windowsService?.colors.successGreen.cgColor
        
        // Pulse animation
        UIView.animate(withDuration: 0.15, animations: {
            self.containerView.transform = CGAffineTransform(scaleX: 1.02, y: 1.02)
        }) { _ in
            UIView.animate(withDuration: 0.15) {
                self.containerView.transform = .identity
            }
        }
    }
}

