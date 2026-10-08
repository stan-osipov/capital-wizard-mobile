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
        // iPhone stays portrait; iPad rotates freely (the card is centered
        // and width-capped, so it lays out fine in any orientation).
        UIDevice.current.userInterfaceIdiom == .pad ? .all : .portrait
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
    // Optional, and the reason this screen leads on a fresh install: a referral
    // code may have arrived through a link, or crossed the App Store on the
    // clipboard, and Create Account is the only place a person expects to see it.
    private let referralField = ValidatedTextField(placeholder: "ABCD-1234")
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
    private let referralLabel = UILabel()
    private let referralHint = UILabel()
    /// Paste button — the WORD, inside the referral field, on the password
    /// toggle's geometry. Android is the same control in the same place (the
    /// `TextInputLayout` suffix), so the two screens read as translations of
    /// each other down to the tap target.
    ///
    /// Inside rather than above the label: the control acts on the box, and one
    /// floating over the label read as a second thing to do.
    ///
    /// A word rather than a glyph, and that is the whole point of it being ours.
    /// `LocalizationManager` is a private bundle lookup behind `L()`, wired to
    /// the locale pill ten points up this same screen, and it resolves to
    /// Ukrainian for a UA-region phone whose system language is English — so
    /// anything the SYSTEM labels is in the wrong language in the ordinary case,
    /// not the edge one. Only a string we own follows the pill. A glyph dodged
    /// that by saying nothing at all, which also left the hint under the field
    /// with nothing to name: it had to say "tap the paste icon", which is what
    /// you write when the button has no name.
    ///
    /// A plain button and not a `UIPasteControl`, and the cost is known rather
    /// than overlooked. The system control pastes with no alert, where reading
    /// `UIPasteboard` ourselves raises a modal whose PROMINENT button is *Don't
    /// Allow Paste* — checked on the simulator, not assumed — standing in front
    /// of the one action that decides whether a referral is credited. It cannot
    /// live here anyway: it ignores a `.clear` `baseBackgroundColor`, falling
    /// back to its own filled capsule, and with no intrinsic width to pin it
    /// against it stretched across the field. If the alert ever proves to cost
    /// signups, the way back is this same button opening the system EDIT MENU on
    /// the focused field — a paste picked there is user-initiated and prompts
    /// nothing — which keeps every pixel of this design and changes only the
    /// handler.
    private let referralPaste = UIButton(type: .system)
    private let termsText = UILabel()
    private let haveAccountLabel = UILabel()
    private let dividerLabel = UILabel()
    private var dividerLines: [UIView] = []

    private var termsAccepted = false
    /// Set the moment the person types in the referral box. From then on a code
    /// the device turns up later is dropped rather than written over theirs.
    private var referralTouched = false
    /// Held rather than made inline: `Event` unsubscribes by identity, so a
    /// fresh closure in `deinit` would remove nothing and leave this controller
    /// on the service's listener list for the life of the process.
    private lazy var onReferralCallback = EventCallback<String> { [weak self] code in
        DispatchQueue.main.async { self?.fillReferral(code) }
    }
    private var activeTextField: UIView?
    private var formBottomConstraint: NSLayoutConstraint?
    private var confirmBottomConstraint: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupValidation()
        setupKeyboardObservers()
        applyReferralPrefill()
        observeLateReferral()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        cardView.animateIn()
        UIView.animate(withDuration: 0.25) { self.termsTextView.alpha = 1 }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        let deepLinkService: DeepLinkService? = ServiceManager.shared.getService()
        deepLinkService?.onReferralCode -= onReferralCallback
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

        configureLabel(referralLabel, text: L("signup.referral_label"))
        // Capitals from the keyboard rather than rewriting the text under the
        // caret on every keystroke — codes are stored upper-case, and a field
        // that re-assigns its own value mid-edit jumps the cursor.
        referralField.textField.autocapitalizationType = .allCharacters
        referralField.textField.returnKeyType = .done
        referralHint.text = L("signup.referral_hint")
        referralHint.font = .systemFont(ofSize: 12)
        referralHint.textColor = colors.dsTextSubtle
        referralHint.numberOfLines = 0

        // The word, INSIDE the field, on the password toggle's own geometry. No
        // fixed width — the word is a different length in every language, and a
        // pinned one would clip «Вставити» to fit "Paste". REQUIRED hugging is
        // what stands in for that width: the accessory slot hands its slack to
        // whatever sits in it, so a control that does not hug its own title
        // grows across the value it sits beside.
        referralPaste.setTitle(L("signup.referral_paste"), for: .normal)
        referralPaste.setTitleColor(colors.dsAccent, for: .normal)
        referralPaste.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        referralPaste.setContentHuggingPriority(.required, for: .horizontal)
        referralPaste.setContentCompressionResistancePriority(.required, for: .horizontal)
        referralPaste.addTarget(self, action: #selector(pasteReferralTapped), for: .touchUpInside)
        referralField.setTrailingAccessory(referralPaste)

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
         passwordHint, confirmLabel, confirmPasswordField, referralLabel, referralField,
         referralHint, termsStack, createButton,
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

            referralLabel.topAnchor.constraint(equalTo: confirmPasswordField.bottomAnchor, constant: 14),
            referralLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),

            referralField.topAnchor.constraint(equalTo: referralLabel.bottomAnchor, constant: 6),
            referralField.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            referralField.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),

            referralHint.topAnchor.constraint(equalTo: referralField.bottomAnchor, constant: 6),
            referralHint.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            referralHint.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),

            termsStack.topAnchor.constraint(equalTo: referralHint.bottomAnchor, constant: 14),
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
        referralLabel.text = L("signup.referral_label")
        referralHint.text = L("signup.referral_hint")
        // The glyph carries no text; its accessibility label is the only string.
        referralPaste.setTitle(L("signup.referral_paste"), for: .normal)
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
            attributed.addAttribute(.link, value: AppProduct.current.legalOrigin + "/terms", range: nsRange)
        }
        if let privacyRange = text.range(of: privacyWord) {
            let nsRange = NSRange(privacyRange, in: text)
            attributed.addAttribute(.link, value: AppProduct.current.legalOrigin + "/privacy", range: nsRange)
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
        // `onTextChanged` fires on `.editingChanged` only, so this is the
        // person's own typing — never our own pre-fill writing into the field.
        referralField.onTextChanged = { [weak self] _ in
            self?.referralTouched = true
            self?.referralField.clearError()
            self?.updateReferralPasteVisibility()
        }
        referralField.textField.delegate = self
    }

    /// Fills the box from the clipboard when the paste button is tapped.
    ///
    /// Read HERE, in the button's own handler, so iOS's "would like to paste
    /// from…" alert lands on an action the person just took — never unprompted
    /// at launch, which is the one place it must not appear at all (it fires
    /// over the splash, before they have seen a screen of the app).
    ///
    /// A paste that is not a code is REFUSED rather than dropped into the field:
    /// somebody who pasted the wrong thing needs to see that, and a box silently
    /// left empty after a deliberate tap reads as a broken button.
    @objc private func pasteReferralTapped() {
        guard let code = ReferralIntake.fromPaste(UIPasteboard.general.string ?? "") else {
            referralField.showError(L("error.referral_invalid"))
            return
        }
        referralField.clearError()
        // Pasting is as deliberate as typing, so it locks the box the same way: a
        // code arriving from a link a second later must not replace it. Writing
        // the field programmatically raises no `.editingChanged`, so the latch
        // that typing sets for free has to be set by hand here.
        referralTouched = true
        referralField.textField.text = code
        updateReferralPasteVisibility()
    }

    /// The paste button is for an EMPTY box. Once there is a code in there,
    /// offering to replace it is offering to undo what just happened.
    private func updateReferralPasteVisibility() {
        referralPaste.isHidden = !referralField.text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Puts a code in the box if this device has one to offer.
    ///
    /// Runs when the screen is built rather than at launch, because the
    /// clipboard leg of `ReferralIntake` is user-visible — iOS posts a "pasted
    /// from Safari" banner — and this is the one screen where the answer is used.
    private func applyReferralPrefill() {
        let deepLinkService: DeepLinkService? = ServiceManager.shared.getService()
        if let code = ReferralIntake.prefill(deepLinkService: deepLinkService) {
            fillReferral(code)
        }
        updateReferralPasteVisibility()
    }

    /// Writes a code the device found into the box — unless the person has
    /// started filling it in themselves, in which case theirs wins. Silent by
    /// design: the hint under the field already says the box fills itself.
    private func fillReferral(_ code: String) {
        guard !referralTouched else { return }
        referralField.clearError()
        referralField.textField.text = code
        updateReferralPasteVisibility()
    }

    /// A code can arrive AFTER this screen is on the table — a `/r/CODE` link
    /// tapped while the app was already open and sitting on Create Account. The
    /// field has to take it: this is the first launch, so nothing else in the
    /// app will ever ask for the code again.
    private func observeLateReferral() {
        let deepLinkService: DeepLinkService? = ServiceManager.shared.getService()
        deepLinkService?.onReferralCode += onReferralCallback
    }

    /// Hands whatever is in the box to the web app, whichever way the account
    /// ends up being created — the field is editable, so what they SEND is what
    /// has to travel, not what arrived.
    private func stashReferralCode() {
        guard !referralField.text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let deepLinkService: DeepLinkService? = ServiceManager.shared.getService()
        deepLinkService?.stashReferral(code: referralField.text)
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

        // Optional, so an empty box always passes. But a code somebody typed and
        // got wrong must not be swallowed silently — that reads as "applied" and
        // is only discovered when the bonus never arrives.
        if !referralField.text.trimmingCharacters(in: .whitespaces).isEmpty,
           ReferralIntake.normalized(referralField.text) == nil {
            referralField.showError(L("error.referral_invalid"))
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

        stashReferralCode()
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

        // Social sign-up creates the account just as the form does, so the code
        // has to be handed over here too.
        stashReferralCode()

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

        // Social sign-up creates the account just as the form does, so the code
        // has to be handed over here too.
        stashReferralCode()

        Task {
            do {
                try await authService.signInWithApple()
            } catch {
                print("Apple sign up failed: \(error.localizedDescription)")
            }
        }
    }

    @objc private func loginTapped() {
        // Presented from Login — go back the way we came. Rooted here instead
        // (a first launch, where Create Account leads) there is nothing to
        // dismiss, and a back button that does nothing strands the person on
        // the one screen they cannot use.
        if presentingViewController != nil {
            dismiss(animated: true)
        } else {
            windowsService?.showLogin()
        }
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
