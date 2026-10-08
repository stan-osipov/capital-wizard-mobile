package com.capitalwizard.android.services

import android.app.Activity
import android.content.Intent
import android.net.Uri
import com.android.billingclient.api.*
import com.capitalwizard.android.BuildConfig
import com.capitalwizard.android.utils.ServiceManager
import kotlinx.coroutines.*
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** Mirrors iOS StoreService. Only server verification can credit the wallet. */
object StoreService {
    val productIds = listOf("cw_credit_10", "cw_credit_20", "cw_credit_50", "cw_credit_100",
        "cw_monthly_10", "cw_monthly_25", "cw_monthly_50")
    // Unlike TestFlight, Play test tracks do not guarantee sandbox payments:
    // only license testers get test cards. Keep Android release billing off
    // until its separate Play setup and device verification are complete.
    val available: Boolean get() = BuildConfig.DEBUG && com.capitalwizard.android.utils.AppProduct.supportsStoreBilling
    private var busy = false
    private var billing: BillingClient? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val auth: AuthService? get() = ServiceManager.getService()
    private val currentUserId: String? get() = auth?.storeUserId
    data class Reply(val handler: String, val payload: JSONObject)
    private data class Pending(val userId: String, val productId: String, val result: CompletableDeferred<JSONObject>)
    private var pending: Pending? = null

    private suspend fun call(body: JSONObject, userId: String): JSONObject {
        check(currentUserId == userId)
        val token = auth?.auth?.currentSessionOrNull()?.accessToken ?: error("signed_out")
        val result = withContext(Dispatchers.IO) {
            val connection = URL("https://qzdgdyqsoldkarcshkbi.supabase.co/functions/v1/store-verify").openConnection() as HttpURLConnection
            try {
                connection.requestMethod = "POST"
                connection.connectTimeout = 25000
                connection.readTimeout = 25000
                connection.instanceFollowRedirects = false
                connection.setRequestProperty("Authorization", "Bearer $token")
                connection.setRequestProperty("Content-Type", "application/json")
                connection.doOutput = true
                connection.outputStream.use { it.write(body.put("store", "PLAY_STORE").toString().toByteArray(Charsets.UTF_8)) }
                check(connection.responseCode == 200)
                JSONObject(connection.inputStream.bufferedReader().use { it.readText() })
            } finally { connection.disconnect() }
        }
        check(currentUserId == userId)
        return result
    }

    private suspend fun connect(activity: Activity): BillingClient {
        val client = billing ?: BillingClient.newBuilder(activity.applicationContext)
            .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
            .enableAutoServiceReconnection()
            .setListener { result, purchases ->
                scope.launch {
                    val waiting = pending
                    if (result.responseCode == BillingClient.BillingResponseCode.USER_CANCELED) {
                        waiting?.result?.complete(JSONObject().put("status", "cancelled"))
                    } else if (result.responseCode != BillingClient.BillingResponseCode.OK) {
                        waiting?.result?.complete(JSONObject().put("status", "pending"))
                    } else {
                        for (purchase in purchases.orEmpty()) {
                            val userId = currentUserId ?: continue
                            val response = try { submit(purchase, userId) } catch (_: Exception) { JSONObject().put("status", "pending") }
                            if (waiting?.userId == userId && waiting.productId in purchase.products) waiting.result.complete(response)
                        }
                    }
                }
            }.build().also { billing = it }
        if (!client.isReady) withTimeout(10000) {
            suspendCancellableCoroutine<Unit> { continuation ->
                client.startConnection(object : BillingClientStateListener {
                    override fun onBillingSetupFinished(result: BillingResult) {
                        if (!continuation.isActive) return
                        if (result.responseCode == BillingClient.BillingResponseCode.OK) continuation.resume(Unit)
                        else continuation.resumeWithException(IllegalStateException("billing_unavailable"))
                    }
                    override fun onBillingServiceDisconnected() { /* Auto-reconnect on the next request. */ }
                })
            }
        }
        return client
    }

    private suspend fun owned(client: BillingClient, type: String): List<Purchase> {
        val result = client.queryPurchasesAsync(QueryPurchasesParams.newBuilder().setProductType(type).build())
        check(result.billingResult.responseCode == BillingClient.BillingResponseCode.OK)
        return result.purchasesList
    }

    private suspend fun products(client: BillingClient, type: String): List<ProductDetails> =
        withTimeout(10000) {
            suspendCancellableCoroutine { continuation ->
                val ids = productIds.filter { it.startsWith("cw_monthly_") == (type == BillingClient.ProductType.SUBS) }
                val params = QueryProductDetailsParams.newBuilder().setProductList(ids.map {
                    QueryProductDetailsParams.Product.newBuilder().setProductId(it).setProductType(type).build()
                }).build()
                client.queryProductDetailsAsync(params) { result, details ->
                    if (continuation.isActive) {
                        if (result.responseCode == BillingClient.BillingResponseCode.OK) continuation.resume(details.productDetailsList)
                        else continuation.resumeWithException(IllegalStateException("products_unavailable"))
                    }
                }
            }
        }

    private fun monthlyOffer(product: ProductDetails) = product.subscriptionOfferDetails?.firstOrNull {
        it.basePlanId == "monthly" && it.offerId == null && it.pricingPhases.pricingPhaseList.size == 1 &&
            it.pricingPhases.pricingPhaseList[0].billingPeriod == "P1M" && it.pricingPhases.pricingPhaseList[0].priceAmountMicros > 0
    }
    private fun oneTimeOffer(product: ProductDetails) = product.oneTimePurchaseOfferDetailsList?.firstOrNull {
        it.offerId == null && it.priceAmountMicros > 0 && it.rentalDetails == null && it.preorderDetails == null
    }

    private suspend fun submit(purchase: Purchase, userId: String): JSONObject {
        if (purchase.purchaseState != Purchase.PurchaseState.PURCHASED) return JSONObject().put("status", "pending")
        check(purchase.products.size == 1 && purchase.products[0] in productIds)
        val response = call(JSONObject().put("action", "verify").put("purchaseToken", purchase.purchaseToken)
            .put("monthly", purchase.products[0].startsWith("cw_monthly_")), userId)
        // Server consumes or acknowledges only AFTER its atomic ledger write.
        return if (response.optBoolean("accepted")) JSONObject().put("status", "ok").put("transactionId", response.getString("transactionId"))
            else JSONObject().put("status", "pending")
    }

    /** Retry unconsumed purchases on startup. Paid pending transactions are also
     * delivered to the listener; renewals/refunds arrive independently via RTDN. */
    suspend fun reconcile(activity: Activity) {
        if (!available || busy) return
        val userId = currentUserId ?: return
        try {
            val client = connect(activity)
            for (type in listOf(BillingClient.ProductType.INAPP, BillingClient.ProductType.SUBS)) {
                for (purchase in owned(client, type)) {
                    if (currentUserId != userId) return
                    try { submit(purchase, userId) } catch (_: Exception) { /* Retry next launch/restore. */ }
                }
            }
        } catch (_: Exception) { /* Billing may be unavailable/offline at startup. */ }
    }

    suspend fun handle(activity: Activity, request: JSONObject): Reply? {
        val event = request.optString("eventName")
        if (!available) return null
        if (event == "store-manage") {
            if (currentUserId != null) activity.startActivity(Intent(Intent.ACTION_VIEW,
                Uri.parse("https://play.google.com/store/account/subscriptions?package=${BuildConfig.APPLICATION_ID}")))
            return null
        }
        val requestId = request.optString("requestId")
        val userId = request.optString("userId")
        val handler = when (event) { "store-products" -> "storeProducts"; "store-purchase" -> "storePurchase"; else -> "storeRestore" }
        fun reply(status: String, extra: JSONObject = JSONObject()) = Reply(handler, JSONObject().apply {
            put("requestId", requestId); put("userId", userId); put("status", status)
            extra.keys().forEach { put(it, extra.get(it)) }
        })
        if (requestId.isBlank() || userId.isBlank() || busy || currentUserId != userId) return reply("error")
        busy = true
        var attempted = false
        try {
            val client = connect(activity)
            if (event == "store-restore") {
                var uncertain = false
                for (type in listOf(BillingClient.ProductType.INAPP, BillingClient.ProductType.SUBS)) {
                    for (purchase in owned(client, type)) {
                        if (submit(purchase, userId).optString("status") != "ok") uncertain = true
                    }
                }
                return reply(if (uncertain) "pending" else "ok")
            }
            val products = products(client, BillingClient.ProductType.INAPP) + products(client, BillingClient.ProductType.SUBS)
            check(currentUserId == userId)
            if (event == "store-products") return reply("ok", JSONObject().put("products", JSONArray().apply {
                products.forEach { product ->
                    val price = if (product.productType == BillingClient.ProductType.SUBS)
                        monthlyOffer(product)?.pricingPhases?.pricingPhaseList?.firstOrNull()?.formattedPrice
                        else oneTimeOffer(product)?.formattedPrice
                    if (price != null) put(JSONObject().put("id", product.productId).put("title", product.title).put("price", price))
                }
            }))
            check(event == "store-purchase")
            val id = request.optString("productId")
            val product = products.firstOrNull { it.productId == id } ?: return reply("error")
            if (id.startsWith("cw_monthly_") && owned(client, BillingClient.ProductType.SUBS).isNotEmpty()) return reply("error")
            val prepared = call(JSONObject().put("action", "prepare"), userId)
            check(currentUserId == userId)
            val offerToken = if (product.productType == BillingClient.ProductType.SUBS) monthlyOffer(product)?.offerToken else oneTimeOffer(product)?.offerToken
            if (offerToken == null) return reply("error")
            val params = BillingFlowParams.newBuilder().setObfuscatedAccountId(prepared.getString("accountToken"))
                .setProductDetailsParamsList(listOf(BillingFlowParams.ProductDetailsParams.newBuilder()
                    .setProductDetails(product).setOfferToken(offerToken).build())).build()
            val waiting = Pending(userId, id, CompletableDeferred())
            pending = waiting
            attempted = true
            val launched = client.launchBillingFlow(activity, params)
            if (launched.responseCode == BillingClient.BillingResponseCode.USER_CANCELED) return reply("cancelled")
            if (launched.responseCode != BillingClient.BillingResponseCode.OK) return reply("pending")
            val result = withTimeout(110000) { waiting.result.await() }
            check(currentUserId == userId)
            return reply(result.getString("status"), result)
        } catch (_: Exception) {
            return reply(if (attempted) "pending" else "error")
        } finally { pending = null; busy = false }
    }
}
