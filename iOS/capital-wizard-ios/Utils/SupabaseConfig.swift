//
//  SupabaseConfig.swift
//  capital-wizard-ios
//

import Foundation

/// The one place this shell holds the Supabase project it talks to.
///
/// EXTRACTED, NOT INVENTED. These two values were already written out by hand in
/// two places — `AuthService` (the auth client) and `StoreService` (the
/// `store-verify` function) — and the Apple Pay poster would have made a third.
/// Three hand-copied references to one project is how one of them gets missed
/// when the project moves, and the one that gets missed is always the one nobody
/// is looking at: here that would be a background App Intent firing on a locked
/// phone, which fails with no screen to fail on.
///
/// NOT A SECRET, and that needs saying before somebody "fixes" it. The
/// publishable key is the anon key: it ships inside every web bundle and every
/// binary we publish, and on its own it grants nothing. Row-level security
/// decides what a request may read, and it decides that from the USER's bearer
/// token — never from this. The server has to assume this value is public
/// because it demonstrably is, so hiding it in the client would buy nothing.
///
/// No Android counterpart, deliberately. The same two values sit inline in
/// `Android/.../services/AuthService.kt` and `StoreService.kt`, and Apple Pay
/// does not exist on that side at all (see `WebViewBridge.getNativeAppScript`),
/// so nothing over there grew a third copy and there is nothing for this file
/// to prevent. Extracting it there too would be churn with no bug behind it.
enum SupabaseConfig {

    /// The project's base address. Everything else here is built from it, so a
    /// project move is one line.
    static let projectUrl = "https://qzdgdyqsoldkarcshkbi.supabase.co"

    /// The anon / publishable key, sent as the `apikey` header. See the note
    /// above about why this is in the binary in plain sight.
    static let publishableKey = "sb_publishable_L2uzqtoQjg4somYmI7RmFg_9Hkwsjgl"

    /// Where the Supabase Swift SDK's `AuthClient` is pointed.
    ///
    /// Force-unwrapped because it is a compile-time literal that either parses
    /// on every device or on none — a typo here is caught the first time anybody
    /// launches the app, not in the field. This is not the kind of unwrap the
    /// repo bans; that rule is about values that arrived over a network.
    static let authUrl = URL(string: "\(projectUrl)/auth/v1")!

    /// An edge function's address, `nil` if the name does not compose into a
    /// valid URL. Optional rather than force-unwrapped so callers reached from a
    /// background intent have something to decline on instead of a crash.
    static func functionUrl(_ name: String) -> URL? {
        URL(string: "\(projectUrl)/functions/v1/\(name)")
    }
}
