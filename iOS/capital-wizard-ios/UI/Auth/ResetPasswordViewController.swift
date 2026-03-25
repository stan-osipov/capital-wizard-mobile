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

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let cardView = AnimatedCardView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let emailField = ValidatedTextField(placeholder: "you@example.com")
    private let sendButton = GradientButton()
    private let backButton = UIButton(type: .system)
    private let termsTextView = UITextView()
    private let successView = UIView()

    private lazy var windowsService: WindowsService? = ServiceManager.shared.getService()
    private var activeTextField: UIView?

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

        titleLabel.text      = L("reset.title")
        titleLabel.font      = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.textColor = windowsService?.colors.textPrimary

        subtitleLabel.text          = L("reset.subtitle")
        subtitleLabel.font          = .systemFont(ofSize: 14)
        subtitleLabel.textColor     = windowsService?.colors.textSecondary
        subtitleLabel.numberOfLines = 0

        let emailLabel       = UILabel()
        emailLabel.text      = L("field.email")
        emailLabel.font      = .systemFont(ofSize: 14, weight: .medium)
        emailLabel.textColor = windowsService?.colors.textPrimary

        sendButton.setTitle(L("reset.button"), for: .normal)
        sendButton.addTarget(self, action: #selector(sendResetTapped), for: .touchUpInside)

        backButton.setTitle(L("reset.back"), for: .normal)
        backButton.setTitleColor(windowsService?.colors.linkColor, for: .normal)
        backButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
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
            cardView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: -70),
            cardView.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 24),
            cardView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -24),
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

            termsTextView.topAnchor.constraint(equalTo: cardView.bottomAnchor, constant: 24),
            termsTextView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 40),
            termsTextView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -40)
        ])
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
        successLabel.text          = L("reset.success_title")
        successLabel.font          = .systemFont(ofSize: 16, weight: .semibold)
        successLabel.textColor     = windowsService?.colors.textPrimary
        successLabel.textAlignment = .center
        successLabel.translatesAutoresizingMaskIntoConstraints = false

        let descLabel = UILabel()
        descLabel.text = L("reset.success_description")
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
