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
    private let backgroundView = AuthBackgroundView()
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let cardView = AnimatedCardView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let emailField = ValidatedTextField(placeholder: "you@example.com")
    private let passwordField = ValidatedTextField(placeholder: "••••••••", isSecure: true, showPasswordToggle: true)
    private let forgotPasswordButton = UIButton(type: .system)
    private let loginButton = SolidButton()
    private let googleButton = SocialButton(provider: .google, title: L("social.google"))
    private let appleButton = SocialButton(provider: .apple, title: L("social.apple"))
    private let createAccountButton = UIButton(type: .system)
    private let termsTextView = UITextView()

    // Locale pill (top-right).
    private let localePill = LocalePillButton()

    // Color-dependent labels kept as properties so they can refresh on a
    // live system-appearance change while the screen is visible.
    private let emailLabel = UILabel()
    private let passwordLabel = UILabel()
    private let noAccountLabel = UILabel()
    private var dividerLines: [UIView] = []
    private let dividerLabel = UILabel()

    private lazy var windowsService: WindowsService? = ServiceManager.shared.getService()
    private var activeTextField: UIView?

    private var effectiveStyle: UIUserInterfaceStyle {
        if traitCollection.userInterfaceStyle != .unspecified {
            return traitCollection.userInterfaceStyle
        }
        return windowsService?.window.traitCollection.userInterfaceStyle ?? .dark
    }
    private var colors: AppColors { AppColors.colors(for: effectiveStyle) }

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
        let colors = self.colors

        // Amber-glow backdrop
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(backgroundView)

        // Tap to dismiss keyboard
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)

        // Locale pill (top-right): flag + code + chevron, opens a dropdown.
        // Refresh localized text in place — never present a new VC (that
        // stacks modals and causes janky transitions).
        localePill.onSelect = { [weak self] code in
            LocalizationManager.shared.currentLanguage = code
            self?.applyLocalizedStrings()
            self?.localePill.refreshLanguage()
        }
        view.addSubview(localePill)

        // ScrollView for keyboard avoidance
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive
        view.addSubview(scrollView)
        // Keep the locale pill above the full-screen scroll view so it stays tappable.
        view.bringSubviewToFront(localePill)

        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)

        cardView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardView)

        // Title (H1 24/600)
        titleLabel.text = L("login.title")
        titleLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        titleLabel.textColor = colors.dsText

        // Subtitle (14 / muted)
        subtitleLabel.text = L("login.subtitle")
        subtitleLabel.font = .systemFont(ofSize: 14)
        subtitleLabel.textColor = colors.dsTextMuted
        subtitleLabel.numberOfLines = 0

        configureLabel(emailLabel, text: L("field.email"))
        configureLabel(passwordLabel, text: L("field.password"))

        forgotPasswordButton.setTitle(L("login.forgot_password"), for: .normal)
        forgotPasswordButton.setTitleColor(colors.dsAccent, for: .normal)
        forgotPasswordButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        forgotPasswordButton.contentHorizontalAlignment = .trailing
        forgotPasswordButton.addTarget(self, action: #selector(forgotPasswordTapped), for: .touchUpInside)

        loginButton.setTitle(L("login.button"), for: .normal)
        loginButton.addTarget(self, action: #selector(loginTapped), for: .touchUpInside)

        let dividerStack = createDivider(text: L("auth.divider"))

        // Social buttons call the SAME existing auth flow
        googleButton.addTarget(self, action: #selector(googleSignInTapped), for: .touchUpInside)
        appleButton.addTarget(self, action: #selector(appleSignInTapped), for: .touchUpInside)

        noAccountLabel.text = L("login.no_account")
        noAccountLabel.font = .systemFont(ofSize: 14)
        noAccountLabel.textColor = colors.dsTextMuted

        createAccountButton.setTitle(L("login.create_one"), for: .normal)
        createAccountButton.setTitleColor(colors.dsAccent, for: .normal)
        createAccountButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
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
            // Background fills the screen
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Locale pill (top-right)
            localePill.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            localePill.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            // ScrollView fills the view
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // ContentView fills scrollView, matches width
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            contentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.heightAnchor),

            // Card: ~54px below the status bar; single column.
            cardView.topAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.topAnchor, constant: 80),
            cardView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            cardView.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 24),
            cardView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -24),
            cardWidth,
            cardView.widthAnchor.constraint(lessThanOrEqualToConstant: 420),

            titleLabel.topAnchor.constraint(equalTo: cardView.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: cardView.trailingAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            subtitleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),

            emailLabel.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 28),
            emailLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),

            emailField.topAnchor.constraint(equalTo: emailLabel.bottomAnchor, constant: 6),
            emailField.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            emailField.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),

            passwordLabel.topAnchor.constraint(equalTo: emailField.bottomAnchor, constant: 16),
            passwordLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),

            passwordField.topAnchor.constraint(equalTo: passwordLabel.bottomAnchor, constant: 6),
            passwordField.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            passwordField.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),

            forgotPasswordButton.topAnchor.constraint(equalTo: passwordField.bottomAnchor, constant: 12),
            forgotPasswordButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),

            loginButton.topAnchor.constraint(equalTo: forgotPasswordButton.bottomAnchor, constant: 16),
            loginButton.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            loginButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            loginButton.heightAnchor.constraint(equalToConstant: 48),

            dividerStack.topAnchor.constraint(equalTo: loginButton.bottomAnchor, constant: 24),
            dividerStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            dividerStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),

            googleButton.topAnchor.constraint(equalTo: dividerStack.bottomAnchor, constant: 24),
            googleButton.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            googleButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            googleButton.heightAnchor.constraint(equalToConstant: 48),

            appleButton.topAnchor.constraint(equalTo: googleButton.bottomAnchor, constant: 12),
            appleButton.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            appleButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            appleButton.heightAnchor.constraint(equalToConstant: 48),

            createStack.topAnchor.constraint(equalTo: appleButton.bottomAnchor, constant: 24),
            createStack.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
            createStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),

            termsTextView.topAnchor.constraint(equalTo: cardView.bottomAnchor, constant: 24),
            termsTextView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 40),
            termsTextView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -40),
            termsTextView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -16)
        ])
    }

    /// Re-reads every localized string in place after a language change so the
    /// screen updates without presenting a fresh view controller.
    private func applyLocalizedStrings() {
        titleLabel.text = L("login.title")
        subtitleLabel.text = L("login.subtitle")
        emailLabel.text = L("field.email")
        passwordLabel.text = L("field.password")
        forgotPasswordButton.setTitle(L("login.forgot_password"), for: .normal)
        loginButton.setTitle(L("login.button"), for: .normal)
        dividerLabel.text = L("auth.divider")
        googleButton.updateTitle(L("social.google"))
        appleButton.updateTitle(L("social.apple"))
        noAccountLabel.text = L("login.no_account")
        createAccountButton.setTitle(L("login.create_one"), for: .normal)
        setupTermsTextView()
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

    private func configureLabel(_ label: UILabel, text: String) {
        label.text = text
        // Field label: 12 / weight 500 / text-muted
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = colors.dsTextMuted
    }

    /// Centered mono-caps label between two 1px border rules.
    private func createDivider(text: String) -> UIStackView {
        let leftLine = UIView()
        leftLine.backgroundColor = colors.dsBorder
        leftLine.heightAnchor.constraint(equalToConstant: 1).isActive = true

        let rightLine = UIView()
        rightLine.backgroundColor = colors.dsBorder
        rightLine.heightAnchor.constraint(equalToConstant: 1).isActive = true
        dividerLines = [leftLine, rightLine]

        dividerLabel.text = text
        dividerLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        dividerLabel.textColor = colors.dsTextSubtle
        dividerLabel.setContentHuggingPriority(.required, for: .horizontal)
        dividerLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [leftLine, dividerLabel, rightLine])
        stack.spacing = 12
        stack.alignment = .center
        leftLine.widthAnchor.constraint(equalTo: rightLine.widthAnchor).isActive = true

        return stack
    }

    /// Re-applies all directly-set text/line colors. Called on a live
    /// system-appearance change so the labels track the new theme.
    private func applyThemeColors() {
        let colors = self.colors
        titleLabel.textColor = colors.dsText
        subtitleLabel.textColor = colors.dsTextMuted
        emailLabel.textColor = colors.dsTextMuted
        passwordLabel.textColor = colors.dsTextMuted
        noAccountLabel.textColor = colors.dsTextMuted
        dividerLabel.textColor = colors.dsTextSubtle
        dividerLines.forEach { $0.backgroundColor = colors.dsBorder }
        forgotPasswordButton.setTitleColor(colors.dsAccent, for: .normal)
        createAccountButton.setTitleColor(colors.dsAccent, for: .normal)
        localePill.applyColors()
        setupTermsTextView()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            applyThemeColors()
        }
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    private func setupTermsTextView() {
        termsTextView.isEditable = false
        termsTextView.isScrollEnabled = false
        termsTextView.backgroundColor = .clear
        termsTextView.textContainerInset = .zero
        termsTextView.textContainer.lineFragmentPadding = 0
        termsTextView.linkTextAttributes = [
            .foregroundColor: colors.dsAccent
        ]

        let text = L("terms.label")
        let termsWord = L("terms.word")
        let privacyWord = L("terms.privacy_word")

        let attributed = NSMutableAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: colors.dsTextSubtle
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
        vc.modalTransitionStyle = .crossDissolve
        present(vc, animated: true)
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
        vc.modalTransitionStyle = .crossDissolve
        present(vc, animated: true)
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
