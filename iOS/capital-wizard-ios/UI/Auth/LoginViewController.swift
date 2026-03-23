//
//  LoginViewController.swift
//  capital-wizard-ios
//
//  Created by Roman on 07.02.2026.
//

import UIKit

class LoginViewController: UIViewController {
    private let cardView = AnimatedCardView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let emailField = ValidatedTextField(placeholder: "you@example.com")
    private let passwordField = ValidatedTextField(placeholder: "••••••••", isSecure: true, showPasswordToggle: true)
    private let rememberMeCheckbox = UIButton(type: .custom)
    private let forgotPasswordButton = UIButton(type: .system)
    private let loginButton = GradientButton()
    private let googleButton = GoogleButton()
    private let createAccountButton = UIButton(type: .system)
    private let termsLabel = UILabel()
    
    private lazy var windowsService: WindowsService? = ServiceManager.shared.getService()

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .pad ? .all : .portrait
    }

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
        
        // Tap to dismiss keyboard
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        view.addGestureRecognizer(tap)
        
        cardView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cardView)
        
        // Title
        titleLabel.text = "Welcome Back"
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.textColor = windowsService?.colors.textPrimary
        
        // Subtitle
        subtitleLabel.text = "Enter your credentials to access your account"
        subtitleLabel.font = .systemFont(ofSize: 14)
        subtitleLabel.textColor = windowsService?.colors.textSecondary
        
        let emailLabel = createLabel("Email Address")
        let passwordLabel = createLabel("Password")
        
        // Remember Me
        rememberMeCheckbox.setImage(UIImage(systemName: "square"), for: .normal)
        rememberMeCheckbox.setImage(UIImage(systemName: "checkmark.square.fill"), for: .selected)
        rememberMeCheckbox.tintColor = windowsService?.colors.textSecondary
        rememberMeCheckbox.addTarget(self, action: #selector(toggleRememberMe), for: .touchUpInside)
        
        let rememberLabel = UILabel()
        rememberLabel.text = "Remember me"
        rememberLabel.font = .systemFont(ofSize: 14)
        rememberLabel.textColor = windowsService?.colors.textSecondary
        
        let rememberStack = UIStackView(arrangedSubviews: [rememberMeCheckbox, rememberLabel])
        rememberStack.spacing = 8
        rememberStack.alignment = .center
        
        forgotPasswordButton.setTitle("Forgot password?", for: .normal)
        forgotPasswordButton.setTitleColor(windowsService?.colors.linkColor, for: .normal)
        forgotPasswordButton.titleLabel?.font = .systemFont(ofSize: 14)
        forgotPasswordButton.addTarget(self, action: #selector(forgotPasswordTapped), for: .touchUpInside)
        
        let rememberForgotStack = UIStackView(arrangedSubviews: [rememberStack, forgotPasswordButton])
        rememberForgotStack.distribution = .equalSpacing
        
        loginButton.setTitle("Login", for: .normal)
        loginButton.addTarget(self, action: #selector(loginTapped), for: .touchUpInside)
        
        let dividerStack = createDivider(text: "Or continue with")
        
        googleButton.setTitle("    Sign in with Google", for: .normal)
        googleButton.addTarget(self, action: #selector(googleSignInTapped), for: .touchUpInside)
        
        let noAccountLabel = UILabel()
        noAccountLabel.text = "Don't have an account?"
        noAccountLabel.font = .systemFont(ofSize: 14)
        noAccountLabel.textColor = windowsService?.colors.textSecondary
        
        createAccountButton.setTitle("Create one", for: .normal)
        createAccountButton.setTitleColor(windowsService?.colors.linkColor, for: .normal)
        createAccountButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        createAccountButton.addTarget(self, action: #selector(createAccountTapped), for: .touchUpInside)
        
        let createStack = UIStackView(arrangedSubviews: [noAccountLabel, createAccountButton])
        createStack.spacing = 4
        createStack.alignment = .center
        
        termsLabel.text = "By continuing, you agree to our Terms of Service and Privacy Policy"
        termsLabel.font = .systemFont(ofSize: 12)
        termsLabel.textColor = windowsService?.colors.textSecondary
        termsLabel.textAlignment = .center
        termsLabel.numberOfLines = 0
        termsLabel.translatesAutoresizingMaskIntoConstraints = false
        termsLabel.alpha = 0

        [titleLabel, subtitleLabel, emailLabel, emailField, passwordLabel, passwordField,
         rememberForgotStack, loginButton, dividerStack, googleButton, createStack].forEach {
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

            titleLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),

            emailLabel.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 16),
            emailLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),

            emailField.topAnchor.constraint(equalTo: emailLabel.bottomAnchor, constant: 6),
            emailField.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),
            emailField.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -24),

            passwordLabel.topAnchor.constraint(equalTo: emailField.bottomAnchor, constant: 12),
            passwordLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),

            passwordField.topAnchor.constraint(equalTo: passwordLabel.bottomAnchor, constant: 6),
            passwordField.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),
            passwordField.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -24),

            rememberForgotStack.topAnchor.constraint(equalTo: passwordField.bottomAnchor, constant: 14),
            rememberForgotStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),
            rememberForgotStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -24),

            loginButton.topAnchor.constraint(equalTo: rememberForgotStack.bottomAnchor, constant: 16),
            loginButton.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),
            loginButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -24),
            loginButton.heightAnchor.constraint(equalToConstant: 44),

            dividerStack.topAnchor.constraint(equalTo: loginButton.bottomAnchor, constant: 16),
            dividerStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),
            dividerStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -24),

            googleButton.topAnchor.constraint(equalTo: dividerStack.bottomAnchor, constant: 16),
            googleButton.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),
            googleButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -24),
            googleButton.heightAnchor.constraint(equalToConstant: 44),

            createStack.topAnchor.constraint(equalTo: googleButton.bottomAnchor, constant: 16),
            createStack.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
            createStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -24),

            termsLabel.topAnchor.constraint(equalTo: cardView.bottomAnchor, constant: 16),
            termsLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            termsLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40)
        ])
    }
    
    private func setupValidation() {
        emailField.onTextChanged = { [weak self] _ in
            self?.emailField.clearError()
        }
        passwordField.onTextChanged = { [weak self] _ in
            self?.passwordField.clearError()
        }
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
    
    @objc private func toggleRememberMe() {
        rememberMeCheckbox.isSelected.toggle()
        
        // Checkbox animation
        UIView.animate(withDuration: 0.1, animations: {
            self.rememberMeCheckbox.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
        }) { _ in
            UIView.animate(withDuration: 0.1) {
                self.rememberMeCheckbox.transform = .identity
            }
        }
    }
    
    @objc private func forgotPasswordTapped() {
        let vc = ResetPasswordViewController()
        vc.modalPresentationStyle = .fullScreen
        present(vc, animated: false)
    }
    
    @objc private func loginTapped() {
        dismissKeyboard()

        guard validateForm() else { return }

        guard let authService: AuthService = ServiceManager.shared.getService() else {
            return
        }

        loginButton.startLoading()

        Task {
            do {
                try await authService.signIn(email: emailField.text, password: passwordField.text)
                await MainActor.run {
                    loginButton.stopLoading()
                    emailField.showSuccess()
                    passwordField.showSuccess()
                    loginButton.showSuccess {}
                }
            } catch {
                await MainActor.run {
                    loginButton.stopLoading()
                    passwordField.showError(error.localizedDescription)
                }
            }
        }
    }

    @objc private func googleSignInTapped() {
        guard let authService: AuthService = ServiceManager.shared.getService() else {
            return
        }

        Task {
            do {
                try await authService.signInWithGoogle()
            } catch {
                print("Google sign in failed: \(error.localizedDescription)")
            }
        }
    }
    
    @objc private func createAccountTapped() {
        let vc = SignUpViewController()
        vc.modalPresentationStyle = .fullScreen
        present(vc, animated: false)
    }
}
