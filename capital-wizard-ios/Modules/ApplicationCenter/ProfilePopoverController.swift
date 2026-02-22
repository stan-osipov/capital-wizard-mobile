//
//  ProfilePopoverController.swift
//  capital-wizard-ios
//
//  Created by Roman on 22.02.2026.
//

import UIKit

class ProfilePopoverController: UIViewController {

    private lazy var authService: AuthService? = ServiceManager.shared.getService()

    private let colorScheme: ColorScheme

    init(colorScheme: ColorScheme) {
        self.colorScheme = colorScheme
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
    }

    private func setupView() {
        let colors = AppColors(scheme: colorScheme)
        view.backgroundColor = colors.backgroundColor

        let titleLabel = UILabel()
        titleLabel.text = "Profile"
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = colors.tintColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let schemeLabel = UILabel()
        schemeLabel.text = "Color Scheme"
        schemeLabel.font = .systemFont(ofSize: 13, weight: .medium)
        schemeLabel.textColor = colors.textSecondary
        schemeLabel.translatesAutoresizingMaskIntoConstraints = false

        let segmentedControl = UISegmentedControl(items: ["Light", "Dark", "System"])
        segmentedControl.selectedSegmentIndex = segmentIndex(for: colorScheme)
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false

        let separator = UIView()
        separator.backgroundColor = colors.separatorLine.withAlphaComponent(0.4)
        separator.translatesAutoresizingMaskIntoConstraints = false

        let logoutButton = UIButton(type: .system)
        logoutButton.setTitle("Log Out", for: .normal)
        logoutButton.setTitleColor(colors.errorRed, for: .normal)
        logoutButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        logoutButton.addTarget(self, action: #selector(logoutTapped), for: .touchUpInside)
        logoutButton.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(titleLabel)
        view.addSubview(schemeLabel)
        view.addSubview(segmentedControl)
        view.addSubview(separator)
        view.addSubview(logoutButton)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            schemeLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 24),
            schemeLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            segmentedControl.topAnchor.constraint(equalTo: schemeLabel.bottomAnchor, constant: 8),
            segmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            segmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            separator.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 24),
            separator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),

            logoutButton.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 16),
            logoutButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            logoutButton.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])
    }

    private func segmentIndex(for scheme: ColorScheme) -> Int {
        switch scheme {
        case .light:                    return 0
        case .dark:                     return 1
        case .systemLight, .systemDark: return 2
        }
    }

    @objc private func logoutTapped() {
        dismiss(animated: true)
        Task { [weak self] in
            try? await self?.authService?.signOut()
        }
    }
}
