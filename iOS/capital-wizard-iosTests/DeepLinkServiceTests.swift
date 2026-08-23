//
//  DeepLinkServiceTests.swift
//  capital-wizard-iosTests
//

import Testing
import Foundation
@testable import capital_wizard_ios

/// Covers the URL → route mapping. This is the one piece of deep-link handling
/// with real security weight: everything it returns is loaded into the WebView,
/// so a link must never be able to steer it off our own origin.
struct DeepLinkServiceTests {

    // MARK: - Universal links

    @Test func acceptsInviteLink() {
        #expect(DeepLinkService.appPath(from: URL(string: "https://app.capital-wizard.com/join/abc123")!)
                == "/join/abc123")
    }

    @Test func keepsQueryAndFragment() {
        let url = URL(string: "https://app.capital-wizard.com/transactions/page/2?filter=open#row")!
        #expect(DeepLinkService.appPath(from: url) == "/transactions/page/2?filter=open#row")
    }

    // MARK: - Referral links on the marketing apex

    @Test func translatesReferralLinkIntoSignUp() {
        // The apex has no in-app route of its own: `/r/<CODE>` is a page on the
        // marketing site, so it becomes the sign-up screen carrying the code.
        #expect(DeepLinkService.appPath(from: URL(string: "https://capital-wizard.com/r/STAN-8F2K")!)
                == "/auth/register?ref=STAN-8F2K")
    }

    @Test func upperCasesReferralCode() {
        #expect(DeepLinkService.appPath(from: URL(string: "https://capital-wizard.com/r/stan-8f2k")!)
                == "/auth/register?ref=STAN-8F2K")
    }

    @Test func ignoresTheRestOfTheMarketingSite() {
        // Only /r/* is claimed. Everything else on that domain has to keep
        // opening in the browser for people who do not have the app.
        #expect(DeepLinkService.appPath(from: URL(string: "https://capital-wizard.com/")!) == nil)
        #expect(DeepLinkService.appPath(from: URL(string: "https://capital-wizard.com/pricing/")!) == nil)
        #expect(DeepLinkService.appPath(from: URL(string: "https://capital-wizard.com/blog/a-post/")!) == nil)
    }

    @Test func rejectsMalformedReferralPaths() {
        #expect(DeepLinkService.appPath(from: URL(string: "https://capital-wizard.com/r/")!) == nil)
        #expect(DeepLinkService.appPath(from: URL(string: "https://capital-wizard.com/r/ab")!) == nil)
        #expect(DeepLinkService.appPath(from: URL(string: "https://capital-wizard.com/r/a/b")!) == nil)
        #expect(DeepLinkService.appPath(from: URL(string: "https://capital-wizard.com/r/-lead")!) == nil)
    }

    @Test func referralPathOnTheAppHostIsNotTranslated() {
        // The app host owns its own routes; only the apex is remapped.
        #expect(DeepLinkService.appPath(from: URL(string: "https://app.capital-wizard.com/r/STAN-8F2K")!)
                == "/r/STAN-8F2K")
    }

    @Test func rejectsForeignHost() {
        #expect(DeepLinkService.appPath(from: URL(string: "https://evil.example.com/join/abc")!) == nil)
    }

    @Test func rejectsLookalikeHost() {
        #expect(DeepLinkService.appPath(from: URL(string: "https://app.capital-wizard.com.evil.test/join/abc")!) == nil)
    }

    @Test func ignoresBareRoot() {
        // The app already opens at the root — there is no route to restore.
        #expect(DeepLinkService.appPath(from: URL(string: "https://app.capital-wizard.com/")!) == nil)
        #expect(DeepLinkService.appPath(from: URL(string: "https://app.capital-wizard.com")!) == nil)
    }

    @Test func matchesHostCaseInsensitively() {
        #expect(DeepLinkService.appPath(from: URL(string: "https://APP.Capital-Wizard.com/join/abc")!)
                == "/join/abc")
    }

    // MARK: - Custom scheme fallback

    @Test func acceptsCustomSchemeRoute() {
        let url = URL(string: "capital-wizard-ios://open?path=/join/abc123")!
        #expect(DeepLinkService.appPath(from: url) == "/join/abc123")
    }

    @Test func leavesOAuthCallbackAlone() {
        // Must fall through to AuthService, not be swallowed as a route.
        let url = URL(string: "capital-wizard-ios://auth/callback?code=xyz")!
        #expect(DeepLinkService.appPath(from: url) == nil)
    }

    @Test func rejectsAbsoluteUrlSmuggledAsPath() {
        let url = URL(string: "capital-wizard-ios://open?path=https://evil.example.com/steal")!
        #expect(DeepLinkService.appPath(from: url) == nil)
    }

    @Test func rejectsProtocolRelativePath() {
        // `//evil.example.com` would resolve against our scheme and leave the origin.
        let url = URL(string: "capital-wizard-ios://open?path=//evil.example.com/steal")!
        #expect(DeepLinkService.appPath(from: url) == nil)
    }

    @Test func rejectsUnrootedPath() {
        let url = URL(string: "capital-wizard-ios://open?path=join/abc")!
        #expect(DeepLinkService.appPath(from: url) == nil)
    }

    @Test func rejectsCustomSchemeWithoutPath() {
        #expect(DeepLinkService.appPath(from: URL(string: "capital-wizard-ios://open")!) == nil)
    }

    @Test func rejectsUnknownScheme() {
        #expect(DeepLinkService.appPath(from: URL(string: "capital-wizard-android://open?path=/join/abc")!) == nil)
    }

    // MARK: - Stashing

    @Test func stashesUntilConsumedThenClears() {
        let service = DeepLinkService()

        #expect(service.handle(url: URL(string: "https://app.capital-wizard.com/join/abc")!) == true)
        #expect(service.hasPendingPath == true)
        #expect(service.consumePendingPath() == "/join/abc")

        // One-shot: a later reload must not silently re-navigate the user.
        #expect(service.hasPendingPath == false)
        #expect(service.consumePendingPath() == nil)
    }

    @Test func declinesUnroutableUrlWithoutStashing() {
        let service = DeepLinkService()

        #expect(service.handle(url: URL(string: "capital-wizard-ios://auth/callback?code=xyz")!) == false)
        #expect(service.hasPendingPath == false)
    }

    @Test func latestLinkWins() {
        let service = DeepLinkService()

        service.handle(url: URL(string: "https://app.capital-wizard.com/join/first")!)
        service.handle(url: URL(string: "https://app.capital-wizard.com/join/second")!)

        #expect(service.consumePendingPath() == "/join/second")
    }
}
