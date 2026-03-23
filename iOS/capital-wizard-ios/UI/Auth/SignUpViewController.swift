//
//  SignUpViewController.swift
//  capital-wizard-ios
//
//  Created by Roman on 07.02.2026.
//

import UIKit

class SignUpViewController: UIViewController {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .pad ? .all : .portrait
    }
    
    private lazy var windowsService: WindowsService? = ServiceManager.shared.getService()

    private let cardView = AnimatedCardView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let emailField = ValidatedTextField(placeholder: "you@example.com")
    private let passwordField = ValidatedTextField(placeholder: "••••••••", isSecure: true, showPasswordToggle: true)
    private let confirmPasswordField = ValidatedTextField(placeholder: "••••••••", isSecure: true, showPasswordToggle: true)
    private let termsCheckbox = UIButton(type: .custom)
    private let createButton = GradientButton()
    private let googleButton = GoogleButton()
    private let loginButton = UIButton(type: .system)
    private let termsLabel = UILabel()
    private var termsAccepted = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupValidation()
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
        
        titleLabel.text = "Create your account"
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.textColor = windowsService?.colors.textPrimary
        
        subtitleLabel.text = "Join thousands using our platform"
        subtitleLabel.font = .systemFont(ofSize: 14)
        subtitleLabel.textColor = windowsService?.colors.textSecondary
        
        let emailLabel = createLabel("Email Address")
        let passwordLabel = createLabel("Password")
        let confirmLabel = createLabel("Confirm Password")
        
        let passwordHint = UILabel()
        passwordHint.text = "At least 8 characters"
        passwordHint.font = .systemFont(ofSize: 12)
        passwordHint.textColor = windowsService?.colors.textSecondary
        
        // Terms Checkbox
        termsCheckbox.setImage(UIImage(systemName: "square"), for: .normal)
        termsCheckbox.setImage(UIImage(systemName: "checkmark.square.fill"), for: .selected)
        termsCheckbox.tintColor = windowsService?.colors.textSecondary
        termsCheckbox.addTarget(self, action: #selector(toggleTerms), for: .touchUpInside)
        
        let termsText = UILabel()
        termsText.text = "I agree to the Terms of Service and Privacy Policy"
        termsText.font = .systemFont(ofSize: 14)
        termsText.textColor = windowsService?.colors.textSecondary
        termsText.numberOfLines = 0
        
        let termsStack = UIStackView(arrangedSubviews: [termsCheckbox, termsText])
        termsStack.spacing = 8
        termsStack.alignment = .top
        
        createButton.setTitle("Create Account", for: .normal)
        createButton.addTarget(self, action: #selector(createTapped), for: .touchUpInside)
        
        let dividerStack = createDivider(text: "Or sign up with")
        
        googleButton.setTitle("    Sign up with Google", for: .normal)
        googleButton.addTarget(self, action: #selector(googleSignUpTapped), for: .touchUpInside)
        
        let haveAccountLabel = UILabel()
        haveAccountLabel.text = "Already have an account?"
        haveAccountLabel.font = .systemFont(ofSize: 14)
        haveAccountLabel.textColor = windowsService?.colors.textSecondary
        
        loginButton.setTitle("Login here", for: .normal)
        loginButton.setTitleColor(windowsService?.colors.linkColor, for: .normal)
        loginButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        loginButton.addTarget(self, action: #selector(loginTapped), for: .touchUpInside)
        
        let loginStack = UIStackView(arrangedSubviews: [haveAccountLabel, loginButton])
        loginStack.spacing = 4
        loginStack.alignment = .center
        
        termsLabel.text = "By continuing, you agree to our Terms of Service and Privacy Policy"
        termsLabel.font = .systemFont(ofSize: 12)
        termsLabel.textColor = windowsService?.colors.textSecondary
        termsLabel.textAlignment = .center
        termsLabel.numberOfLines = 0
        termsLabel.translatesAutoresizingMaskIntoConstraints = false
        termsLabel.alpha = 0

        [titleLabel, subtitleLabel, emailLabel, emailField, passwordLabel, passwordField,
         passwordHint, confirmLabel, confirmPasswordField, termsStack, createButton,
         dividerStack, googleButton, loginStack].forEach {
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

            titleLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),

            emailLabel.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 10),
            emailLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),

            emailField.topAnchor.constraint(equalTo: emailLabel.bottomAnchor, constant: 4),
            emailField.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),
            emailField.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -24),

            passwordLabel.topAnchor.constraint(equalTo: emailField.bottomAnchor, constant: 10),
            passwordLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),

            passwordField.topAnchor.constraint(equalTo: passwordLabel.bottomAnchor, constant: 4),
            passwordField.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),
            passwordField.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -24),

            passwordHint.topAnchor.constraint(equalTo: passwordField.bottomAnchor, constant: 2),
            passwordHint.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),

            confirmLabel.topAnchor.constraint(equalTo: passwordHint.bottomAnchor, constant: 8),
            confirmLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),

            confirmPasswordField.topAnchor.constraint(equalTo: confirmLabel.bottomAnchor, constant: 4),
            confirmPasswordField.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),
            confirmPasswordField.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -24),

            termsStack.topAnchor.constraint(equalTo: confirmPasswordField.bottomAnchor, constant: 10),
            termsStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),
            termsStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -24),

            createButton.topAnchor.constraint(equalTo: termsStack.bottomAnchor, constant: 10),
            createButton.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),
            createButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -24),
            createButton.heightAnchor.constraint(equalToConstant: 40),

            dividerStack.topAnchor.constraint(equalTo: createButton.bottomAnchor, constant: 10),
            dividerStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),
            dividerStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -24),

            googleButton.topAnchor.constraint(equalTo: dividerStack.bottomAnchor, constant: 10),
            googleButton.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),
            googleButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -24),
            googleButton.heightAnchor.constraint(equalToConstant: 40),

            loginStack.topAnchor.constraint(equalTo: googleButton.bottomAnchor, constant: 10),
            loginStack.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
            loginStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -16),

            termsLabel.topAnchor.constraint(equalTo: cardView.bottomAnchor, constant: 12),
            termsLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            termsLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40)
        ])
    }
    
    private func setupValidation() {
        emailField.onTextChanged = { [weak self] _ in self?.emailField.clearError() }
        passwordField.onTextChanged = { [weak self] _ in self?.passwordField.clearError() }
        confirmPasswordField.onTextChanged = { [weak self] _ in self?.confirmPasswordField.clearError() }
    }
    
    private func validateForm() -> Bool {
        var isValid = true
        
        if emailField.text.isEmpty {
            emailField.showError("Email is required")
            isValid = false
        } else if !Validator.isValidEmail(emailField.text) {
            emailField.showError("Please enter a valid email address")
            isValid = false
        }
        
        if passwordField.text.isEmpty {
            passwordField.showError("Password is required")
            isValid = false
        } else if !Validator.isValidPassword(passwordField.text) {
            passwordField.showError("Password must be at least 8 characters")
            isValid = false
        }
        
        if confirmPasswordField.text.isEmpty {
            confirmPasswordField.showError("Please confirm your password")
            isValid = false
        } else if !Validator.passwordsMatch(passwordField.text, confirmPasswordField.text) {
            confirmPasswordField.showError("Passwords do not match")
            isValid = false
        }
        
        if !termsAccepted {
            // Shake checkbox
            let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
            shake.values = [-8, 8, -6, 6, -4, 4, 0]
            shake.duration = 0.4
            termsCheckbox.layer.add(shake, forKey: "shake")
            termsCheckbox.tintColor = windowsService?.colors.errorRed
            isValid = false
        }
        
        return isValid
    }
    
    private func createLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = windowsService?.colors.textPrimary
        return label
    }
    
    private func createDivider(text: String) -> UIStackView {
        let leftLine = UIView()
        leftLine.backgroundColor = windowsService?.colors.cardBorder
        leftLine.heightAnchor.constraint(equalToConstant: 1).isActive = true
        
        let rightLine = UIView()
        rightLine.backgroundColor = windowsService?.colors.cardBorder
        rightLine.heightAnchor.constraint(equalToConstant: 1).isActive = true
        
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 14)
        label.textColor = windowsService?.colors.textSecondary
        
        let stack = UIStackView(arrangedSubviews: [leftLine, label, rightLine])
        stack.spacing = 16
        stack.alignment = .center
        leftLine.widthAnchor.constraint(equalTo: rightLine.widthAnchor).isActive = true
        
        return stack
    }
    
    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }
    
    @objc private func toggleTerms() {
        termsAccepted.toggle()
        termsCheckbox.isSelected = termsAccepted
        termsCheckbox.tintColor = termsAccepted ? windowsService?.colors.gradientFirst : windowsService?.colors.textSecondary
        
        UIView.animate(withDuration: 0.1, animations: {
            self.termsCheckbox.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
        }) { _ in
            UIView.animate(withDuration: 0.1) {
                self.termsCheckbox.transform = .identity
            }
        }
    }
    
    @objc private func createTapped() {
        dismissKeyboard()

        guard validateForm() else { return }

        guard let authService: AuthService = ServiceManager.shared.getService() else {
            return
        }

        createButton.startLoading()

        Task {
            do {
                let loggedIn = try await authService.signUp(email: emailField.text, password: passwordField.text)
                await MainActor.run {
                    createButton.stopLoading()
                    if loggedIn {
                        emailField.showSuccess()
                        passwordField.showSuccess()
                        confirmPasswordField.showSuccess()
                        createButton.showSuccess {}
                    } else {
                        emailField.showSuccess()
                        createButton.setTitle("Check your email to confirm", for: .normal)
                    }
                }
            } catch {
                await MainActor.run {
                    createButton.stopLoading()
                    emailField.showError(error.localizedDescription)
                }
            }
        }
    }

    @objc private func googleSignUpTapped() {
        guard let authService: AuthService = ServiceManager.shared.getService() else {
            return
        }

        Task {
            do {
                try await authService.signInWithGoogle()
            } catch {
                print("Google sign up failed: \(error.localizedDescription)")
            }
        }
    }
    
    @objc private func loginTapped() {
        dismiss(animated: true)
    }
}
