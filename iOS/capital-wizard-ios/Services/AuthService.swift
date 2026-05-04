//
//  AuthService.swift
//  capital-wizard-ios
//
//  Created by Roman on 07.02.2026.
//

import Foundation
import Auth
import AuthenticationServices

class AuthService: NSObject, Service {

    let client: AuthClient

    private var session: Session?

    var onLogin:  Event<Void> = Event()
    var onLogout: Event<Void> = Event()

    private(set) var isLoggedIn: Bool = false

    private static let redirectURL = URL(string: "capital-wizard-ios://auth/callback")!

    private var appleSignInContinuation: CheckedContinuation<Void, Error>?
    private var appleSignInContextProvider: AppleSignInPresentationContext?

    override init() {
        client = AuthClient(configuration: .init(
            url: URL(string: "https://qzdgdyqsoldkarcshkbi.supabase.co/auth/v1")!,
            headers: ["apikey": "sb_publishable_L2uzqtoQjg4somYmI7RmFg_9Hkwsjgl"],
            flowType: .pkce,
            redirectToURL: AuthService.redirectURL,
            localStorage: KeychainLocalStorage()
        ))
        super.init()
    }

    func postInit() {
        Task {
            do {
                SplashAnimationView.postStatus("Restoring session…")
                session = try await client.session
                SplashAnimationView.postStatus("Verifying account…")
                _ = try await client.user()
                isLoggedIn = true
                SplashAnimationView.postStatus("Session restored")
                await MainActor.run {
                    onLogin.invoke(())
                }
            } catch {
                SplashAnimationView.postStatus("No active session")
                try? await client.signOut()
                session = nil
                isLoggedIn = false
                await MainActor.run {
                    onLogout.invoke(())
                }
            }
        }
    }

    func signIn(email: String, password: String) async throws {
        session = try await client.signIn(email: email, password: password)
        isLoggedIn = true
        await MainActor.run {
            onLogin.invoke(())
        }
    }

    @discardableResult
    func signUp(email: String, password: String) async throws -> Bool {
        let response = try await client.signUp(email: email, password: password)
        session = response.session
        if session != nil {
            isLoggedIn = true
            await MainActor.run {
                onLogin.invoke(())
            }
            return true
        }
        return false
    }

    func signInWithGoogle() async throws {
        session = try await client.signInWithOAuth(
            provider: .google,
            redirectTo: AuthService.redirectURL,
            queryParams: [("prompt", "select_account")]
        )
        isLoggedIn = true
        await MainActor.run {
            onLogin.invoke(())
        }
    }

    @MainActor
    func signInWithApple() async throws {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.email, .fullName]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self

        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = scene.windows.first {
            appleSignInContextProvider = AppleSignInPresentationContext(window: window)
            controller.presentationContextProvider = appleSignInContextProvider
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.appleSignInContinuation = continuation
            controller.performRequests()
        }
        appleSignInContextProvider = nil
    }

    func signOut() async throws {
        // Ignore server-side error — the web app may have already invalidated the session.
        // Always clear local state and notify subscribers regardless.
        try? await client.signOut()
        session = nil
        isLoggedIn = false
        await MainActor.run {
            onLogout.invoke(())
        }
    }
    
    func onOpenUrl(url: URL?) {
        guard let url = url else {
            return
        }
        Task(priority: .high) {
            do {
                session = try await client.session(from: url)
                isLoggedIn = true
                await MainActor.run {
                    onLogin.invoke(())
                }
            } catch {
                print(error)
            }
        }
    }
}

// MARK: - Apple Sign In Delegate

extension AuthService: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityTokenData = credential.identityToken,
              let idToken = String(data: identityTokenData, encoding: .utf8) else {
            appleSignInContinuation?.resume(throwing: NSError(domain: "AuthService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get Apple ID token"]))
            appleSignInContinuation = nil
            return
        }

        Task {
            do {
                session = try await client.signInWithIdToken(credentials: .init(provider: .apple, idToken: idToken))
                isLoggedIn = true
                await MainActor.run {
                    onLogin.invoke(())
                }
                appleSignInContinuation?.resume()
            } catch {
                appleSignInContinuation?.resume(throwing: error)
            }
            appleSignInContinuation = nil
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        appleSignInContinuation?.resume(throwing: error)
        appleSignInContinuation = nil
    }
}

// MARK: - Apple Sign In Presentation Context

private class AppleSignInPresentationContext: NSObject, ASAuthorizationControllerPresentationContextProviding {
    private let window: UIWindow

    init(window: UIWindow) {
        self.window = window
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        return window
    }
}
