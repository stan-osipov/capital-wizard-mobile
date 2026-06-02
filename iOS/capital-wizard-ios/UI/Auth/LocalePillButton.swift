//
//  LocalePillButton.swift
//  capital-wizard-ios
//
//  Locale pill shown top-right in the auth app-bar. Renders the current
//  language flag, its 2-letter display code (EN / UA) and a chevron-down,
//  inside a rounded pill (surface fill + 1px border). Tapping opens a native
//  dropdown (`UIMenu`) listing every supported language with a checkmark on
//  the active one. Selecting a language invokes `onSelect(code)` so the host
//  view controller can persist it and reload itself in the new language.
//
//  The pill's fill/border/rounding live on a non-interactive background
//  subview (`pillBG`) rather than the button's own layer. This keeps the
//  button layer unmasked so the system menu's lift/highlight animation can't
//  flicker the rounded pill into a rectangle, and the radius is re-derived
//  from the real bounds in `layoutSubviews()` so it stays a perfect pill.
//
//  Mirrors the web/Android `.locale` pill from the design handoff.
//

import UIKit

class LocalePillButton: UIButton {

    /// Called with the chosen language code (e.g. "en" / "uk"). The host VC
    /// persists it via `LocalizationManager` and reloads its own screen.
    var onSelect: ((String) -> Void)?

    private let pillBG = UIView()
    private let flagLabel = UILabel()
    private let codeLabel = UILabel()
    private let chevronView = UIImageView()

    private lazy var windowsService: WindowsService? = ServiceManager.shared.getService()

    init() {
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var effectiveStyle: UIUserInterfaceStyle {
        if traitCollection.userInterfaceStyle != .unspecified {
            return traitCollection.userInterfaceStyle
        }
        return windowsService?.window.traitCollection.userInterfaceStyle ?? .dark
    }

    /// 2-letter display code for the pill ("uk" is shown as "UA" per design).
    private static func displayCode(for languageCode: String) -> String {
        languageCode == "uk" ? "UA" : languageCode.uppercased()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false

        // The pill shape lives on a non-interactive background view so the
        // button's own layer stays unmasked (see file header).
        pillBG.isUserInteractionEnabled = false
        pillBG.layer.borderWidth = 1
        pillBG.layer.masksToBounds = true
        pillBG.layer.cornerCurve = .continuous
        pillBG.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pillBG)

        let manager = LocalizationManager.shared

        flagLabel.font = .systemFont(ofSize: 14)
        flagLabel.text = manager.currentFlag
        flagLabel.isUserInteractionEnabled = false

        codeLabel.font = .systemFont(ofSize: 12, weight: .medium)
        codeLabel.text = Self.displayCode(for: manager.currentLanguage)
        codeLabel.isUserInteractionEnabled = false

        let chevronConfig = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        chevronView.image = UIImage(systemName: "chevron.down", withConfiguration: chevronConfig)
        chevronView.contentMode = .scaleAspectFit
        chevronView.isUserInteractionEnabled = false
        chevronView.setContentHuggingPriority(.required, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [flagLabel, codeLabel, chevronView])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 5
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 32),

            pillBG.topAnchor.constraint(equalTo: topAnchor),
            pillBG.bottomAnchor.constraint(equalTo: bottomAnchor),
            pillBG.leadingAnchor.constraint(equalTo: leadingAnchor),
            pillBG.trailingAnchor.constraint(equalTo: trailingAnchor),

            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -11),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        applyColors()
        rebuildMenu()
        showsMenuAsPrimaryAction = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Always a perfect pill, regardless of any transient bounds change.
        pillBG.layer.cornerRadius = pillBG.bounds.height / 2
    }

    /// Rebuilds the dropdown so the checkmark tracks the current language.
    private func rebuildMenu() {
        let manager = LocalizationManager.shared
        let current = manager.currentLanguage

        let actions = manager.supportedLanguages.map { language -> UIAction in
            let title = "\(language.flag)  \(language.name)"
            return UIAction(
                title: title,
                state: language.code == current ? .on : .off
            ) { [weak self] _ in
                self?.onSelect?(language.code)
            }
        }
        menu = UIMenu(title: "", options: .displayInline, children: actions)
    }

    /// Refreshes flag/code/menu after the language changes (when reused).
    func refreshLanguage() {
        let manager = LocalizationManager.shared
        flagLabel.text = manager.currentFlag
        codeLabel.text = Self.displayCode(for: manager.currentLanguage)
        rebuildMenu()
    }

    func applyColors() {
        let colors = AppColors.colors(for: effectiveStyle)
        pillBG.backgroundColor = colors.dsSurface
        pillBG.layer.borderColor = colors.dsBorder.cgColor
        codeLabel.textColor = colors.dsTextMuted
        chevronView.tintColor = colors.dsTextMuted
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            applyColors()
        }
    }
}
