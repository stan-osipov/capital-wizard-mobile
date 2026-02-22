//
//  AuthService.swift
//  capital-wizard-ios
//
//  Created by Roman on 07.02.2026.
//

import Foundation
import Auth

class AuthService: NSObject, Service {

    let client: AuthClient
    
    private var session: Session?

    var onLogin:  Event<Void> = Event()
    var onLogout: Event<Void> = Event()

    private(set) var isLoggedIn: Bool = false

    private static let redirectURL = URL(string: "capital-wizard-ios://auth/callback")!

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
                session = try await client.session
                isLoggedIn = true
                await MainActor.run {
                    onLogin.invoke(())
                }
            } catch {
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
            redirectTo: AuthService.redirectURL
        )
        isLoggedIn = true
        await MainActor.run {
            onLogin.invoke(())
        }
    }

    func signOut() async throws {
        try await client.signOut()
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
