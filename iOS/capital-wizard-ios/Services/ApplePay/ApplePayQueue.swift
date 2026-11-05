//
//  ApplePayQueue.swift
//  capital-wizard-ios
//
//  Payments that have been captured but not yet accepted by the server.
//

import Foundation

// Capital Wizard only. The Coding Lab target syncs `capital-wizard-ios`
// but NOT `SharedImages`, so `SharedImageInbox` — which the app-group id
// below is read from — does not exist in that build; and a product with no
// ledger has nothing to log a payment into anyway. Guarding here rather
// than carving target membership out of the project file keeps the
// exclusion visible in the source that is excluded.
#if !CODING_LAB


/// A durable, on-disk spool of Apple Pay payments waiting to be posted.
///
/// Deliberately the same shape as `SharedImageInbox`: one JSON file per item in
/// the shared app-group container, named by a UUID, written atomically, read
/// oldest-first, acknowledged by id, and garbage-collected after seven days.
/// Read that file alongside this one — if the two ever stop looking like
/// translations of each other, this one is the one that drifted.
///
/// WHY A QUEUE AND NOT JUST A RETRY. The thing that captures a payment is a
/// Shortcuts automation firing on a Wallet notification. It gets a few seconds,
/// it may well be the only notice of that payment anybody will ever receive, and
/// when it fails nobody finds out — there is no screen, no spinner and no user.
/// The three things that routinely go wrong at a till are all transient: the
/// phone is on a shop's captive wifi, or on no network at all underground, or
/// the process is suspended mid-request. Every one of those loses the payment
/// for good without somewhere to put it down.
///
/// EVERY PAYMENT IS WRITTEN HERE FIRST, even when the phone is online and the
/// post is about to succeed. That is the point: the window between "captured"
/// and "durable" is the only window in which a payment can vanish, and writing
/// first makes it as close to zero as a file write. The cost is one small write
/// per payment, which is nothing next to losing one. It also makes the retry
/// path and the happy path the same code, so the retry path cannot rot
/// unexercised — it runs on every single payment.
///
/// A RETRY CANNOT DOUBLE-BOOK, which is what makes the above safe. The server
/// keys a payment on `applePayExternalId` — merchant, amount, card and the
/// occurrence time ROUNDED TO THE MINUTE — precisely so that two reports of one
/// tap collide. That was built for the two iOS triggers both firing on one
/// purchase; it covers our retries for free. A second post of the same payment
/// comes back `duplicate`, which is a normal outcome and not an error.
enum ApplePayQueue {

    /// The group that already exists in the entitlements. See
    /// `ApplePayConfigStore.group` for why nothing new is provisioned.
    static let group = ApplePayConfigStore.group

    private static let folderName = "apple-pay-queue"

    /// Seven days, matching `SharedImageInbox.pending()`. A payment nobody has
    /// managed to post inside a week is one whose notification the user has long
    /// since forgotten, and keeping it forever turns a transient outage into a
    /// surprise flood of month-old transactions the next time the app opens.
    private static let maxAge: TimeInterval = 7 * 24 * 60 * 60

    /// A ceiling, so a server that refuses everything for a fortnight cannot
    /// fill the container. Two hundred is far more Apple Pay taps than anybody
    /// makes in a week, so hitting it means something is broken rather than busy
    /// — and in that case the OLDEST entries are the ones worth keeping, because
    /// they are the ones closest to being garbage-collected unseen.
    private static let maxPending = 200

    enum Failure: Error {
        /// No app-group container. Either the entitlement is missing from this
        /// build or the device has not been unlocked since boot.
        case unavailable
        case full
        case invalid
    }

    /// One queued payment: the id that acknowledges it, and the body to post.
    struct Entry {
        let id: String
        /// Exactly the JSON the `apple-pay` function's `log` action expects —
        /// stored verbatim rather than re-derived at drain time, so a payment
        /// captured by today's build still posts correctly after an app update
        /// changes how capture works.
        let body: [String: Any]
    }

    private static func directory() throws -> URL {
        guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            throw Failure.unavailable
        }
        let folder = root.appendingPathComponent(folderName, isDirectory: true)
        // `completeUntilFirstUserAuthentication` is the whole reason this works
        // on a locked phone: the intent's most important moment is three seconds
        // after a tap at a till, with the screen off and the phone back in a
        // pocket. `complete` would make the write fail exactly then. This is the
        // same class `SharedImageInbox` uses, for the same reason.
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var protected = folder
        var values = URLResourceValues()
        // A payment waiting to be posted is in-flight state, not user data. It
        // must not be restored onto a different device and posted a second time
        // under a session that may belong to somebody else.
        values.isExcludedFromBackup = true
        try protected.setResourceValues(values)
        return folder
    }

    /// Queued files, oldest first, with anything past `maxAge` swept on the way
    /// through. The sweep lives here rather than in a timer because this is the
    /// only code that ever looks at the folder, so it is the only place that can
    /// be relied on to run.
    static func pending() throws -> [URL] {
        let files = try FileManager.default.contentsOfDirectory(at: try directory(),
                                                                includingPropertiesForKeys: [.creationDateKey])
        let cutoff = Date().addingTimeInterval(-maxAge)
        return files.filter { url in
            guard url.pathExtension == "json" else { return false }
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            if created < cutoff {
                try? FileManager.default.removeItem(at: url)
                return false
            }
            return true
        }.sorted { a, b in
            ((try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast)
                < ((try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast)
        }
    }

    /// Puts a payment down durably. Returns the id that will acknowledge it.
    ///
    /// `body` is the server's `log` payload, already assembled — including
    /// `occurred_at`, which MUST be stamped at capture and not at drain. A
    /// payment that spent two hours in the queue because the phone was in the
    /// Underground belongs to the moment of the tap; booking it at the moment
    /// the train surfaced would put it on the wrong day often enough to matter,
    /// and would also move it out of the minute window the server's duplicate
    /// key depends on.
    @discardableResult
    static func enqueue(_ body: [String: Any]) throws -> String {
        guard JSONSerialization.isValidJSONObject(body) else { throw Failure.invalid }
        guard try pending().count < maxPending else { throw Failure.full }
        let id = UUID().uuidString.lowercased()
        let data = try JSONSerialization.data(withJSONObject: ["id": id, "body": body])
        try data.write(to: try directory().appendingPathComponent("\(id).json"),
                       options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return id
    }

    /// The next `limit` payments to post, oldest first.
    ///
    /// A file that will not parse is deleted rather than returned or left: it
    /// can never succeed, and leaving it would wedge the drain at the head of
    /// the queue forever, which is the worst of the available outcomes because
    /// every payment behind it is fine.
    static func peek(limit: Int) throws -> [Entry] {
        var entries: [Entry] = []
        for url in try pending() {
            if entries.count >= limit { break }
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = object["id"] as? String, UUID(uuidString: id) != nil,
                  let body = object["body"] as? [String: Any] else {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            entries.append(Entry(id: id, body: body))
        }
        return entries
    }

    /// Drops a payment the server has answered. The id is validated as a UUID
    /// before it is used to build a path — same guard, same reason, as
    /// `SharedImageInbox.acknowledge`.
    static func acknowledge(_ id: String) throws {
        guard UUID(uuidString: id) != nil else { return }
        let file = try directory().appendingPathComponent("\(id.lowercased()).json")
        if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
    }

    /// How many payments are waiting. Used only for logging a count.
    static func depth() -> Int {
        (try? pending().count) ?? 0
    }
}

#endif
