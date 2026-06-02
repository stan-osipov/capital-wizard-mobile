//
//  ResetPasswordViewController.swift
//  capital-wizard-ios
//
//  Created by Roman on 07.02.2026.
//

import UIKit
import SafariServices

class ResetPasswordViewController: UIViewController {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .portrait
    }

    private let backgroundView = AuthBackgroundView()
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let cardView = AnimatedCardView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let emailField = ValidatedTextField(placeholder: "you@example.com")
    private let sendButton = SolidButton()
    private let backButton = UIButton(type: .system)
    private let termsTextView = UITextView()
    private let successView = UIView()
    private let emailLabel = UILabel()

    // Locale pill (top-right).
    private let localePill = LocalePillButton()

    private lazy var windowsService: WindowsService? = ServiceManager.shared.getService()
    private var activeTextField: UIView?

    private var effectiveStyle: UIUserInterfaceStyle {
        if traitCollection.userInterfaceStyle != .unspecified {
            return traitCollection.userInterfaceStyle
        }
        return windowsService?.window.traitCollection.userInterfaceStyle ?? .dark
    }
    private var colors: AppColors { AppColors.colors(for: effectiveStyle) }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
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

        titleLabel.text      = L("reset.title")
        titleLabel.font      = .systemFont(ofSize: 24, weight: .semibold)
        titleLabel.textColor = colors.dsText

        subtitleLabel.text          = L("reset.subtitle")
        subtitleLabel.font          = .systemFont(ofSize: 14)
        subtitleLabel.textColor     = colors.dsTextMuted
        subtitleLabel.numberOfLines = 0

        emailLabel.text      = L("field.email")
        emailLabel.font      = .systemFont(ofSize: 12, weight: .medium)
        emailLabel.textColor = colors.dsTextMuted

        sendButton.setTitle(L("reset.button"), for: .normal)
        sendButton.addTarget(self, action: #selector(sendResetTapped), for: .touchUpInside)

        backButton.setTitle(L("reset.back"), for: .normal)
        backButton.setTitleColor(colors.dsAccent, for: .normal)
        backButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)

        setupTermsTextView()
        termsTextView.translatesAutoresizingMaskIntoConstraints = false
        termsTextView.alpha = 0

        // Success View (hidden initially)
        setupSuccessView()

        [titleLabel, subtitleLabel, emailLabel, emailField, sendButton, backButton, successView].forEach {
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
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: cardView.trailingAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            subtitleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),

            emailLabel.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 28),
            emailLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),

            emailField.topAnchor.constraint(equalTo: emailLabel.bottomAnchor, constant: 6),
            emailField.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            emailField.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),

            sendButton.topAnchor.constraint(equalTo: emailField.bottomAnchor, constant: 24),
            sendButton.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            sendButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            sendButton.heightAnchor.constraint(equalToConstant: 48),

            backButton.topAnchor.constraint(equalTo: sendButton.bottomAnchor, constant: 18),
            backButton.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
            backButton.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),

            successView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 28),
            successView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            successView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),

            termsTextView.topAnchor.constraint(equalTo: cardView.bottomAnchor, constant: 24),
            termsTextView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 40),
            termsTextView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -40),
            termsTextView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -16)
        ])
    }

    /// Re-reads every localized string in place after a language change so the
    /// screen updates without presenting a fresh view controller.
    private func applyLocalizedStrings() {
        titleLabel.text = L("reset.title")
        subtitleLabel.text = L("reset.subtitle")
        emailLabel.text = L("field.email")
        sendButton.setTitle(L("reset.button"), for: .normal)
        backButton.setTitle(L("reset.back"), for: .normal)
        setupTermsTextView()
    }

    /// Re-applies directly-set text colors on a live system-appearance change.
    private func applyThemeColors() {
        let colors = self.colors
        titleLabel.textColor = colors.dsText
        subtitleLabel.textColor = colors.dsTextMuted
        emailLabel.textColor = colors.dsTextMuted
        backButton.setTitleColor(colors.dsAccent, for: .normal)
        localePill.applyColors()
        setupTermsTextView()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            applyThemeColors()
        }
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

    private func setupSuccessView() {
        successView.alpha = 0
        successView.isHidden = true

        let iconContainer                = UIView()
        iconContainer.backgroundColor    = colors.successGreen.withAlphaComponent(0.16)
        iconContainer.layer.cornerRadius = 30
        iconContainer.translatesAutoresizingMaskIntoConstraints = false

        let checkIcon = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
        checkIcon.tintColor = colors.successGreen
        checkIcon.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.addSubview(checkIcon)

        let successLabel           = UILabel()
        successLabel.text          = L("reset.success_title")
        successLabel.font          = .systemFont(ofSize: 16, weight: .semibold)
        successLabel.textColor     = colors.dsText
        successLabel.textAlignment = .center
        successLabel.translatesAutoresizingMaskIntoConstraints = false

        let descLabel = UILabel()
        descLabel.text = L("reset.success_description")
        descLabel.font = .systemFont(ofSize: 14)
        descLabel.textColor = colors.dsTextMuted
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

    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(_:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)

        emailField.textField.delegate = self
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    @objc private func sendResetTapped() {
        dismissKeyboard()

        if emailField.text.isEmpty {
            emailField.showError(L("error.email_required"))
            return
        }

        if !Validator.isValidEmail(emailField.text) {
            emailField.showError(L("error.email_invalid"))
            return
        }

        sendButton.startLoading()

        guard let authService: AuthService = ServiceManager.shared.getService() else {
            sendButton.stopLoading()
            return
        }

        Task {
            do {
                try await authService.client.resetPasswordForEmail(emailField.text)
                await MainActor.run {
                    sendButton.stopLoading()
                    showSuccessState()
                }
            } catch {
                await MainActor.run {
                    sendButton.stopLoading()
                    emailField.showError(error.localizedDescription)
                }
            }
        }
    }

    @objc private func backTapped() {
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

extension ResetPasswordViewController: UITextFieldDelegate {
    func textFieldDidBeginEditing(_ textField: UITextField) {
        activeTextField = textField.superview?.superview
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        activeTextField = nil
    }
}

// MARK: - UITextViewDelegate

extension ResetPasswordViewController: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        let safari = SFSafariViewController(url: URL)
        present(safari, animated: true)
        return false
    }
}
