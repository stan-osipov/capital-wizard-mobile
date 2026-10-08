import UIKit
import StoreKit
import Auth

/// Mirrors Android StoreService. Only server verification can credit the wallet.
@MainActor final class StoreService {
    static let shared = StoreService()
    static let productIds = ["cw_credit_10", "cw_credit_20", "cw_credit_50", "cw_credit_100",
                             "cw_monthly_10", "cw_monthly_25", "cw_monthly_50"]
    private static var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
    static var available: Bool {
        StoreBillingPolicy.isAvailable(isDebugBuild: isDebugBuild,
            receiptName: Bundle.main.appStoreReceiptURL?.lastPathComponent)
    }
    private var busy = false
    private var updates: Task<Void, Never>?
    private var auth: AuthService? { ServiceManager.shared.getService() }
    private var currentUserId: String? { auth?.storeUserId }
    struct Reply { let handler: String; let payload: [String: Any] }

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
        guard let auth, currentUserId != nil else { throw StoreFailure(code: "session_unavailable") }
        guard currentUserId == userId else { throw StoreFailure(code: "account_mismatch") }
        let session: Auth.Session
        do { session = try await auth.client.session }
        catch { throw StoreFailure(code: "session_unavailable") }
        guard session.user.id.uuidString.lowercased() == userId, currentUserId == userId else { throw StoreFailure(code: "account_mismatch") }
        var request = URLRequest(url: URL(string: "https://qzdgdyqsoldkarcshkbi.supabase.co/functions/v1/store-verify")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body.merging(["store":"APP_STORE"]) { _, new in new })
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw StoreFailure(code: "server_unavailable") }
        guard response.statusCode == 200 else { throw StoreFailure.response(status: response.statusCode) }
        guard currentUserId == userId else { throw StoreFailure(code: "account_mismatch") }
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StoreFailure(code: "server_unavailable")
        }
        return result
    }

    private func submit(_ result: VerificationResult<StoreKit.Transaction>) async throws -> String? {
        guard case .verified(let transaction) = result else { throw StoreFailure(code: "store_unavailable") }
        guard transaction.environment == .sandbox else { throw StoreFailure(code: "sandbox_required") }
        guard let userId = currentUserId else { throw StoreFailure(code: "session_unavailable") }
        guard transaction.appAccountToken?.uuidString.lowercased() == userId else { throw StoreFailure(code: "account_mismatch") }
        guard Self.productIds.contains(transaction.productID) else { throw StoreFailure(code: "product_unavailable") }
        let response = try await call(["action":"verify", "signedTransaction":result.jwsRepresentation], userId:userId)
        guard response["accepted"] as? Bool == true else { return nil }
        await transaction.finish()
        return String(transaction.id)
    }

    func handle(_ request: [String: Any]) async -> Reply? {
        let event = request["eventName"] as? String ?? ""
        if event == "store-manage" {
            guard Self.available else { return nil }
            if currentUserId != nil, let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                await UIApplication.shared.open(url)
            }
            return nil
        }
        guard let requestId = request["requestId"] as? String, let userId = request["userId"] as? String else { return nil }
        let handler = event == "store-products" ? "storeProducts" : event == "store-purchase" ? "storePurchase" : "storeRestore"
        func reply(_ status: String, _ extra: [String: Any] = [:]) -> Reply {
            if let code = extra["errorCode"] as? String {
                CWLog.shared.log("\(event): \(status) (\(code))", category: "Store")
            }
            return Reply(handler: handler, payload: ["requestId":requestId,"userId":userId,"status":status].merging(extra) { _, new in new })
        }
        guard Self.available else { return reply("error", ["errorCode":"payments_unavailable"]) }
        guard !busy else { return reply("error", ["errorCode":"store_busy"]) }
        guard currentUserId != nil else { return reply("error", ["errorCode":"session_unavailable"]) }
        guard currentUserId == userId, let uuid = UUID(uuidString:userId) else {
            return reply("error", ["errorCode":"account_mismatch"])
        }
        busy = true
        defer { busy = false }
        var purchaseAttempted = false
        var failureCode = "store_unavailable"
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
                guard currentUserId == userId else { return reply("error", ["errorCode":"account_mismatch"]) }
                return reply(pending ? "pending" : "ok")
            }
            let products = try await Product.products(for:Self.productIds)
            guard currentUserId == userId else { return reply("error", ["errorCode":"account_mismatch"]) }
            if event == "store-products" {
                return reply("ok",["products":products.map { ["id":$0.id,"title":$0.displayName,"price":$0.displayPrice] }])
            }
            guard event == "store-purchase", let id = request["productId"] as? String,
                  let product = products.first(where: { $0.id == id }) else { return reply("error", ["errorCode":"product_unavailable"]) }
            if id.hasPrefix("cw_monthly_") {
                for await result in StoreKit.Transaction.currentEntitlements {
                    if case .verified(let transaction) = result, transaction.productID.hasPrefix("cw_monthly_") {
                        return reply("error", ["errorCode":"subscription_active"]) // No prorated subscription replacements.
                    }
                }
            }
            failureCode = "server_unavailable"
            let prepared = try await call(["action":"prepare"],userId:userId)
            guard currentUserId == userId else { return reply("error", ["errorCode":"account_mismatch"]) }
            // TestFlight purchases use sandbox; recheck the system receipt.
            // AppTransaction describes the app download, not this IAP: an absent
            // or unverified download record must not block StoreKit's own sheet.
            // submit() and the server still verify the actual purchase signature,
            // sandbox environment, product and account before granting credit.
            try StoreBillingPolicy.validateCheckout(isDebugBuild: Self.isDebugBuild,
                receiptName: Bundle.main.appStoreReceiptURL?.lastPathComponent,
                accountToken: prepared["accountToken"] as? String, userId: userId)
            CWLog.shared.log("store-purchase: opening checkout", category: "Store")
            failureCode = "store_unavailable"
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
            let code = (error as? StoreFailure)?.code ?? failureCode
            return reply(purchaseAttempted ? "pending" : "error", ["errorCode":code])
        }
    }
}
