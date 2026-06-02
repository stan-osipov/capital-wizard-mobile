//
//  SignUpViewController.swift
//  capital-wizard-ios
//
//  Created by Roman on 07.02.2026.
//

import UIKit
import AuthenticationServices
import SafariServices

class SignUpViewController: UIViewController {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .portrait
    }

    private lazy var windowsService: WindowsService? = ServiceManager.shared.getService()

    private var effectiveStyle: UIUserInterfaceStyle {
        if traitCollection.userInterfaceStyle != .unspecified {
            return traitCollection.userInterfaceStyle
        }
        return windowsService?.window.traitCollection.userInterfaceStyle ?? .dark
    }
    private var colors: AppColors { AppColors.colors(for: effectiveStyle) }

    private let backgroundView = AuthBackgroundView()
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let cardView = AnimatedCardView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let emailField = ValidatedTextField(placeholder: "you@example.com")
    private let passwordField = ValidatedTextField(placeholder: "••••••••", isSecure: true, showPasswordToggle: true)
    private let confirmPasswordField = ValidatedTextField(placeholder: "••••••••", isSecure: true, showPasswordToggle: true)
    private let termsCheckbox = TermsCheckbox()
    private let createButton = SolidButton()
    private let googleButton = SocialButton(provider: .google, title: L("social.google"))
    private let appleButton = SocialButton(provider: .apple, title: L("social.apple"))
    private let loginButton = UIButton(type: .system)
    private let termsTextView = UITextView()
    private let confirmationView = UIView()

    // Locale pill (top-right).
    private let localePill = LocalePillButton()

    // Color-dependent labels kept as properties so they refresh on a live
    // system-appearance change while the screen is visible.
    private let emailLabel = UILabel()
    private let passwordLabel = UILabel()
    private let confirmLabel = UILabel()
    private let passwordHint = UILabel()
    private let termsText = UILabel()
    private let haveAccountLabel = UILabel()
    private let dividerLabel = UILabel()
    private var dividerLines: [UIView] = []

    private var termsAccepted = false
    private var activeTextField: UIView?
    private var formBottomConstraint: NSLayoutConstraint?
    private var confirmBottomConstraint: NSLayoutConstraint?

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

        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(backgroundView)

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)

        // Locale pill (top-right): flag + code + chevron, opens a dropdown.
        // Refresh localized text in place — never present a new VC (that
        // stacks modals and causes janky transitions).
        localePill.onSelect = { [weak self] code in
            guard let self = self else { return }
            LocalizationManager.shared.currentLanguage = code
            self.applyLocalizedStrings()
            self.localePill.refreshLanguage()
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

        titleLabel.text = L("signup.title")
        titleLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        titleLabel.textColor = colors.dsText
        titleLabel.numberOfLines = 0

        subtitleLabel.text = L("signup.subtitle")
        subtitleLabel.font = .systemFont(ofSize: 14)
        subtitleLabel.textColor = colors.dsTextMuted
        subtitleLabel.numberOfLines = 0

        configureLabel(emailLabel, text: L("field.email"))
        configureLabel(passwordLabel, text: L("field.password"))
        configureLabel(confirmLabel, text: L("field.confirm_password"))

        passwordHint.text = L("signup.password_hint")
        passwordHint.font = .systemFont(ofSize: 12)
        passwordHint.textColor = colors.dsTextSubtle

        // Terms checkbox (design system) — gates the primary button.
        termsCheckbox.addTarget(self, action: #selector(toggleTerms), for: .valueChanged)
        termsCheckbox.setContentHuggingPriority(.required, for: .horizontal)
        termsCheckbox.setContentCompressionResistancePriority(.required, for: .horizontal)

        termsText.text = L("signup.terms_agree")
        termsText.font = .systemFont(ofSize: 13)
        termsText.textColor = colors.dsTextMuted
        termsText.numberOfLines = 0

        let termsStack = UIStackView(arrangedSubviews: [termsCheckbox, termsText])
        termsStack.spacing = 6
        termsStack.alignment = .center

        createButton.setTitle(L("signup.button"), for: .normal)
        createButton.addTarget(self, action: #selector(createTapped), for: .touchUpInside)
        createButton.isFormEnabled = false // disabled (0.4) until Terms accepted

        let dividerStack = createDivider(text: L("auth.divider"))

        // Social buttons call the SAME existing auth flow
        googleButton.addTarget(self, action: #selector(googleSignUpTapped), for: .touchUpInside)
        appleButton.addTarget(self, action: #selector(appleSignUpTapped), for: .touchUpInside)

        haveAccountLabel.text = L("signup.have_account")
        haveAccountLabel.font = .systemFont(ofSize: 14)
        haveAccountLabel.textColor = colors.dsTextMuted

        loginButton.setTitle(L("signup.login_here"), for: .normal)
        loginButton.setTitleColor(colors.dsAccent, for: .normal)
        loginButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        loginButton.addTarget(self, action: #selector(loginTapped), for: .touchUpInside)

        let loginStack = UIStackView(arrangedSubviews: [haveAccountLabel, loginButton])
        loginStack.spacing = 4
        loginStack.alignment = .center

        setupTermsTextView()
        termsTextView.translatesAutoresizingMaskIntoConstraints = false
        termsTextView.alpha = 0

        // Confirmation view (hidden initially)
        setupConfirmationView()

        [titleLabel, subtitleLabel, emailLabel, emailField, passwordLabel, passwordField,
         passwordHint, confirmLabel, confirmPasswordField, termsStack, createButton,
         dividerStack, googleButton, appleButton, loginStack, confirmationView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            cardView.addSubview($0)
        }
        contentView.addSubview(termsTextView)

        let cardWidth = cardView.widthAnchor.constraint(equalTo: contentView.widthAnchor, constant: -48)
        cardWidth.priority = .defaultHigh

        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Locale pill (top-right)
            localePill.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            localePill.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            // ScrollView
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            contentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.heightAnchor),

            cardView.topAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.topAnchor, constant: 80),
            cardView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            cardView.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 24),
            cardView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -24),
            cardWidth,
            cardView.widthAnchor.constraint(lessThanOrEqualToConstant: 420),

            titleLabel.topAnchor.constraint(equalTo: cardView.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            subtitleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),

            emailLabel.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 22),
            emailLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),

            emailField.topAnchor.constraint(equalTo: emailLabel.bottomAnchor, constant: 6),
            emailField.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            emailField.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),

            passwordLabel.topAnchor.constraint(equalTo: emailField.bottomAnchor, constant: 14),
            passwordLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),

            passwordField.topAnchor.constraint(equalTo: passwordLabel.bottomAnchor, constant: 6),
            passwordField.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            passwordField.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),

            passwordHint.topAnchor.constraint(equalTo: passwordField.bottomAnchor, constant: 6),
            passwordHint.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),

            confirmLabel.topAnchor.constraint(equalTo: passwordHint.bottomAnchor, constant: 12),
            confirmLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),

            confirmPasswordField.topAnchor.constraint(equalTo: confirmLabel.bottomAnchor, constant: 6),
            confirmPasswordField.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            confirmPasswordField.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),

            termsStack.topAnchor.constraint(equalTo: confirmPasswordField.bottomAnchor, constant: 14),
            termsStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            termsStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),

            createButton.topAnchor.constraint(equalTo: termsStack.bottomAnchor, constant: 16),
            createButton.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            createButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            createButton.heightAnchor.constraint(equalToConstant: 48),

            dividerStack.topAnchor.constraint(equalTo: createButton.bottomAnchor, constant: 24),
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

            loginStack.topAnchor.constraint(equalTo: appleButton.bottomAnchor, constant: 24),
            loginStack.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),

            // Confirmation view centered in card
            confirmationView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 24),
            confirmationView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            confirmationView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),

            termsTextView.topAnchor.constraint(equalTo: cardView.bottomAnchor, constant: 20),
            termsTextView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 40),
            termsTextView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -40),
            termsTextView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -16)
        ])

        // Store switchable bottom constraints
        formBottomConstraint = loginStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor)
        confirmBottomConstraint = confirmationView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor)
        formBottomConstraint?.isActive = true
    }

    /// Re-reads every localized string in place after a language change so the
    /// screen updates without presenting a fresh view controller.
    private func applyLocalizedStrings() {
        titleLabel.text = L("signup.title")
        subtitleLabel.text = L("signup.subtitle")
        emailLabel.text = L("field.email")
        passwordLabel.text = L("field.password")
        confirmLabel.text = L("field.confirm_password")
        passwordHint.text = L("signup.password_hint")
        termsText.text = L("signup.terms_agree")
        createButton.setTitle(L("signup.button"), for: .normal)
        dividerLabel.text = L("auth.divider")
        googleButton.updateTitle(L("social.google"))
        appleButton.updateTitle(L("social.apple"))
        haveAccountLabel.text = L("signup.have_account")
        loginButton.setTitle(L("signup.login_here"), for: .normal)
        setupTermsTextView()
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

    private func setupConfirmationView() {
        confirmationView.alpha = 0
        confirmationView.isHidden = true

        let iconContainer = UIView()
        iconContainer.backgroundColor = colors.dsAccentSoft
        iconContainer.layer.cornerRadius = 30
        iconContainer.translatesAutoresizingMaskIntoConstraints = false

        let emailIcon = UIImageView(image: UIImage(systemName: "envelope.circle.fill"))
        emailIcon.tintColor = colors.dsAccent
        emailIcon.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.addSubview(emailIcon)

        let titleLabel = UILabel()
        titleLabel.text = L("signup.confirm_title")
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = colors.dsText
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let descLabel = UILabel()
        descLabel.text = L("signup.confirm_description")
        descLabel.font = .systemFont(ofSize: 14)
        descLabel.textColor = colors.dsTextMuted
        descLabel.textAlignment = .center
        descLabel.numberOfLines = 0
        descLabel.translatesAutoresizingMaskIntoConstraints = false

        let backToLoginButton = UIButton(type: .system)
        backToLoginButton.setTitle(L("signup.back_to_login"), for: .normal)
        backToLoginButton.setTitleColor(colors.dsAccent, for: .normal)
        backToLoginButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        backToLoginButton.addTarget(self, action: #selector(loginTapped), for: .touchUpInside)
        backToLoginButton.translatesAutoresizingMaskIntoConstraints = false

        confirmationView.addSubview(iconContainer)
        confirmationView.addSubview(titleLabel)
        confirmationView.addSubview(descLabel)
        confirmationView.addSubview(backToLoginButton)

        NSLayoutConstraint.activate([
            iconContainer.topAnchor.constraint(equalTo: confirmationView.topAnchor),
            iconContainer.centerXAnchor.constraint(equalTo: confirmationView.centerXAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: 60),
            iconContainer.heightAnchor.constraint(equalToConstant: 60),

            emailIcon.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            emailIcon.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            emailIcon.widthAnchor.constraint(equalToConstant: 32),
            emailIcon.heightAnchor.constraint(equalToConstant: 32),

            titleLabel.topAnchor.constraint(equalTo: iconContainer.bottomAnchor, constant: 16),
            titleLabel.centerXAnchor.constraint(equalTo: confirmationView.centerXAnchor),

            descLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            descLabel.leadingAnchor.constraint(equalTo: confirmationView.leadingAnchor),
            descLabel.trailingAnchor.constraint(equalTo: confirmationView.trailingAnchor),

            backToLoginButton.topAnchor.constraint(equalTo: descLabel.bottomAnchor, constant: 16),
            backToLoginButton.centerXAnchor.constraint(equalTo: confirmationView.centerXAnchor),
            backToLoginButton.bottomAnchor.constraint(equalTo: confirmationView.bottomAnchor)
        ])
    }

    private func showConfirmationState() {
        confirmationView.isHidden = false
        confirmationView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)

        // Swap bottom constraints so card shrinks to fit confirmation
        formBottomConstraint?.isActive = false
        confirmBottomConstraint?.isActive = true

        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5) {
            self.confirmationView.alpha = 1
            self.confirmationView.transform = .identity
            // Hide form elements
            for subview in self.cardView.subviews where subview !== self.titleLabel && subview !== self.subtitleLabel && subview !== self.confirmationView {
                subview.alpha = 0
            }
            self.view.layoutIfNeeded()
        }
    }

    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(_:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)

        emailField.textField.delegate = self
        passwordField.textField.delegate = self
        confirmPasswordField.textField.delegate = self
    }

    private func setupValidation() {
        emailField.onTextChanged = { [weak self] _ in self?.emailField.clearError() }
        passwordField.onTextChanged = { [weak self] _ in self?.passwordField.clearError() }
        confirmPasswordField.onTextChanged = { [weak self] _ in self?.confirmPasswordField.clearError() }
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

        if confirmPasswordField.text.isEmpty {
            confirmPasswordField.showError(L("error.confirm_required"))
            isValid = false
        } else if !Validator.passwordsMatch(passwordField.text, confirmPasswordField.text) {
            confirmPasswordField.showError(L("error.passwords_mismatch"))
            isValid = false
        }

        if !termsAccepted {
            termsCheckbox.shake()
            isValid = false
        }

        return isValid
    }

    private func configureLabel(_ label: UILabel, text: String) {
        label.text = text
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = colors.dsTextMuted
    }

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

    /// Re-applies directly-set text/line colors on a live appearance change.
    private func applyThemeColors() {
        let colors = self.colors
        titleLabel.textColor = colors.dsText
        subtitleLabel.textColor = colors.dsTextMuted
        emailLabel.textColor = colors.dsTextMuted
        passwordLabel.textColor = colors.dsTextMuted
        confirmLabel.textColor = colors.dsTextMuted
        passwordHint.textColor = colors.dsTextSubtle
        termsText.textColor = colors.dsTextMuted
        haveAccountLabel.textColor = colors.dsTextMuted
        dividerLabel.textColor = colors.dsTextSubtle
        dividerLines.forEach { $0.backgroundColor = colors.dsBorder }
        loginButton.setTitleColor(colors.dsAccent, for: .normal)
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

    @objc private func toggleTerms() {
        termsAccepted = termsCheckbox.isChecked
        // Gate the primary button on acceptance.
        createButton.isFormEnabled = termsAccepted
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
                        showConfirmationState()
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

    @objc private func appleSignUpTapped() {
        guard let authService: AuthService = ServiceManager.shared.getService() else {
            return
        }

        Task {
            do {
                try await authService.signInWithApple()
            } catch {
                print("Apple sign up failed: \(error.localizedDescription)")
            }
        }
    }

    @objc private func loginTapped() {
        dismiss(animated: true)
    }

    // MARK: - Keyboard Handling

    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }

        let keyboardHeight = keyboardFrame.height
        scrollView.contentInset.bottom = keyboardHeight
        scrollView.verticalScrollIndicatorInsets.bottom = keyboardHeight

        if let activeField = activeTextField {
            let fieldFrame = activeField.convert(activeField.bounds, to: scrollView)
            scrollView.scrollRectToVisible(fieldFrame.insetBy(dx: 0, dy: -20), animated: true)
        }
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        guard let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval else { return }

        UIView.animate(withDuration: duration) {
            self.scrollView.contentInset.bottom = 0
            self.scrollView.verticalScrollIndicatorInsets.bottom = 0
        }
    }
}

// MARK: - UITextFieldDelegate

extension SignUpViewController: UITextFieldDelegate {
    func textFieldDidBeginEditing(_ textField: UITextField) {
        activeTextField = textField.superview?.superview
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        activeTextField = nil
    }
}

// MARK: - UITextViewDelegate

extension SignUpViewController: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        let safari = SFSafariViewController(url: URL)
        present(safari, animated: true)
        return false
    }
}
