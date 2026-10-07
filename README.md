# capital-wizard-mobile

Hybrid iOS and Android shells for Capital Wizard. Build instructions are in
`CLAUDE.md`.

## Direct mobile wallet sandbox integration

Both shells include matching `StoreService` implementations: system StoreKit on
iOS and Google Play Billing 8.3.0 on Android. RevenueCat is not used. Catalog,
console setup, server verification, rollout limits and device tests are documented
in `../capital-wizard/docs/mobile-wallet-payments.md`.

Purchases require a signed-in Capital Wizard administrator and a Debug build.
The server must be configured and the corresponding sandbox gate enabled before
opening a purchase sheet. Release builds advertise no store capability. No store
API keys or service-account credentials belong in these native builds.

The native layer sends purchase evidence straight to `store-verify` using its
Supabase session. The server validates the store, account and paid transaction,
and atomically credits the isolated test wallet. Only then does iOS finish the
transaction or the server acknowledge/consume the Play purchase. Pending results
retry on launch/restore. The web bridge never receives purchase evidence.

This is not a billing release. Both stores require real device sandbox testing;
live settlement and release-build enablement remain disabled. Build tools and
caches installed for this worktree live under ignored `.build/`.
