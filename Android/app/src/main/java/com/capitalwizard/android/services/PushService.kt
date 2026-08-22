package com.capitalwizard.android.services

import android.Manifest
import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.capitalwizard.android.R
import com.capitalwizard.android.utils.CWLog
import com.capitalwizard.android.utils.Event
import com.google.firebase.messaging.FirebaseMessaging

/** Everything the web app needs to store one row in `push_devices`. */
data class PushRegistration(
    val token: String,
    val deviceName: String,
    val appVersion: String,
    val packageName: String,
)

/**
 * Owns this device's FCM registration. Mirrors the iOS `PushService`.
 *
 * The shell never decides *when* to ask: the web app does, by posting
 * `request-push-token` once someone is signed in. That keeps the Android 13+
 * permission dialog away from the launch screen, where it would land before
 * anyone has seen what the app is for.
 *
 * The answer is always sent back, token or not, so the web side can stop
 * waiting either way.
 */
class PushService {

    companion object {
        /**
         * Must match `ANDROID_CHANNEL_ID` in the send-push edge function — a
         * message naming a channel that doesn't exist is silently dropped on
         * API 26+.
         */
        const val CHANNEL_ID = "cw_general"

        /** Request code for the POST_NOTIFICATIONS prompt on Android 13+. */
        const val PERMISSION_REQUEST_CODE = 8341

        /** Ceiling on the tap-report stash; the web caps at the same order. */
        private const val PENDING_OPEN_REPORTS_MAX = 20

        /** Where the "we have shown the Android 13+ prompt at least once" flag
         *  lives. Without it a refusal and a never-asked state look identical
         *  from here, and the web app would tell a first-time user to go and
         *  turn on a permission nobody has asked them for yet. */
        private const val PREFS_NAME = "cw_push"
        private const val PREF_PERMISSION_ASKED = "permission_asked"

        /**
         * Channels have to exist before the first notification arrives, so this
         * runs at app start rather than at registration time — a push can reach
         * a device that has never opened the app since installing an update.
         * Re-creating an existing channel is a no-op, so it is safe to repeat.
         */
        fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val channel = NotificationChannel(
                CHANNEL_ID,
                context.getString(R.string.push_channel_name),
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = context.getString(R.string.push_channel_description)
            }
            val manager = context.getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }

    /** Fires with the registration, or `null` when it was refused or unavailable. */
    val onRegistration = Event<PushRegistration?>()

    var registration: PushRegistration? = null
        private set

    /**
     * Why the last answer carried no token: `denied` (the user said no),
     * `unavailable` (Firebase not configured in this build), or `error` (a
     * transient failure). Null after a success. Rides along with the bridge
     * answer so the web app's decline log never mistakes a build without
     * google-services.json for a user refusing.
     */
    var lastFailureReason: String? = null
        private set

    private var requestInFlight = false

    /**
     * Fired when a tapped notification carried a `sendId` — the click-tracking
     * handle minted by the send-push function. Subscribers with a live bridge
     * call [consumePendingOpenReports] and forward the ids to the web app,
     * which counts them via its authenticated RPC; ignoring the event leaves
     * them stashed for the app-ready flush, mirroring the deep-link stash.
     */
    val onOpenRecorded = Event<Unit>()

    /**
     * A queue, not a single slot: taps can outpace the bridge (tap → WebView
     * mid-reload → background → tap again), and dropping the older id would
     * undercount the send it belonged to. Capped — anything past a handful is
     * not a person tapping notifications.
     */
    private val pendingOpenSendIds = mutableListOf<String>()

    /**
     * Stashes the click-tracking id of a tapped notification and announces it.
     * The value arrived over the network, so it is capped, never parsed — the
     * web side validates the shape before its RPC ever sees it.
     */
    fun reportOpen(sendId: String) {
        if (sendId.isBlank() || sendId.length > 64) return
        if (pendingOpenSendIds.size >= PENDING_OPEN_REPORTS_MAX) return

        CWLog.log("Notification tap recorded (send …${sendId.takeLast(8)})", category = "Push")
        pendingOpenSendIds.add(sendId)
        onOpenRecorded.invoke(Unit)
    }

    /**
     * Returns the stashed tap ids and clears them, so a tap is only ever
     * reported once — a later app-ready must not re-send ids already handed
     * over (the server dedups per account regardless, but the bridge should
     * not rely on that).
     */
    fun consumePendingOpenReports(): List<String> {
        val ids = pendingOpenSendIds.toList()
        pendingOpenSendIds.clear()
        return ids
    }

    /**
     * Answers the web app's `request-push-token`. [activity] is needed for the
     * Android 13+ permission prompt; without one we can still return a token if
     * permission was granted earlier.
     */
    fun requestRegistration(activity: Activity?) {
        registration?.let {
            // Already registered this launch — answer straight away rather than
            // waiting on another round trip to Google.
            onRegistration.invoke(it)
            return
        }
        if (requestInFlight) return
        requestInFlight = true

        val context = activity?.applicationContext
        if (context == null) {
            lastFailureReason = "error"
            finish(null)
            return
        }

        // Below API 33 notifications need no runtime permission at all — the
        // per-app toggle in system settings is the only gate.
        val needsPermission = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED

        if (needsPermission) {
            markPermissionAsked(context)
            ActivityCompat.requestPermissions(
                activity,
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                PERMISSION_REQUEST_CODE,
            )
            return // continues in onPermissionResult
        }

        fetchToken(context)
    }

    /**
     * The OS notification state as it stands right now, in the vocabulary the
     * web app reads. Mirrors iOS `PushService.readPermission`.
     *
     * Answers a question the `push_devices` registry cannot: a row survives the
     * user switching this app's notifications off, so the registry keeps saying
     * "reachable" while every send is accepted by FCM and then discarded by the
     * phone.
     *
     * `areNotificationsEnabled` is the honest signal on every API level — it
     * covers the Android 13+ runtime permission AND the per-app toggle that is
     * the only gate below 33. The extra cases around it exist so the web app can
     * word the fix correctly:
     *
     *  - `unsupported`   — this build has no Firebase configuration, so nothing
     *                      the user does in Settings will make a push arrive.
     *  - `undetermined`  — 13+, not granted, and we have never shown the prompt.
     *                      There is still a prompt to show; sending somebody to
     *                      Settings would be wrong.
     *  - `denied`        — refused, or switched off later. Settings is the fix.
     */
    fun readPermission(context: Context): String {
        val firebaseReady = runCatching { FirebaseMessaging.getInstance() }.getOrNull() != null
        if (!firebaseReady) return "unsupported"

        if (NotificationManagerCompat.from(context).areNotificationsEnabled()) return "granted"

        val needsRuntimePermission = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU
        if (needsRuntimePermission && !hasAskedPermission(context)) return "undetermined"

        return "denied"
    }

    /**
     * Opens this app's notification settings.
     *
     * The only way out of `denied`: Android stops showing the runtime prompt
     * after two refusals, and below API 33 there was never a prompt at all —
     * the per-app toggle in Settings is the only switch.
     *
     * Falls back to the app-details page on the handful of ROMs that do not
     * handle the notification-specific intent.
     */
    fun openSystemSettings(context: Context) {
        val notificationSettings = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
            .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

        val opened = runCatching { context.startActivity(notificationSettings) }.isSuccess
        if (opened) return

        val appDetails = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            .setData(Uri.fromParts("package", context.packageName, null))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching { context.startActivity(appDetails) }
            .onFailure { CWLog.log("Couldn't open notification settings: ${it.message}", category = "Push") }
    }

    private fun hasAskedPermission(context: Context): Boolean =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(PREF_PERMISSION_ASKED, false)

    private fun markPermissionAsked(context: Context) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(PREF_PERMISSION_ASKED, true)
            .apply()
    }

    /** Forwarded by the hosting Activity from `onRequestPermissionsResult`. */
    fun onPermissionResult(activity: Activity, granted: Boolean) {
        if (!granted) {
            CWLog.log("Notification permission refused", category = "Push")
            lastFailureReason = "denied"
            finish(null)
            return
        }
        fetchToken(activity.applicationContext)
    }

    /**
     * A token can be reissued at any time (app restore, data cleared, Google
     * rotating it). Re-announcing it re-runs the upsert on the web side, which
     * is how the new one replaces the old.
     */
    fun onTokenRefreshed(context: Context, token: String) {
        CWLog.log("FCM token refreshed (…${token.takeLast(8)})", category = "Push")
        finish(buildRegistration(context, token))
    }

    private fun fetchToken(context: Context) {
        // Without google-services.json Firebase never initialises, and asking it
        // for a token throws. That is the normal state of a build made before
        // the Firebase project exists, so it is a log line, not a crash.
        val messaging = runCatching { FirebaseMessaging.getInstance() }.getOrNull()
        if (messaging == null) {
            CWLog.log("Firebase is not configured — no push token available", category = "Push")
            lastFailureReason = "unavailable"
            finish(null)
            return
        }

        messaging.token
            .addOnSuccessListener { token ->
                CWLog.log("FCM token registered (…${token.takeLast(8)})", category = "Push")
                finish(buildRegistration(context, token))
            }
            .addOnFailureListener { error ->
                CWLog.log("FCM token request failed: ${error.message}", category = "Push")
                lastFailureReason = "error"
                finish(null)
            }
    }

    private fun buildRegistration(context: Context, token: String): PushRegistration {
        val version = runCatching {
            context.packageManager.getPackageInfo(context.packageName, 0).versionName
        }.getOrNull() ?: ""

        return PushRegistration(
            token = token,
            deviceName = "${Build.MANUFACTURER} ${Build.MODEL}".trim(),
            appVersion = version,
            packageName = context.packageName,
        )
    }

    private fun finish(registration: PushRegistration?) {
        requestInFlight = false
        if (registration != null) lastFailureReason = null
        this.registration = registration ?: this.registration
        onRegistration.invoke(registration)
    }
}
