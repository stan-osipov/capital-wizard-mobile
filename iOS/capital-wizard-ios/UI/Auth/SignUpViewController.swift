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

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let cardView = AnimatedCardView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let emailField = ValidatedTextField(placeholder: "you@example.com")
    private let passwordField = ValidatedTextField(placeholder: "••••••••", isSecure: true, showPasswordToggle: true)
    private let confirmPasswordField = ValidatedTextField(placeholder: "••••••••", isSecure: true, showPasswordToggle: true)
    private let termsCheckbox = UIButton(type: .custom)
    private let createButton = GradientButton()
    private let googleButton = UIButton(type: .system)
    private lazy var appleButton = ASAuthorizationAppleIDButton(type: .signUp, style: traitCollection.userInterfaceStyle == .dark ? .white : .black)
    private let loginButton = UIButton(type: .system)
    private let termsTextView = UITextView()
    private let confirmationView = UIView()
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
        view.backgroundColor = windowsService?.colors.backgroundColor

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)

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

        titleLabel.text = L("signup.title")
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.textColor = windowsService?.colors.textPrimary

        subtitleLabel.text = L("signup.subtitle")
        subtitleLabel.font = .systemFont(ofSize: 14)
        subtitleLabel.textColor = windowsService?.colors.textSecondary

        let emailLabel = createLabel(L("field.email"))
        let passwordLabel = createLabel(L("field.password"))
        let confirmLabel = createLabel(L("field.confirm_password"))

        let passwordHint = UILabel()
        passwordHint.text = L("signup.password_hint")
        passwordHint.font = .systemFont(ofSize: 12)
        passwordHint.textColor = windowsService?.colors.textSecondary

        // Terms Checkbox — fixed size with proper symbol configuration
        let checkboxConfig = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        termsCheckbox.setImage(UIImage(systemName: "square", withConfiguration: checkboxConfig), for: .normal)
        termsCheckbox.setImage(UIImage(systemName: "checkmark.square.fill", withConfiguration: checkboxConfig), for: .selected)
        termsCheckbox.tintColor = windowsService?.colors.textSecondary
        termsCheckbox.addTarget(self, action: #selector(toggleTerms), for: .touchUpInside)
        termsCheckbox.setContentHuggingPriority(.required, for: .horizontal)
        termsCheckbox.setContentCompressionResistancePriority(.required, for: .horizontal)
        termsCheckbox.imageView?.contentMode = .scaleAspectFit

        let termsText = UILabel()
        termsText.text = L("signup.terms_agree")
        termsText.font = .systemFont(ofSize: 14)
        termsText.textColor = windowsService?.colors.textSecondary
        termsText.numberOfLines = 0

        let termsStack = UIStackView(arrangedSubviews: [termsCheckbox, termsText])
        termsStack.spacing = 8
        termsStack.alignment = .top

        createButton.setTitle(L("signup.button"), for: .normal)
        createButton.addTarget(self, action: #selector(createTapped), for: .touchUpInside)

        let dividerStack = createDivider(text: L("signup.divider"))

        // Google button — bordered style
        setupGoogleButton(title: L("signup.google"))

        // Apple button
        appleButton.cornerRadius = 8
        appleButton.addTarget(self, action: #selector(appleSignUpTapped), for: .touchUpInside)

        let haveAccountLabel = UILabel()
        haveAccountLabel.text = L("signup.have_account")
        haveAccountLabel.font = .systemFont(ofSize: 14)
        haveAccountLabel.textColor = windowsService?.colors.textSecondary

        loginButton.setTitle(L("signup.login_here"), for: .normal)
        loginButton.setTitleColor(windowsService?.colors.linkColor, for: .normal)
        loginButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
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

            cardView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            cardView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: -50),
            cardView.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 24),
            cardView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -24),
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

            // Terms checkbox with fixed width
            termsCheckbox.widthAnchor.constraint(equalToConstant: 28),
            termsCheckbox.heightAnchor.constraint(equalToConstant: 28),

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

            appleButton.topAnchor.constraint(equalTo: googleButton.bottomAnchor, constant: 8),
            appleButton.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),
            appleButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -24),
            appleButton.heightAnchor.constraint(equalToConstant: 40),

            loginStack.topAnchor.constraint(equalTo: appleButton.bottomAnchor, constant: 10),
            loginStack.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),

            // Confirmation view centered in card
            confirmationView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 24),
            confirmationView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),
            confirmationView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -24),

            termsTextView.topAnchor.constraint(equalTo: cardView.bottomAnchor, constant: 12),
            termsTextView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 40),
            termsTextView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -40)
        ])

        // Store switchable bottom constraints
        formBottomConstraint = loginStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -16)
        confirmBottomConstraint = confirmationView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -24)
        formBottomConstraint?.isActive = true
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

        googleButton.addTarget(self, action: #selector(googleSignUpTapped), for: .touchUpInside)
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

    private func setupConfirmationView() {
        confirmationView.alpha = 0
        confirmationView.isHidden = true

        let iconContainer = UIView()
        iconContainer.backgroundColor = windowsService?.colors.gradientFirst.withAlphaComponent(0.2)
        iconContainer.layer.cornerRadius = 30
        iconContainer.translatesAutoresizingMaskIntoConstraints = false

        let emailIcon = UIImageView(image: UIImage(systemName: "envelope.circle.fill"))
        emailIcon.tintColor = windowsService?.colors.gradientFirst
        emailIcon.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.addSubview(emailIcon)

        let titleLabel = UILabel()
        titleLabel.text = L("signup.confirm_title")
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = windowsService?.colors.textPrimary
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let descLabel = UILabel()
        descLabel.text = L("signup.confirm_description")
        descLabel.font = .systemFont(ofSize: 14)
        descLabel.textColor = windowsService?.colors.textSecondary
        descLabel.textAlignment = .center
        descLabel.numberOfLines = 0
        descLabel.translatesAutoresizingMaskIntoConstraints = false

        let backToLoginButton = UIButton(type: .system)
        backToLoginButton.setTitle(L("signup.back_to_login"), for: .normal)
        backToLoginButton.setTitleColor(windowsService?.colors.linkColor, for: .normal)
        backToLoginButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
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
