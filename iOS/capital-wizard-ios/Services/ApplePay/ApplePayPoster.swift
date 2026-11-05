//
//  ApplePayPoster.swift
//  capital-wizard-ios
//
//  Getting a captured payment to the server, and telling its owner what happened.
//

import Foundation
import Auth
import UserNotifications

#if !CODING_LAB

/// Posts queued Apple Pay payments to the `apple-pay` edge function.
///
/// THE SHAPE OF THIS IS DICTATED BY WHO IS WATCHING: nobody. A Shortcuts
/// automation fires on a Wallet notification, this runs for a few seconds on a
/// phone that is probably back in a pocket, and there is no screen on which to
/// fail. So every decision below leans the same way — put the payment down
/// durably first, treat a refusal as information rather than an error, and never
/// throw anything a caller would have to catch and report to a user who is not
/// there.
///
/// EVERY PAYMENT GOES THROUGH THE QUEUE, even when the phone is online. See
/// `ApplePayQueue` for the full argument; the short version is that the window
/// between "captured" and "durable" is the only one in which a payment can
/// vanish, and this makes the retry path and the happy path the same code.
///
/// IT CANNOT DOUBLE-BOOK. The server keys a payment on merchant, amount, card
/// and the minute it happened (`applePayExternalId`), so a retry of something
/// that already landed comes back `duplicate` — a normal outcome, acknowledged
/// and dropped like any other.
enum ApplePayPoster {

    /// How many queued payments one drain attempts. Small on purpose: this runs
    /// in the seconds an intent or a foreground transition is given, and a
    /// backlog is better worked through over several passes than abandoned
    /// halfway through one long one.
    private static let drainBatch = 10

    /// Per request. Generous enough for a shop's slow wifi and short enough that
    /// an intent is not killed mid-flight with the payment still unacknowledged.
    private static let requestTimeout: TimeInterval = 20

    /// Serialises drains. Two at once — an intent firing while the app is coming
    /// to the foreground — would post the same queued payments twice. The server
    /// would answer `duplicate` and no harm would be done, but it is wasted work
    /// and it makes the run log read as though every payment happened twice.
    private static let draining = DrainGate()

    private actor DrainGate {
        private var busy = false
        /// Answers whether the caller took the gate. A caller that did not must
        /// simply return — the drain already running will pick up its work.
        func take() -> Bool {
            if busy { return false }
            busy = true
            return true
        }
        func release() { busy = false }
    }

    /// What a single post came back with. Mirrors the edge function's own
    /// vocabulary plus the two answers only the client can give.
    enum Outcome {
        /// The server answered. The payment is settled either way and the queue
        /// entry is dropped — `duplicate`, `no_amount` and `unreadable` are all
        /// final answers, not failures to retry.
        case settled(outcome: String, merchant: String?, amount: Double?, currency: String?)
        /// Nothing reached the server, or it answered in a way that may well
        /// succeed later. The payment stays queued.
        case retry(reason: String)
        /// There is no session, or no configuration. The payment stays queued;
        /// signing in and opening the app is what clears it.
        case notReady(reason: String)
    }

    // MARK: - Capture

    /// Takes a payment from the intent, puts it down, and tries to send it.
    ///
    /// Returns what the user should be told, or nil when there is nothing worth
    /// saying. Never throws: the caller is an App Intent whose failure would be
    /// a dialog on a lock screen nobody asked for.
    @discardableResult
    static func submit(body: [String: Any]) async -> Outcome {
        do {
            _ = try ApplePayQueue.enqueue(body)
        } catch {
            // The one genuinely unrecoverable case: no app-group container, or a
            // full queue. There is nowhere to put the payment, so it is lost —
            // say so in the log, which is the only place anybody can find out.
            CWLog.shared.log("Apple Pay: could not queue payment", category: "ApplePay")
            return .retry(reason: "queue_unavailable")
        }
        return await drain()
    }

    // MARK: - Drain

    /// Posts what is queued. Answers with the outcome of the LAST payment it
    /// settled, which for the common case — one tap, one queued payment — is
    /// that payment's own answer and is what the notification reports.
    @discardableResult
    static func drain() async -> Outcome {
        guard await draining.take() else { return .retry(reason: "already_draining") }
        defer { Task { await draining.release() } }

        guard let config = ApplePayConfigStore.current() else {
            return .notReady(reason: "not_configured")
        }
        guard let endpoint = SupabaseConfig.functionUrl("apple-pay") else {
            return .notReady(reason: "no_endpoint")
        }

        // THE KEYCHAIN IS THE UNKNOWN HERE, and it is handled rather than
        // predicted. The Supabase SDK's `KeychainLocalStorage` chooses its own
        // accessibility class, and which one it is decides whether this read
        // works while the phone is locked — which is exactly when the intent
        // runs. Rather than assert an answer this code cannot verify, a failed
        // read is treated as "not ready": the payment stays queued and goes out
        // on the next unlock or foreground. That is correct whichever class the
        // SDK picked, and it degrades to a short delay rather than a lost
        // payment. The setup guide's "unlock your phone before paying" tip
        // exists for the same reason.
        let token: String
        do {
            token = try await session().accessToken
        } catch {
            CWLog.shared.log("Apple Pay: no session available, \(ApplePayQueue.depth()) payment(s) held", category: "ApplePay")
            return .notReady(reason: "no_session")
        }

        let entries: [ApplePayQueue.Entry]
        do { entries = try ApplePayQueue.peek(limit: drainBatch) }
        catch { return .retry(reason: "queue_unreadable") }
        guard !entries.isEmpty else { return .notReady(reason: "nothing_queued") }

        var last: Outcome = .retry(reason: "nothing_posted")
        for entry in entries {
            var body = entry.body
            // The space is stamped at DRAIN time, not at capture. A payment
            // captured before the user switched space should still land where
            // the phone is configured to log now — and a payment captured while
            // nothing was configured would otherwise be unsendable forever.
            body["organization_id"] = config.organizationId
            body["action"] = "log"

            let outcome = await post(body: body, to: endpoint, token: token)
            switch outcome {
            case .settled:
                try? ApplePayQueue.acknowledge(entry.id)
                last = outcome
            case .retry, .notReady:
                // Stop at the first payment that did not settle. The queue is
                // ordered oldest-first and the usual cause is the network being
                // gone; hammering the rest would spend the intent's seconds
                // failing nine more times.
                return outcome
            }
        }
        return last
    }

    // MARK: - One request

    private static func post(body: [String: Any], to endpoint: URL, token: String) async -> Outcome {
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else {
            // Unserialisable means this entry can never be sent. Settle it so it
            // leaves the queue rather than blocking everything behind it.
            return .settled(outcome: "failed", merchant: nil, amount: nil, currency: nil)
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = payload

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .retry(reason: "no_response") }

            // 401/403 is a session that is no longer good for this space. Held
            // rather than discarded: signing in again is what fixes it, and
            // throwing the payment away would punish the user for our expiry.
            if http.statusCode == 401 || http.statusCode == 403 {
                CWLog.shared.log("Apple Pay: server declined the session", category: "ApplePay")
                return .notReady(reason: "unauthorized")
            }
            // 5xx and 429 are the server's problem and are worth trying again.
            if http.statusCode >= 500 || http.statusCode == 429 {
                CWLog.shared.log("Apple Pay: server busy (\(http.statusCode))", category: "ApplePay")
                return .retry(reason: "server_\(http.statusCode)")
            }
            guard http.statusCode == 200,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let outcome = object["outcome"] as? String else {
                // A 4xx with a body we cannot read is a request this build will
                // never get right. Settling it keeps the queue moving; the run
                // log on the server is where it is chased.
                CWLog.shared.log("Apple Pay: request refused (\(http.statusCode))", category: "ApplePay")
                return .settled(outcome: "failed", merchant: nil, amount: nil, currency: nil)
            }

            CWLog.shared.log("Apple Pay: \(outcome)", category: "ApplePay")
            return .settled(outcome: outcome,
                            merchant: object["merchant"] as? String,
                            amount: object["amount"] as? Double,
                            currency: object["currency"] as? String)
        } catch {
            // Deliberately not logging the error — it can carry a URL and a host
            // and this log is copied into support messages. The operation and
            // the fact that it did not reach anybody is the whole story.
            CWLog.shared.log("Apple Pay: could not reach the server", category: "ApplePay")
            return .retry(reason: "network")
        }
    }

    /// A session, from a client configured exactly as `AuthService`'s is.
    ///
    /// Built here rather than reached for through `ServiceManager` because an
    /// App Intent can run before — or entirely without — the service locator
    /// having been populated: the system may launch this app in the background
    /// purely to answer the intent. Both clients read the same Keychain storage,
    /// so this is the same session the app itself holds, refresh included.
    private static func session() async throws -> Session {
        let client = AuthClient(configuration: .init(
            url: SupabaseConfig.authUrl,
            headers: ["apikey": SupabaseConfig.publishableKey],
            flowType: .pkce,
            localStorage: KeychainLocalStorage()
        ))
        return try await client.session
    }

    // MARK: - Telling the user

    /// Posts a local notification about a settled payment, if the user asked for
    /// one and the system will carry it.
    ///
    /// THE FIRST LOCAL NOTIFICATION IN THIS APP. Everything else here is remote
    /// push (`PushService`), which owns the `UNUserNotificationCenter` delegate —
    /// this only ever ADDS a request and never touches that delegate, so a tap
    /// on one of these is routed by the same code that routes a push.
    ///
    /// AUTHORIZATION IS READ, NEVER REQUESTED. Asking from here would put a
    /// system prompt on a locked phone, seconds after a tap at a till, with
    /// nobody expecting it. If permission has not been granted the payment is
    /// still recorded — it simply lands silently, which is what the settings
    /// screen warns about.
    static func notify(outcome: Outcome, organizationName: String) async {
        guard case let .settled(result, merchant, amount, currency) = outcome else { return }
        guard ApplePayConfigStore.current()?.notify == true else { return }

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
                || settings.authorizationStatus == .ephemeral else { return }

        guard let text = notificationText(result: result, merchant: merchant, amount: amount, currency: currency) else { return }

        let content = UNMutableNotificationContent()
        content.title = text.title
        content.body = text.body.isEmpty ? organizationName : text.body
        // Silent: the payment already made the phone buzz once, when Wallet
        // showed the notification this was read from. A second sound for the
        // same tap is what makes somebody turn the feature off.
        content.sound = nil

        let request = UNNotificationRequest(identifier: "cw.applePay.\(UUID().uuidString)",
                                            content: content,
                                            trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// What a settled payment says on the lock screen. Localised through the app
    /// bundle so it reads in the user's own language, like every other string in
    /// this shell.
    private static func notificationText(result: String,
                                         merchant: String?,
                                         amount: Double?,
                                         currency: String?) -> (title: String, body: String)? {
        let name = merchant?.trimmingCharacters(in: .whitespacesAndNewlines)
        let where_ = (name?.isEmpty == false) ? name! : L("apple_pay.unknown_merchant")

        switch result {
        case "logged":
            let money = formattedAmount(amount, currency: currency)
            let title = money.isEmpty ? where_ : "\(where_) · \(money)"
            return (title: title, body: L("apple_pay.logged"))
        case "duplicate":
            // Nothing happened and nothing is wrong. Silent — telling somebody
            // their payment was already recorded is noise about a success.
            return nil
        case "no_amount", "unreadable":
            return (title: L("apple_pay.not_logged.title"),
                    body: L("apple_pay.not_logged.body"))
        default:
            return (title: L("apple_pay.failed.title"),
                    body: L("apple_pay.failed.body"))
        }
    }

    private static func formattedAmount(_ amount: Double?, currency: String?) -> String {
        guard let amount else { return "" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        // A currency the device's locale cannot format falls back to the plain
        // number plus the code, rather than to a figure with the wrong symbol
        // in front of it.
        if let currency, let text = formatter.string(from: NSNumber(value: amount)) {
            _ = currency
            return text
        }
        return String(format: "%.2f", amount)
    }
}

#endif
