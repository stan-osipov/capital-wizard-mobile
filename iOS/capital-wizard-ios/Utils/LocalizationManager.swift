//
//  LocalizationManager.swift
//  capital-wizard-ios
//

import Foundation

class LocalizationManager {
    static let shared = LocalizationManager()

    private let languageKey = "app_language"
    private var bundle: Bundle?

    struct Language {
        let code: String
        let flag: String
        let name: String
    }

    let supportedLanguages: [Language] = [
        Language(code: "en", flag: "🇬🇧", name: "English"),
        Language(code: "uk", flag: "🇺🇦", name: "Українська")
    ]

    var currentLanguage: String {
        get {
            if let saved = UserDefaults.standard.string(forKey: languageKey) {
                return saved
            }
            let preferred = Locale.preferredLanguages.first ?? "en"
            if preferred.hasPrefix("uk") {
                return "uk"
            }
            // Check device region — if in Ukraine, default to Ukrainian
            if let region = Locale.current.region?.identifier, region == "UA" {
                return "uk"
            }
            return "en"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: languageKey)
            updateBundle()
        }
    }

    var currentFlag: String {
        supportedLanguages.first { $0.code == currentLanguage }?.flag ?? "🇬🇧"
    }

    var otherLanguage: Language {
        supportedLanguages.first { $0.code != currentLanguage } ?? supportedLanguages[0]
    }

    private init() {
        updateBundle()
    }

    private func updateBundle() {
        let lang = currentLanguage
        if let path = Bundle.main.path(forResource: lang, ofType: "lproj") {
            bundle = Bundle(path: path)
        } else if let path = Bundle.main.path(forResource: "en", ofType: "lproj") {
            bundle = Bundle(path: path)
        } else {
            bundle = Bundle.main
        }
    }

    func string(_ key: String) -> String {
        return bundle?.localizedString(forKey: key, value: nil, table: nil) ?? key
    }
}

func L(_ key: String) -> String {
    return LocalizationManager.shared.string(key)
}
