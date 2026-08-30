//
//  ReferralIntake.swift
//  capital-wizard-ios
//

import Foundation

/// Where a referral code comes from on this device, and what shape it has to be.
///
/// A code has to survive the gap between "I tapped Olena's link" and "I filled in
/// the sign-up form", and on a phone that gap can contain the App Store. Three
/// sources, tried in this order:
///
///   1. **A universal link this launch** — `capital-wizard.com/r/CODE` reached
///      `DeepLinkService` because the app was already installed. Exact, and the
///      only one that asks nothing of the person.
///   2. **The clipboard, on a tap** — the claim page prints the code beside a
///      Copy button, and the pasteboard is the ONLY thing that crosses an App
///      Store install on iOS. Apple ships no install-time payload of any kind:
///      campaign parameters on an App Store URL reach App Analytics, never the
///      app. (Android *does* have one, which is why `InstallReferrerService`
///      exists over there and nothing here mirrors it.)
///
///      Read from the sign-up screen's own Paste button, never automatically.
///      Reading `UIPasteboard.general.string` unprompted raises a **modal**
///      "would like to paste from…" alert whose default button is *Don't Allow*
///      — and on a first launch it fires over the splash, before the person has
///      seen a single screen of the app. On a deliberate tap the same alert is
///      ordinary iOS, and it is where Android's own clipboard-read toast lands.
///
///      A `UIPasteControl` avoids the alert entirely and was tried first. It
///      draws its label in the DEVICE's language rather than the app's, so a
///      phone set to English showed "Paste" beside a Ukrainian hint telling the
///      person to tap «Вставити» — this screen has its own locale pill, so the
///      mismatch is not an edge case — and it cannot be styled past a fill
///      colour, leaving an empty clipboard looking like a broken button.
///   3. **Typed by hand** — the field is always present and always editable, and
///      the server still accepts a code for a week after the account is created.
///
/// None of this is a guarantee and it must not pretend to be. A wrong code sitting
/// in the box is worse than an empty box, so every source is validated against the
/// same alphabet the database's own check constraint uses before it is shown.
enum ReferralIntake {

    /// A paste holding a whole article is somebody's reading, not a code.
    /// Applied before the value is used, so a large paste is discarded outright.
    static let maxPasteLength = 64

    private static let rememberedKey = "cw.referral.pending"
    private static let rememberedAtKey = "cw.referral.pendingSavedAt"

    /// Generous by design, and the same window `src/lib/pendingReferral.ts` uses
    /// on the web: somebody may meet the link days before they sign up, and a
    /// stale code costs nothing — the server still refuses one once the account
    /// is over a week old. 30 days, matching the attribution window we advertise.
    private static let maxAge: TimeInterval = 30 * 24 * 60 * 60

    // MARK: - Shape

    /// Upper-cases and trims `raw`, returning it only if it could be a referral
    /// code. The alphabet matches `DeepLinkService.referralCode(fromPath:)` and
    /// the database's own check constraint: anything else is not a code we could
    /// resolve, so showing it would only invite a person to submit it.
    static func normalized(_ raw: String?) -> String? {
        guard let raw = raw else { return nil }
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count >= 3, code.count <= 32,
              code.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }),
              let first = code.first, first != "-" else { return nil }
        return code
    }

    // MARK: - Surviving a relaunch

    /// Keeps a code across app launches.
    ///
    /// `DeepLinkService` holds it in memory, which lasts exactly as long as the
    /// process: somebody who taps the link, reaches the form and then puts their
    /// phone down has lost it by the time they come back. That is the same gap
    /// the App Store opens, one launch later, so it gets the same answer.
    /// `defaults` is injectable so tests get their own store — these are global
    /// keys, and a suite that runs in parallel would otherwise race itself.
    static func remember(_ code: String, into defaults: UserDefaults = .standard) {
        guard let code = normalized(code) else { return }
        defaults.set(code, forKey: rememberedKey)
        defaults.set(Date().timeIntervalSince1970, forKey: rememberedAtKey)
    }

    /// The remembered code, if there is one and it has not gone stale.
    static func remembered(from defaults: UserDefaults = .standard) -> String? {
        guard let code = normalized(defaults.string(forKey: rememberedKey)) else { return nil }
        let savedAt = defaults.double(forKey: rememberedAtKey)
        guard savedAt > 0, Date().timeIntervalSince1970 - savedAt <= maxAge else {
            forget(from: defaults)
            return nil
        }
        return code
    }

    /// Drops the remembered code.
    ///
    /// Called once an account has signed in on this device: from that moment the
    /// web app owns redemption, and leaving it here would pre-fill somebody
    /// else's code onto a SECOND account created on the same phone.
    static func forget(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: rememberedKey)
        defaults.removeObject(forKey: rememberedAtKey)
    }

    // MARK: - Prefill

    /// The code to put in the sign-up field, or `nil` to leave it empty.
    ///
    /// Only the link leg is automatic — this launch's, or one remembered from an
    /// earlier one. Everything else is a deliberate act by the person: the paste
    /// button, or the keyboard.
    static func prefill(deepLinkService: DeepLinkService?,
                        defaults: UserDefaults = .standard) -> String? {
        if let code = normalized(deepLinkService?.pendingReferralCode) {
            CWLog.shared.log("Referral prefill from deep link → \(code)", category: "Referral")
            return code
        }
        if let code = remembered(from: defaults) {
            CWLog.shared.log("Referral prefill from an earlier launch → \(code)", category: "Referral")
            return code
        }
        return nil
    }

    /// A pasted string turned into a code, or `nil` if it is not one.
    static func fromPaste(_ raw: String) -> String? {
        guard raw.count <= maxPasteLength else { return nil }
        return normalized(raw)
    }
}
