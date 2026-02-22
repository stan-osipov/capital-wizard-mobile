//
//  ResetPasswordViewController.swift
//  capital-wizard-ios
//
//  Created by Roman on 07.02.2026.
//

import UIKit

class ResetPasswordViewController: UIViewController {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .pad ? .all : .portrait
    }

    private let cardView = AnimatedCardView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let emailField = ValidatedTextField(placeholder: "you@example.com")
    private let sendButton = GradientButton()
    private let backButton = UIButton(type: .system)
    private let termsLabel = UILabel()
    private let successView = UIView()
    
    private lazy var windowsService: WindowsService? = ServiceManager.shared.getService()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        cardView.animateIn()
        UIView.animate(withDuration: 0.25) { self.termsLabel.alpha = 1 }
    }
    
    private func setupUI() {
        view.backgroundColor = windowsService?.colors.backgroundColor
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        view.addGestureRecognizer(tap)
        
        cardView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cardView)
        
        titleLabel.text      = "Reset password"
        titleLabel.font      = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.textColor = windowsService?.colors.textPrimary
        
        subtitleLabel.text          = "Enter your email and we'll send you a reset link."
        subtitleLabel.font          = .systemFont(ofSize: 14)
        subtitleLabel.textColor     = windowsService?.colors.textSecondary
        subtitleLabel.numberOfLines = 0
        
        let emailLabel       = UILabel()
        emailLabel.text      = "Email Address"
        emailLabel.font      = .systemFont(ofSize: 14, weight: .medium)
        emailLabel.textColor = windowsService?.colors.textPrimary
        
        sendButton.setTitle("Send reset link", for: .normal)
        sendButton.addTarget(self, action: #selector(sendResetTapped), for: .touchUpInside)
        
        backButton.setTitle("Back to login", for: .normal)
        backButton.setTitleColor(windowsService?.colors.linkColor, for: .normal)
        backButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        
        termsLabel.text          = "By continuing, you agree to our Terms of Service and Privacy Policy"
        termsLabel.font          = .systemFont(ofSize: 12)
        termsLabel.textColor     = windowsService?.colors.textSecondary
        termsLabel.textAlignment = .center
        termsLabel.numberOfLines = 0
        termsLabel.translatesAutoresizingMaskIntoConstraints = false
        termsLabel.alpha = 0

        // Success View (hidden initially)
        setupSuccessView()
        
        [titleLabel, subtitleLabel, emailLabel, emailField, sendButton, backButton, successView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            cardView.addSubview($0)
        }
        view.addSubview(termsLabel)
        
        let cardWidth = cardView.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -48)
        cardWidth.priority = .defaultHigh

        NSLayoutConstraint.activate([
            cardView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cardView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            cardView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            cardView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            cardWidth,
            cardView.widthAnchor.constraint(lessThanOrEqualToConstant: 400),
            
            titleLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 32),
            titleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),
            
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),
            subtitleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -24),
            
            emailLabel.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 24),
            emailLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),
            
            emailField.topAnchor.constraint(equalTo: emailLabel.bottomAnchor, constant: 8),
            emailField.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),
            emailField.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -24),
            
            sendButton.topAnchor.constraint(equalTo: emailField.bottomAnchor, constant: 24),
            sendButton.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),
            sendButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -24),
            sendButton.heightAnchor.constraint(equalToConstant: 50),
            
            backButton.topAnchor.constraint(equalTo: sendButton.bottomAnchor, constant: 16),
            backButton.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
            backButton.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -32),
            
            successView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 24),
            successView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),
            successView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -24),
            
            termsLabel.topAnchor.constraint(equalTo: cardView.bottomAnchor, constant: 24),
            termsLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            termsLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40)
        ])
    }
    
    private func setupSuccessView() {
        successView.alpha = 0
        successView.isHidden = true
        
        let iconContainer                = UIView()
        iconContainer.backgroundColor    = windowsService?.colors.successGreen.withAlphaComponent(0.2)
        iconContainer.layer.cornerRadius = 30
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        
        let checkIcon = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
        checkIcon.tintColor = windowsService?.colors.successGreen
        checkIcon.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.addSubview(checkIcon)
        
        let successLabel           = UILabel()
        successLabel.text          = "Check your inbox!"
        successLabel.font          = .systemFont(ofSize: 16, weight: .semibold)
        successLabel.textColor     = windowsService?.colors.textPrimary
        successLabel.textAlignment = .center
        successLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let descLabel = UILabel()
        descLabel.text = "We've sent a password reset link to your email."
        descLabel.font = .systemFont(ofSize: 14)
        descLabel.textColor = windowsService?.colors.textSecondary
        descLabel.textAlignment = .center
        descLabel.numberOfLines = 0
        descLabel.translatesAutoresizingMaskIntoConstraints = false
        
        successView.addSubview(iconContainer)
        successView.addSubview(successLabel)
        successView.addSubview(descLabel)
        
        NSLayoutConstraint.activate([
            iconContainer.topAnchor.constraint(equalTo: successView.topAnchor),
            iconContainer.centerXAnchor.constraint(equalTo: successView.centerXAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: 60),
            iconContainer.heightAnchor.constraint(equalToConstant: 60),
            
            checkIcon.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            checkIcon.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            checkIcon.widthAnchor.constraint(equalToConstant: 32),
            checkIcon.heightAnchor.constraint(equalToConstant: 32),
            
            successLabel.topAnchor.constraint(equalTo: iconContainer.bottomAnchor, constant: 16),
            successLabel.centerXAnchor.constraint(equalTo: successView.centerXAnchor),
            
            descLabel.topAnchor.constraint(equalTo: successLabel.bottomAnchor, constant: 8),
            descLabel.leadingAnchor.constraint(equalTo: successView.leadingAnchor),
            descLabel.trailingAnchor.constraint(equalTo: successView.trailingAnchor),
            descLabel.bottomAnchor.constraint(equalTo: successView.bottomAnchor)
        ])
    }
    
    private func showSuccessState() {
        successView.isHidden = false
        successView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5) {
            self.successView.alpha = 1
            self.successView.transform = .identity
            self.emailField.alpha = 0
            self.sendButton.alpha = 0
        }
    }
    
    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }
    
    @objc private func sendResetTapped() {
        dismissKeyboard()
        
        if emailField.text.isEmpty {
            emailField.showError("Email is required")
            return
        }
        
        if !Validator.isValidEmail(emailField.text) {
            emailField.showError("Please enter a valid email address")
            return
        }
        
        sendButton.startLoading()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.sendButton.stopLoading()
            self.showSuccessState()
        }
    }
    
    @objc private func backTapped() {
        dismiss(animated: true)
    }
}
