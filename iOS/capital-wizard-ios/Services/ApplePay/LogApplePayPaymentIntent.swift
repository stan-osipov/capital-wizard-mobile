//
//  LogApplePayPaymentIntent.swift
//  capital-wizard-ios
//
//  The door a Shortcuts automation hands an Apple Pay payment through.
//

import AppIntents
import Foundation

#if !CODING_LAB

/// One category a payment can book under: a transaction type, or a type and one
/// of its subtypes.
///
/// It is an `AppEntity` rather than a plain `String` parameter for one reason,
/// and it is the reason the whole feature works for people who do not want to
/// think about categories: a parameter with entity options is what lets the
/// shortcut be set to **Ask Each Time**, and iOS then draws THIS SPACE'S OWN
/// list at the moment of the tap. A string parameter would make the user type a
/// category id from memory at a till.
///
/// The options come from the config the web app pushed over the bridge
/// (`ApplePayConfigStore.categories()`), so the list is the space's real
/// taxonomy rather than anything compiled into this binary — and a space that
/// renames a type sees the new name on the phone the next time somebody opens
/// the Apple Pay settings screen.
struct ApplePayCategory: AppEntity {

    /// `"<typeId>"` for a bare type, `"<typeId>/<subtypeId>"` for a pair. The
    /// server is handed the two halves separately; this id only has to be
    /// stable and unique within one space's list.
    let id: String
    let label: String
    let typeId: String
    let subtypeId: String?

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Category")
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(label)")
    }

    static var defaultQuery = ApplePayCategoryQuery()
}

/// Answers the picker. Reads the stored config every time rather than caching:
/// the list changes when somebody edits their taxonomy, and a shortcut that is
/// set to ask each time must offer what the space has now.
struct ApplePayCategoryQuery: EntityQuery {

    func entities(for identifiers: [String]) async throws -> [ApplePayCategory] {
        let wanted = Set(identifiers)
        return all().filter { wanted.contains($0.id) }
    }

    func suggestedEntities() async throws -> [ApplePayCategory] {
        all()
    }

    private func all() -> [ApplePayCategory] {
        ApplePayConfigStore.categories().map {
            ApplePayCategory(id: $0.id, label: $0.label, typeId: $0.typeId, subtypeId: $0.subtypeId)
        }
    }
}

/// Records one Apple Pay payment.
///
/// WHAT CALLS THIS IS AN AUTOMATION, NOT A PERSON. iOS has two triggers that can
/// drive it and they report different things, which is why every parameter below
/// is optional and why the server is asked to make sense of them rather than
/// this intent:
///
///   • the Wallet-card trigger (iOS 17+) hands over a Transaction with the
///     merchant, the amount and the card as separate values;
///   • the notification trigger (iOS 27+) hands over the notification's TEXT and
///     nothing else — one line a bank wrote, in the user's own language.
///
/// Both can be set up at once and both fire for one in-store tap. That is safe:
/// the server keys a payment on merchant, amount, card and the minute it
/// happened, so the second report collides with the first and is answered
/// `duplicate`. See `applePayExternalId` in the web repo.
///
/// `openAppWhenRun` is FALSE and must stay false. The whole promise of this
/// feature is that a payment records itself; an intent that threw the app onto
/// the screen every time somebody bought a coffee would be uninstalled by the
/// end of the day.
struct LogApplePayPaymentIntent: AppIntent {

    static var title: LocalizedStringResource = "Log a payment"

    // App Store Connect validates this exported Siri metadata after upload and
    // rejects descriptions containing "Apple" (90626). Android has no App Intent
    // metadata; its unsupported capability remains unchanged.
    static var description = IntentDescription(
        "Records a payment in Capital Wizard. Run this action from a transaction or notification automation."
    )

    static var openAppWhenRun: Bool = false

    @Parameter(title: "Amount")
    var amount: Double?

    @Parameter(title: "Currency")
    var currency: String?

    @Parameter(title: "Merchant")
    var merchant: String?

    @Parameter(title: "Card")
    var card: String?

    /// The whole notification, for the trigger that carries no structured
    /// fields. The server reads an amount out of it when the fields are empty.
    @Parameter(title: "Notification text")
    var notificationText: String?

    /// Set this to **Ask Each Time** to choose as you pay, or pin it to one
    /// category. Left empty, the payment books under whatever the merchant's
    /// saved rule says, then the default chosen in the app.
    @Parameter(title: "Category")
    var category: ApplePayCategory?

    /// Which trigger this is, so the run log can say which one is doing the
    /// work when somebody has set up both. Not asked of the user — the shortcut
    /// sets it, and anything unrecognised is read by the server as a
    /// notification.
    @Parameter(title: "Source", default: "notification")
    var source: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amount) \(\.$currency) at \(\.$merchant)") {
            \.$card
            \.$notificationText
            \.$category
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        // A phone nobody has set up is the ordinary state of this intent for
        // everybody who installed the shortcut before opening the app. It must
        // not look like a failure: Shortcuts would draw an error over a lock
        // screen about something the user has not done yet.
        guard ApplePayConfigStore.isConfigured else {
            CWLog.shared.log("Apple Pay: intent fired before setup", category: "ApplePay")
            return .result()
        }

        var body: [String: Any] = [
            "trigger": normalizedTrigger(),
            // Stamped HERE, at capture — not when the payment is eventually
            // posted. A payment that spent an hour queued because the phone was
            // underground belongs to the moment of the tap, and the server's
            // duplicate key is a minute window around exactly this value.
            "occurred_at": ISO8601DateFormatter().string(from: Date()),
        ]
        if let amount, amount != 0 { body["amount"] = amount }
        if let text = trimmed(currency) { body["currency"] = text }
        if let text = trimmed(merchant) { body["merchant"] = text }
        if let text = trimmed(card) { body["card"] = text }
        if let text = trimmed(notificationText) { body["notification_text"] = text }
        if let category {
            body["type"] = category.typeId
            if let subtypeId = category.subtypeId { body["subtype"] = subtypeId }
        }

        let outcome = await ApplePayPoster.submit(body: body)
        await ApplePayPoster.notify(outcome: outcome,
                                    organizationName: ApplePayConfigStore.current()?.organizationName ?? "")
        return .result()
    }

    private func trimmed(_ value: String?) -> String? {
        guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    /// The server takes exactly three words here and reads anything else as a
    /// notification. Normalising on this side keeps a mistyped shortcut from
    /// producing a run log full of rows that cannot say where they came from.
    private func normalizedTrigger() -> String {
        switch trimmed(source)?.lowercased() {
        case "transaction": return "transaction"
        case "manual": return "manual"
        default: return "notification"
        }
    }
}

/// Puts the intent in front of people who have not gone looking for it — the
/// Shortcuts gallery, and Siri.
///
/// The phrases name the app because `applicationName` is what Siri will accept
/// around them, and both languages this shell speaks are offered: a Ukrainian
/// user saying the English phrase is not a thing to design for.
struct CapitalWizardAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogApplePayPaymentIntent(),
            phrases: [
                "Log a payment in \(.applicationName)",
                "Record a payment in \(.applicationName)",
                "Записати платіж у \(.applicationName)",
            ],
            shortTitle: "Log a payment",
            systemImageName: "creditcard"
        )
    }
}

#endif
