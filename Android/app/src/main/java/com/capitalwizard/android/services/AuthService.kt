package com.capitalwizard.android.services

import android.content.Context
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

    val onLogin = Event<Unit>()
    val onLogout = Event<Unit>()

    var isLoggedIn: Boolean = false
        private set

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

    init {
        // Observe session status changes
        auth.sessionStatus.onEach { status ->
            when (status) {
                is SessionStatus.Authenticated -> {
                    isLoggedIn = true
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
        scope.launch {
            try {
                auth.parseFragmentAndImportSession(uri)
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
