//
//  LoginViewController.swift
//  capital-wizard-ios
//
//  Created by Roman on 07.02.2026.
//

import UIKit
import AuthenticationServices
import SafariServices

class LoginViewController: UIViewController {
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let cardView = AnimatedCardView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let emailField = ValidatedTextField(placeholder: "you@example.com")
    private let passwordField = ValidatedTextField(placeholder: "••••••••", isSecure: true, showPasswordToggle: true)
    private let forgotPasswordButton = UIButton(type: .system)
    private let loginButton = GradientButton()
    private let googleButton = UIButton(type: .system)
    private lazy var appleButton = ASAuthorizationAppleIDButton(type: .signIn, style: traitCollection.userInterfaceStyle == .dark ? .white : .black)
    private let createAccountButton = UIButton(type: .system)
    private let termsTextView = UITextView()
    private let languageButton = UIButton(type: .system)

    private lazy var windowsService: WindowsService? = ServiceManager.shared.getService()
    private var activeTextField: UIView?

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .portrait
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupValidation()
        setupKeyboardObservers()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        cardView.animateIn()
        UIView.animate(withDuration: 0.25) { self.termsTextView.alpha = 1 }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupUI() {
        view.backgroundColor = windowsService?.colors.backgroundColor

        // Tap to dismiss keyboard (cancelsTouchesInView = false so ASAuthorizationAppleIDButton still works)
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)

        // Language button (top right) — flag-based
        let manager = LocalizationManager.shared
        languageButton.setTitle(manager.currentFlag, for: .normal)
        languageButton.titleLabel?.font = .systemFont(ofSize: 24)
        languageButton.translatesAutoresizingMaskIntoConstraints = false
        languageButton.addTarget(self, action: #selector(languageTapped), for: .touchUpInside)
        view.addSubview(languageButton)

        // ScrollView for keyboard avoidance
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive
        view.addSubview(scrollView)

        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)

        cardView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardView)

        // Title
        titleLabel.text = L("login.title")
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.textColor = windowsService?.colors.textPrimary

        // Subtitle
        subtitleLabel.text = L("login.subtitle")
        subtitleLabel.font = .systemFont(ofSize: 14)
        subtitleLabel.textColor = windowsService?.colors.textSecondary

        let emailLabel = createLabel(L("field.email"))
        let passwordLabel = createLabel(L("field.password"))

        forgotPasswordButton.setTitle(L("login.forgot_password"), for: .normal)
        forgotPasswordButton.setTitleColor(windowsService?.colors.linkColor, for: .normal)
        forgotPasswordButton.titleLabel?.font = .systemFont(ofSize: 14)
        forgotPasswordButton.contentHorizontalAlignment = .trailing
        forgotPasswordButton.addTarget(self, action: #selector(forgotPasswordTapped), for: .touchUpInside)

        loginButton.setTitle(L("login.button"), for: .normal)
        loginButton.addTarget(self, action: #selector(loginTapped), for: .touchUpInside)

        let dividerStack = createDivider(text: L("login.divider"))

        // Google button — bordered style matching Apple button
        setupGoogleButton(title: L("login.google"))

        // Apple button
        appleButton.cornerRadius = 8
        appleButton.addTarget(self, action: #selector(appleSignInTapped), for: .touchUpInside)

        let noAccountLabel = UILabel()
        noAccountLabel.text = L("login.no_account")
        noAccountLabel.font = .systemFont(ofSize: 14)
        noAccountLabel.textColor = windowsService?.colors.textSecondary

        createAccountButton.setTitle(L("login.create_one"), for: .normal)
        createAccountButton.setTitleColor(windowsService?.colors.linkColor, for: .normal)
        createAccountButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        createAccountButton.addTarget(self, action: #selector(createAccountTapped), for: .touchUpInside)

        let createStack = UIStackView(arrangedSubviews: [noAccountLabel, createAccountButton])
        createStack.spacing = 4
        createStack.alignment = .center

        setupTermsTextView()
        termsTextView.translatesAutoresizingMaskIntoConstraints = false
        termsTextView.alpha = 0

        [titleLabel, subtitleLabel, emailLabel, emailField, passwordLabel, passwordField,
         forgotPasswordButton, loginButton, dividerStack, googleButton, appleButton, createStack].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            cardView.addSubview($0)
        }
        contentView.addSubview(termsTextView)

        let cardWidth = cardView.widthAnchor.constraint(equalTo: contentView.widthAnchor, constant: -48)
        cardWidth.priority = .defaultHigh

        NSLayoutConstraint.activate([
            // Language button
            languageButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            languageButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            languageButton.widthAnchor.constraint(equalToConstant: 44),
            languageButton.heightAnchor.constraint(equalToConstant: 44),

            // ScrollView fills the view
            scrollView.topAnchor.constraint(equalTo: languageButton.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // ContentView fills scrollView, matches width
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            // Minimum height so card is centered when keyboard is hidden
            contentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.heightAnchor),

            cardView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            cardView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: -70),
            cardView.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 24),
            cardView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -24),
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

            forgotPasswordButton.topAnchor.constraint(equalTo: passwordField.bottomAnchor, constant: 14),
            forgotPasswordButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -24),

            loginButton.topAnchor.constraint(equalTo: forgotPasswordButton.bottomAnchor, constant: 16),
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

            appleButton.topAnchor.constraint(equalTo: googleButton.bottomAnchor, constant: 10),
            appleButton.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),
            appleButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -24),
            appleButton.heightAnchor.constraint(equalToConstant: 44),

            createStack.topAnchor.constraint(equalTo: appleButton.bottomAnchor, constant: 16),
            createStack.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
            createStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -24),

            termsTextView.topAnchor.constraint(equalTo: cardView.bottomAnchor, constant: 16),
            termsTextView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 40),
            termsTextView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -40)
        ])
    }

    private func setupGoogleButton(title: String) {
        googleButton.setTitle(title, for: .normal)
        googleButton.setTitleColor(windowsService?.colors.textPrimary, for: .normal)
        googleButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        googleButton.backgroundColor = .clear
        googleButton.layer.cornerRadius = 8
        googleButton.layer.borderWidth = 1
        googleButton.layer.borderColor = windowsService?.colors.cardBorder.cgColor

        // Google "G" icon
        let gIcon = createGoogleIcon(size: 20)
        googleButton.setImage(gIcon, for: .normal)
        googleButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 8)
        googleButton.titleEdgeInsets = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 0)

        googleButton.addTarget(self, action: #selector(googleSignInTapped), for: .touchUpInside)
        googleButton.addTarget(self, action: #selector(buttonTouchDown(_:)), for: .touchDown)
        googleButton.addTarget(self, action: #selector(buttonTouchUp(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])
    }

    private func createGoogleIcon(size: CGFloat) -> UIImage {
        return GoogleIconRenderer.render(size: size)
    }

    @objc private func buttonTouchDown(_ sender: UIButton) {
        UIView.animate(withDuration: 0.1) {
            sender.transform = CGAffineTransform(scaleX: 0.97, y: 0.97)
            sender.alpha = 0.7
        }
    }

    @objc private func buttonTouchUp(_ sender: UIButton) {
        UIView.animate(withDuration: 0.1) {
            sender.transform = .identity
            sender.alpha = 1.0
        }
    }

    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(_:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)

        emailField.textField.delegate = self
        passwordField.textField.delegate = self
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
            emailField.showError(L("error.email_required"))
            isValid = false
        } else if !Validator.isValidEmail(emailField.text) {
            emailField.showError(L("error.email_invalid"))
            isValid = false
        }

        if passwordField.text.isEmpty {
            passwordField.showError(L("error.password_required"))
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

    @objc private func languageTapped() {
        let manager = LocalizationManager.shared
        let other = manager.otherLanguage
        manager.currentLanguage = other.code
        windowsService?.showLogin()
    }

    private func setupTermsTextView() {
        termsTextView.isEditable = false
        termsTextView.isScrollEnabled = false
        termsTextView.backgroundColor = .clear
        termsTextView.textContainerInset = .zero
        termsTextView.textContainer.lineFragmentPadding = 0
        termsTextView.linkTextAttributes = [
            .foregroundColor: windowsService?.colors.linkColor ?? .systemPurple
        ]

        let text = L("terms.label")
        let termsWord = L("terms.word")
        let privacyWord = L("terms.privacy_word")

        let attributed = NSMutableAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: windowsService?.colors.textSecondary ?? .gray
        ])

        if let termsRange = text.range(of: termsWord) {
            let nsRange = NSRange(termsRange, in: text)
            attributed.addAttribute(.link, value: "https://capital-wizard.com/terms", range: nsRange)
        }
        if let privacyRange = text.range(of: privacyWord) {
            let nsRange = NSRange(privacyRange, in: text)
            attributed.addAttribute(.link, value: "https://capital-wizard.com/privacy", range: nsRange)
        }

        let style = NSMutableParagraphStyle()
        style.alignment = .center
        attributed.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: attributed.length))

        termsTextView.attributedText = attributed
        termsTextView.delegate = self
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

    @objc private func appleSignInTapped() {
        guard let authService: AuthService = ServiceManager.shared.getService() else {
            return
        }

        Task {
            do {
                try await authService.signInWithApple()
            } catch {
                print("Apple sign in failed: \(error.localizedDescription)")
            }
        }
    }

    @objc private func createAccountTapped() {
        let vc = SignUpViewController()
        vc.modalPresentationStyle = .fullScreen
        present(vc, animated: false)
    }

    // MARK: - Keyboard Handling

    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval else { return }

        let keyboardHeight = keyboardFrame.height
        scrollView.contentInset.bottom = keyboardHeight
        scrollView.verticalScrollIndicatorInsets.bottom = keyboardHeight

        if let activeField = activeTextField {
            let fieldFrame = activeField.convert(activeField.bounds, to: scrollView)
            scrollView.scrollRectToVisible(fieldFrame.insetBy(dx: 0, dy: -20), animated: true)
        }
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0.25

        UIView.animate(withDuration: duration) {
            self.scrollView.contentInset.bottom = 0
            self.scrollView.verticalScrollIndicatorInsets.bottom = 0
        }
    }
}

// MARK: - UITextFieldDelegate

extension LoginViewController: UITextFieldDelegate {
    func textFieldDidBeginEditing(_ textField: UITextField) {
        activeTextField = textField.superview?.superview // ValidatedTextField → containerView → ValidatedTextField
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        activeTextField = nil
    }
}

// MARK: - UITextViewDelegate

extension LoginViewController: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        let safari = SFSafariViewController(url: URL)
        present(safari, animated: true)
        return false
    }
}
