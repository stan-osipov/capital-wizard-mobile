package com.capitalwizard.android.services

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.capitalwizard.android.R
import com.capitalwizard.android.ui.auth.LoginActivity
import com.capitalwizard.android.utils.CWLog
import com.capitalwizard.android.utils.ServiceManager
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/**
 * Receives pushes from FCM.
 *
 * Android splits delivery in two, and both halves need covering:
 *  * **Backgrounded** — the system tray draws the `notification` payload itself
 *    and this class is never called. Tapping launches [LoginActivity] with the
 *    message's `data` map as intent extras, which is where the `route` is read.
 *  * **Foregrounded** — nothing is drawn automatically; [onMessageReceived]
 *    fires and we post the notification ourselves, with the same tap behaviour.
 */
class PushMessagingService : FirebaseMessagingService() {

    companion object {
        /** Intent extra carrying the in-app route a tap should open. */
        const val EXTRA_ROUTE = "route"

        /**
         * Intent extra carrying an EXTERNAL https page a tap should open. Kept
         * separate from [EXTRA_ROUTE] all the way down: a route is shown inside
         * the WebView that holds the signed-in session, and an outside page must
         * never land there. The server decides which of the two it is.
         */
        const val EXTRA_URL = "url"

        /**
         * Intent extra carrying the send's click-tracking id, minted by the
         * send-push function. The tap hands it to [PushService.reportOpen] on
         * the way past LoginActivity; the web app does the actual counting.
         */
        const val EXTRA_SEND_ID = "sendId"

        /**
         * Builds the tap intent. Routed through the launcher rather than
         * WebViewActivity directly because the app may be signed out or not
         * running at all; LoginActivity is the entry point that resolves both,
         * and it already knows how to hand a route to DeepLinkService.
         */
        fun tapIntent(context: Context, route: String?, url: String?, sendId: String?): PendingIntent {
            val intent = Intent(context, LoginActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                if (!route.isNullOrBlank()) putExtra(EXTRA_ROUTE, route)
                else if (!url.isNullOrBlank()) putExtra(EXTRA_URL, url)
                if (!sendId.isNullOrBlank()) putExtra(EXTRA_SEND_ID, sendId)
            }
            // The send id leads the request code: two notifications with the
            // same link are still DIFFERENT sends, and sharing a PendingIntent
            // would overwrite the first one's extras with the second's — its
            // tap would then be counted against the wrong send.
            return PendingIntent.getActivity(
                context,
                (sendId ?: route ?: url).hashCode(),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        ServiceManager.getService<PushService>()?.onTokenRefreshed(applicationContext, token)
    }

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)

        val title = message.notification?.title ?: message.data["title"] ?: return
        val body = message.notification?.body ?: message.data["body"] ?: ""
        val route = message.data["route"]
        val url = message.data["url"]
        val sendId = message.data["sendId"]

        CWLog.log("Push received in foreground: $title", category = "Push")
        PushService.ensureChannel(applicationContext)

        val notification = NotificationCompat.Builder(applicationContext, PushService.CHANNEL_ID)
            // A white-on-transparent silhouette — Android tints the small icon
            // and would render a full-colour launcher icon as a grey blob.
            .setSmallIcon(R.drawable.ic_cw_mark)
            .setColor(ContextCompat.getColor(applicationContext, R.color.accent))
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(tapIntent(applicationContext, route, url, sendId))
            .build()

        val manager = applicationContext.getSystemService(NotificationManager::class.java)
        // Posting without POST_NOTIFICATIONS on API 33+ is a silent no-op rather
        // than a throw, and we only get here after the user allowed it anyway.
        manager?.notify(message.messageId?.hashCode() ?: title.hashCode(), notification)
    }
}
