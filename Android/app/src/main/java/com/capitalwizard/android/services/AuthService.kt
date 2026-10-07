package com.capitalwizard.android.services

import android.content.Context
import android.content.Intent
import android.net.Uri
import com.capitalwizard.android.utils.Event
import com.capitalwizard.android.utils.EventCallback
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.auth.FlowType
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.providers.Google
import io.github.jan.supabase.auth.providers.builtin.Email
import io.github.jan.supabase.auth.status.SessionStatus
import io.github.jan.supabase.createSupabaseClient
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch

class AuthService(private val context: Context) {

    companion object {
        private const val PREFS = "cw_auth_state"
        private const val KEY_EVER_SIGNED_IN = "ever_signed_in"
    }

    val onLogin = Event<Unit>()
    val onLogout = Event<Unit>()

    var isLoggedIn: Boolean = false
        private set

    /**
     * Whether ANY account has ever reached a session on this device.
     *
     * Decides which auth screen the app roots on: somebody who has never signed
     * in is being asked for a password they have not chosen yet, so Create
     * Account leads until this flips. Deliberately not "is there a session" —
     * that is cleared on sign-out, which would drop a returning user back onto
     * the sign-up form every time they log out.
     *
     * Mirrors iOS `AuthService.hasEverSignedIn`, where the same flag is doing
     * one extra job: over there the SDK keeps the session in the Keychain, which
     * survives a delete-and-reinstall, so device state and session state disagree
     * far more often than they do here.
     */
    val hasEverSignedIn: Boolean
        get() = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_EVER_SIGNED_IN, false)

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    private val supabase = createSupabaseClient(
        supabaseUrl = "https://qzdgdyqsoldkarcshkbi.supabase.co",
        supabaseKey = "sb_publishable_L2uzqtoQjg4somYmI7RmFg_9Hkwsjgl"
    ) {
        install(Auth) {
            flowType = FlowType.PKCE
            scheme = "capital-wizard-android"
            host = "auth/callback"
        }
    }

    val auth get() = supabase.auth
    val storeUserId: String? get() = if (isLoggedIn) auth.currentUserOrNull()?.id else null

    init {
        // Observe session status changes
        auth.sessionStatus.onEach { status ->
            when (status) {
                is SessionStatus.Authenticated -> {
                    markSignedIn()
                    onLogin.invoke(Unit)
                }
                is SessionStatus.NotAuthenticated -> {
                    if (isLoggedIn) {
                        isLoggedIn = false
                        onLogout.invoke(Unit)
                    }
                }
                else -> { /* Initializing / LoadingFromStorage */ }
            }
        }.launchIn(scope)
    }

    /** Marks the service — and this device — as having reached a session. */
    private fun markSignedIn() {
        isLoggedIn = true
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY_EVER_SIGNED_IN, true).apply()
        // From here the web app owns redemption. Keeping the code would pre-fill
        // it onto a second account created on this phone.
        ReferralIntake.forget(context)
    }

    fun tryRestoreSession() {
        // Session restoration happens automatically via the Auth plugin.
        // The sessionStatus flow above will emit Authenticated if a valid session exists.
    }

    suspend fun signIn(email: String, password: String) {
        auth.signInWith(Email) {
            this.email = email
            this.password = password
        }
    }

    suspend fun signUp(email: String, password: String): Boolean {
        val result = auth.signUpWith(Email) {
            this.email = email
            this.password = password
        }
        return result != null
    }

    suspend fun signInWithGoogle() {
        auth.signInWith(Google)
    }

    /**
     * Sends a password-recovery email. Uses the configured PKCE redirect
     * (scheme/host set on the Auth plugin above) so the deep link returns
     * to the app. Mirrors the iOS `resetPasswordForEmail` flow.
     */
    suspend fun resetPasswordForEmail(email: String) {
        auth.resetPasswordForEmail(email)
    }

    suspend fun signOut() {
        try {
            auth.signOut()
        } catch (_: Exception) {
            // Ignore server-side errors — web app may have already invalidated the session
        }
        isLoggedIn = false
        onLogout.invoke(Unit)
    }

    fun handleDeepLink(uri: Uri) {
        val code = uri.getQueryParameter("code") ?: return
        scope.launch {
            try {
                auth.exchangeCodeForSession(code)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    fun getAccessToken(): String? =
        auth.currentSessionOrNull()?.accessToken

    fun getRefreshToken(): String? =
        auth.currentSessionOrNull()?.refreshToken
}
