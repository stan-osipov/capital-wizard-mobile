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

/// Covers the referral code as a VALUE, separate from the route it also produces.
///
/// The native sign-up screen shows the code and the WebView is sent to
/// `?ref=` — two consumers of one link, and the earlier design served only the
/// second. These tests exist because the two can silently drift apart: the route
/// slot is single-valued and gets overwritten by the next link that arrives.
struct ReferralIntakeTests {

    // MARK: - Shape

    @Test func acceptsAWellFormedCode() {
        #expect(ReferralIntake.normalized(" stan-8f2k ") == "STAN-8F2K")
    }

    @Test func rejectsCodesTheDatabaseWouldRefuse() {
        #expect(ReferralIntake.normalized("ab") == nil)          // too short
        #expect(ReferralIntake.normalized("-LEADING") == nil)    // leading dash
        #expect(ReferralIntake.normalized("has space") == nil)
        #expect(ReferralIntake.normalized("код-1234") == nil)    // non-ASCII
        #expect(ReferralIntake.normalized(String(repeating: "A", count: 33)) == nil)
        #expect(ReferralIntake.normalized(nil) == nil)
    }

    @Test func refusesAPasteThatIsSomebodysReading() {
        // A whole article on the clipboard is not a referral code, and the
        // length guard is what stops us trying to read one as if it were.
        let essay = String(repeating: "A", count: ReferralIntake.maxPasteLength + 1)
        #expect(ReferralIntake.fromPaste(essay) == nil)
        #expect(ReferralIntake.fromPaste("STAN-8F2K") == "STAN-8F2K")
    }

    // MARK: - Surviving a relaunch

    /// Its own store per test: these are global keys and the suite runs in
    /// parallel, so sharing `UserDefaults.standard` makes the tests race.
    private func scratchDefaults(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: "ReferralIntakeTests.\(name)")!
        defaults.removePersistentDomain(forName: "ReferralIntakeTests.\(name)")
        return defaults
    }

    @Test func remembersACodeAcrossLaunches() {
        // DeepLinkService is in-memory; somebody who taps the link, reaches the
        // form and puts the phone down would otherwise lose the code.
        let defaults = scratchDefaults(#function)
        ReferralIntake.remember("stan-8f2k", into: defaults)

        #expect(ReferralIntake.remembered(from: defaults) == "STAN-8F2K")
        // With nothing in this launch's slot, the prefill falls back to it.
        #expect(ReferralIntake.prefill(deepLinkService: DeepLinkService(), defaults: defaults) == "STAN-8F2K")
    }

    @Test func thisLaunchsLinkBeatsTheRememberedOne() {
        let defaults = scratchDefaults(#function)
        ReferralIntake.remember("OLD-CODE1", into: defaults)

        let service = DeepLinkService()
        service.handle(url: URL(string: "https://capital-wizard.com/r/NEW-CODE1"))

        #expect(ReferralIntake.prefill(deepLinkService: service, defaults: defaults) == "NEW-CODE1")
    }

    @Test func forgettingClearsIt() {
        let defaults = scratchDefaults(#function)
        ReferralIntake.remember("STAN-8F2K", into: defaults)
        ReferralIntake.forget(from: defaults)
        #expect(ReferralIntake.remembered(from: defaults) == nil)
    }

    @Test func aMalformedCodeIsNeverRemembered() {
        let defaults = scratchDefaults(#function)
        ReferralIntake.remember("no", into: defaults)
        #expect(ReferralIntake.remembered(from: defaults) == nil)
    }

    // MARK: - The code as its own slot

    @Test func recordsTheCodeBesideTheRoute() {
        let service = DeepLinkService()
        #expect(service.handle(url: URL(string: "https://capital-wizard.com/r/stan-8f2k")) == true)

        #expect(service.pendingReferralCode == "STAN-8F2K")
        #expect(service.consumePendingPath() == "/auth/register?ref=STAN-8F2K")
    }

    @Test func keepsTheCodeAfterTheRouteIsConsumed() {
        // The sign-up screen may be built after the WebView has already taken
        // the route — and a person who backs out and returns must still see it.
        let service = DeepLinkService()
        service.handle(url: URL(string: "https://capital-wizard.com/r/STAN-8F2K"))
        _ = service.consumePendingPath()

        #expect(service.pendingReferralCode == "STAN-8F2K")
    }

    @Test func aLaterInviteDoesNotEraseTheCode() {
        // The route slot is single-valued; the code slot must not be, or an
        // invite tapped after a referral link would silently drop the bonus.
        let service = DeepLinkService()
        service.handle(url: URL(string: "https://capital-wizard.com/r/STAN-8F2K"))
        service.handle(url: URL(string: "https://app.capital-wizard.com/join/abc123"))

        #expect(service.pendingReferralCode == "STAN-8F2K")
        #expect(service.consumePendingPath() == "/join/abc123")
    }

    @Test func ordinaryLinksSetNoCode() {
        let service = DeepLinkService()
        service.handle(url: URL(string: "https://app.capital-wizard.com/join/abc123"))
        #expect(service.pendingReferralCode == nil)
    }

    @Test func onlyTheApexCanSetACode() {
        // `/r/<CODE>` on the APP host is an ordinary route, not a referral: the
        // host check is what keeps a path shape from acting as a claim.
        #expect(DeepLinkService.referralCode(from: URL(string: "https://app.capital-wizard.com/r/STAN-8F2K")!) == nil)
        #expect(DeepLinkService.referralCode(from: URL(string: "https://capital-wizard.com/r/STAN-8F2K")!) == "STAN-8F2K")
    }

    // MARK: - What the person actually submitted

    @Test func aTypedCodeOverwritesTheOneThatArrived() {
        // The field is editable, so what they SEND has to travel, not what came in.
        let service = DeepLinkService()
        service.handle(url: URL(string: "https://capital-wizard.com/r/STAN-8F2K"))

        #expect(service.stashReferral(code: "olena-4t7p") == true)
        #expect(service.pendingReferralCode == "OLENA-4T7P")
        #expect(service.consumePendingPath() == "/auth/register?ref=OLENA-4T7P")
    }

    @Test func submittingACodeDoesNotHijackAnInvite() {
        // An invite link is a DESTINATION; a referral code is a parameter. The
        // person tapped the first one, so it must survive the second.
        let service = DeepLinkService()
        service.handle(url: URL(string: "https://app.capital-wizard.com/join/abc123"))

        #expect(service.stashReferral(code: "STAN-8F2K") == true)
        #expect(service.pendingReferralCode == "STAN-8F2K")
        #expect(service.consumePendingPath() == "/join/abc123")
    }

    @Test func aMalformedSubmissionStashesNothing() {
        let service = DeepLinkService()
        #expect(service.stashReferral(code: "no") == false)
        #expect(service.pendingReferralCode == nil)
        #expect(service.consumePendingPath() == nil)
    }
}
