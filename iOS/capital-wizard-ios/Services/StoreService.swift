import UIKit
import StoreKit

/// Mirrors Android StoreService. Only server verification can credit the wallet.
@MainActor final class StoreService {
    static let shared = StoreService()
    static let productIds = ["cw_credit_10", "cw_credit_20", "cw_credit_50", "cw_credit_100",
                             "cw_monthly_10", "cw_monthly_25", "cw_monthly_50"]
    static var available: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
    private var busy = false
    private var updates: Task<Void, Never>?
    private var auth: AuthService? { ServiceManager.shared.getService() }
    private var currentUserId: String? { auth?.storeUserId }
    struct Reply { let handler: String; let payload: [String: Any] }
    private enum Failure: Error { case unavailable }

    private init() {
        guard Self.available else { return }
        updates = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard let self, !Task.isCancelled else { return }
                _ = try? await self.submit(result)
            }
        }
    }

    /// Retry unfinished transactions on startup. StoreKit redelivers after a crash
    /// because finish() happens only after the server has durably accepted them.
    @discardableResult func reconcile() async -> Bool {
        guard Self.available, let userId = currentUserId else { return false }
        var complete = true
        for await result in StoreKit.Transaction.unfinished {
            if case .verified(let transaction) = result,
               transaction.appAccountToken?.uuidString.lowercased() != userId { continue }
            do { if try await submit(result) == nil { complete = false } }
            catch { complete = false }
        }
        return complete
    }

    private func call(_ body: [String: Any], userId: String) async throws -> [String: Any] {
        guard let auth, currentUserId == userId else { throw Failure.unavailable }
        let session = try await auth.client.session
        guard session.user.id.uuidString.lowercased() == userId, currentUserId == userId else { throw Failure.unavailable }
        var request = URLRequest(url: URL(string: "https://qzdgdyqsoldkarcshkbi.supabase.co/functions/v1/store-verify")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body.merging(["store":"APP_STORE"]) { _, new in new })
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, currentUserId == userId,
              let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.unavailable }
        return result
    }

    private func submit(_ result: VerificationResult<StoreKit.Transaction>) async throws -> String? {
        guard case .verified(let transaction) = result,
              let userId = currentUserId, transaction.appAccountToken?.uuidString.lowercased() == userId,
              Self.productIds.contains(transaction.productID) else { throw Failure.unavailable }
        let response = try await call(["action":"verify", "signedTransaction":result.jwsRepresentation], userId:userId)
        guard response["accepted"] as? Bool == true else { return nil }
        await transaction.finish()
        return String(transaction.id)
    }

    func handle(_ request: [String: Any]) async -> Reply? {
        let event = request["eventName"] as? String ?? ""
        guard Self.available else { return nil }
        if event == "store-manage" {
            if currentUserId != nil, let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                await UIApplication.shared.open(url)
            }
            return nil
        }
        guard let requestId = request["requestId"] as? String, let userId = request["userId"] as? String else { return nil }
        let handler = event == "store-products" ? "storeProducts" : event == "store-purchase" ? "storePurchase" : "storeRestore"
        func reply(_ status: String, _ extra: [String: Any] = [:]) -> Reply {
            Reply(handler: handler, payload: ["requestId":requestId,"userId":userId,"status":status].merging(extra) { _, new in new })
        }
        guard !busy, currentUserId == userId, let uuid = UUID(uuidString:userId) else { return reply("error") }
        busy = true
        defer { busy = false }
        var purchaseAttempted = false
        do {
            if event == "store-restore" {
                try await AppStore.sync()
                var pending = !(await reconcile())
                for await result in StoreKit.Transaction.currentEntitlements {
                    if case .verified(let transaction) = result,
                       transaction.appAccountToken?.uuidString.lowercased() == userId {
                        if try await submit(result) == nil { pending = true }
                    }
                }
                return reply(currentUserId == userId ? (pending ? "pending" : "ok") : "error")
            }
            let products = try await Product.products(for:Self.productIds)
            guard currentUserId == userId else { return reply("error") }
            if event == "store-products" {
                return reply("ok",["products":products.map { ["id":$0.id,"title":$0.displayName,"price":$0.displayPrice] }])
            }
            guard event == "store-purchase", let id = request["productId"] as? String,
                  let product = products.first(where: { $0.id == id }) else { return reply("error") }
            if id.hasPrefix("cw_monthly_") {
                for await result in StoreKit.Transaction.currentEntitlements {
                    if case .verified(let transaction) = result, transaction.productID.hasPrefix("cw_monthly_") {
                        return reply("error") // No prorated subscription replacements.
                    }
                }
            }
            let prepared = try await call(["action":"prepare"],userId:userId)
            guard prepared["accountToken"] as? String == userId, currentUserId == userId else { return reply("error") }
            purchaseAttempted = true
            switch try await product.purchase(options:[.appAccountToken(uuid)]) {
            case .userCancelled: return reply("cancelled")
            case .pending: return reply("pending")
            case .success(let result):
                guard let transactionId = try await submit(result) else { return reply("pending") }
                return reply("ok",["transactionId":transactionId])
            @unknown default: return reply("pending")
            }
        } catch {
            // A transport error may follow a charge. Preserve the unfinished
            // transaction and never invite a second consumable purchase.
            return reply(purchaseAttempted ? "pending" : "error")
        }
    }
}
