//
//  ApplePayConfigStore.swift
//  capital-wizard-ios
//
//  What the web app told this phone about where Apple Pay payments go.
//

import Foundation

// Capital Wizard only. The Coding Lab target syncs `capital-wizard-ios`
// but NOT `SharedImages`, so `SharedImageInbox` — which the app-group id
// below is read from — does not exist in that build; and a product with no
// ledger has nothing to log a payment into anyway. Guarding here rather
// than carving target membership out of the project file keeps the
// exclusion visible in the source that is excluded.
#if !CODING_LAB


/// One subtype as the space defines it.
struct ApplePaySubtype: Codable, Hashable {
    let id: String
    let name: String
}

/// One transaction type as the space defines it, with its subtypes.
///
/// The taxonomy is not a table: it lives in `organizations.settings.transactionTypes`,
/// which is why the whole list has to be carried here rather than looked up by
/// id. See `spaceTypes()` in the `apple-pay` edge function — it does the same
/// reduction on the server for the same reason.
struct ApplePayTransactionType: Codable, Hashable {
    let id: String
    let name: String
    let subtypes: [ApplePaySubtype]
}

/// Where this phone logs Apple Pay payments, and whether it says so.
struct ApplePayConfig: Codable {
    let organizationId: String
    /// The space's own name, so a notification can say where the money went
    /// without a round trip to ask.
    let organizationName: String
    let notify: Bool
    let types: [ApplePayTransactionType]
    /// When the web app last told us this. Not used to expire anything — it is
    /// here so a support log can say how stale the category list is.
    let receivedAt: Date
}

/// The durable answer to "where do payments go", written by the bridge and read
/// by the App Intent.
///
/// WHY THIS EXISTS AT ALL. The intent runs with nobody watching — on the lock
/// screen, seconds after a tap at a till — so it cannot ask which space the
/// payment belongs to, and it cannot ask the web app either: the web app is
/// almost certainly not running, and on a cold intent launch there is no WebView
/// and never will be one. So the setup screen TELLS the shell once, over the
/// bridge, and the shell keeps the answer. `applePayNative.ts` is the other half
/// of this contract.
///
/// WHY THE APP GROUP SUITE RATHER THAN `UserDefaults.standard`. Today the intent
/// is hosted by the app target, so it runs in the app's own process and
/// `standard` would be readable. Two reasons not to lean on that: the config is
/// read in the same breath as the queue it belongs to (`ApplePayQueue`, same
/// container), so keeping them apart would be the odd choice; and if the intent
/// is ever moved into an extension of its own — which is the normal way this
/// grows — `standard` becomes a different, empty database and the feature
/// silently stops working with no error to show for it. The group costs nothing
/// and removes that trap. It is the group that already exists in the
/// entitlements; nothing here provisions anything new.
enum ApplePayConfigStore {

    /// Reusing the share handoff's group ON PURPOSE. A second app group would
    /// need a trip to the Apple Developer portal and a provisioning-profile
    /// regeneration for every build machine, and it would buy nothing: both
    /// payloads are this user's own data, both are app-and-extension only, and
    /// the group name saying "shared-images" is already a documented lie (see
    /// `SharedImageInbox`, which carries statements under the same name because
    /// the id cannot be renamed without breaking the handoff mid-upgrade).
    static let group = SharedImageInbox.group

    private static let configKey = "cw.applePay.config"

    /// Caps mirroring `configureApplePay()` in `applePayNative.ts`, applied
    /// AGAIN here. The web side caps on the way out to keep the payload small;
    /// this caps on the way in because the payload crossed `window`, where any
    /// script running in our page could have written it. A space with four
    /// hundred types would otherwise become four hundred rows iOS has to draw
    /// in a picker and we have to keep on disk.
    private static let maxTypes = 60
    private static let maxSubtypes = 40
    /// Long enough for the longest real category name, short enough that a
    /// hostile page cannot grow the plist without bound.
    private static let maxNameLength = 120

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: group)
    }

    /// What `apple-pay-configure` asked for.
    enum Outcome {
        /// Logging is on, for this space.
        case configured(organizationName: String, typeCount: Int)
        /// `organizationId: null` — the user turned the feature off or left the
        /// space. The shortcut on the phone still exists and still fires; this
        /// is what makes it stop writing payments.
        case cleared
        /// The payload did not make sense. Nothing was changed — deliberately
        /// not "cleared", because a malformed message must not be able to switch
        /// the feature off behind the user's back.
        case ignored
    }

    static func current() -> ApplePayConfig? {
        guard let data = defaults?.data(forKey: configKey) else { return nil }
        return try? JSONDecoder().decode(ApplePayConfig.self, from: data)
    }

    /// Is this phone configured to log payments right now?
    static var isConfigured: Bool { current() != nil }

    /// Applies a bridge payload. See `ApplePayConfigure` in `applePayNative.ts`
    /// for the shape; this must stay a translation of it.
    @discardableResult
    static func apply(_ dict: [String: Any]) -> Outcome {
        // `organizationId: null` arrives as NSNull through WKScriptMessage, and
        // as a missing key if an older web build posted a bare disable. Both
        // mean the same thing and both are a legitimate instruction, which is
        // why they are separated from `ignored` below.
        let rawId = dict["organizationId"]
        if rawId == nil || rawId is NSNull {
            clear()
            return .cleared
        }

        // A space id is a UUID on the server (`UUID` in the edge function
        // refuses anything else), so anything else here is either a bug in the
        // web app or a script that is not the web app. Either way it is not
        // worth keeping, and storing it would mean every payment this phone
        // ever logs is refused with nobody watching.
        guard let organizationId = (rawId as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              UUID(uuidString: organizationId) != nil else {
            return .ignored
        }

        let organizationName = clamp(dict["organizationName"] as? String) ?? ""
        // Absent reads as ON. A build of the web app that predates the flag sent
        // no `notify`, and the feature was announced as "the app tells you when
        // a payment is logged" — silently going quiet would read as the whole
        // automation having broken.
        let notify = dict["notify"] as? Bool ?? true
        let types = parseTypes(dict["types"])

        let config = ApplePayConfig(organizationId: organizationId,
                                    organizationName: organizationName,
                                    notify: notify,
                                    types: types,
                                    receivedAt: Date())
        guard let data = try? JSONEncoder().encode(config) else { return .ignored }
        defaults?.set(data, forKey: configKey)
        return .configured(organizationName: organizationName, typeCount: types.count)
    }

    static func clear() {
        defaults?.removeObject(forKey: configKey)
    }

    /// The category list the intent's picker offers, flattened into the
    /// type/subtype pairs a payment can actually book under.
    ///
    /// A bare type is offered as well as each of its subtypes, because a space
    /// that uses subtypes for some types and not others is the normal case and
    /// forcing a subtype choice would make those types unpickable.
    static func categories() -> [(id: String, label: String, typeId: String, subtypeId: String?)] {
        guard let config = current() else { return [] }
        var result: [(id: String, label: String, typeId: String, subtypeId: String?)] = []
        for type in config.types {
            result.append((id: type.id, label: type.name, typeId: type.id, subtypeId: nil))
            for subtype in type.subtypes {
                result.append((id: "\(type.id)/\(subtype.id)",
                               // An em-space-separated pair rather than a nested
                               // picker: Shortcuts draws a flat list of values
                               // and "Groceries" twice over with no parent shown
                               // is unpickable.
                               label: "\(type.name) · \(subtype.name)",
                               typeId: type.id,
                               subtypeId: subtype.id))
            }
        }
        return result
    }

    // MARK: - Payload reading

    private static func clamp(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxNameLength))
    }

    private static func parseTypes(_ raw: Any?) -> [ApplePayTransactionType] {
        guard let array = raw as? [[String: Any]] else { return [] }
        return array.prefix(maxTypes).compactMap { entry in
            // An unnamed type is dropped rather than shown as its own id: a
            // picker row reading `b7f1e2c0-…` is worse than one row fewer.
            guard let id = clamp(entry["id"] as? String), let name = clamp(entry["name"] as? String) else { return nil }
            let subtypes = (entry["subtypes"] as? [[String: Any]] ?? []).prefix(maxSubtypes).compactMap { sub -> ApplePaySubtype? in
                guard let subId = clamp(sub["id"] as? String), let subName = clamp(sub["name"] as? String) else { return nil }
                return ApplePaySubtype(id: subId, name: subName)
            }
            return ApplePayTransactionType(id: id, name: name, subtypes: Array(subtypes))
        }
    }
}

#endif
