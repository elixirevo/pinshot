## MacAppEssentials

- The package checkout defaults to `../tools/library`; `MAC_APP_ESSENTIALS_PATH` can override it.
- Before changing the integration, read `docs/agent-integration.md`, `docs/settings-configuration.md`, and `docs/integration.md` in that checkout.
- Use the shared settings, menus, permission controls, lifecycle, onboarding, and Sparkle adapter. Keep capture engines and persisted keys in PinShot.
- Legal documents belong in Settings > Help & Support, with bundled read-only sheets until public document URLs exist. Do not add legal sidebar pages.
- Terms acceptance is separate from onboarding completion and document viewing. Never include either record in preference resets.
- Build with `make`, run `make test`, and verify app resource bundles and Mach-O deployment/SDK versions. Minimum macOS is 13.
- For Sentry integration, read the package's `docs/sentry-setup.md` and use its developer profile and `scripts/sentry-setup.py`. Never print or bundle management tokens. Keep crash reporting opt-in, shared between Settings and onboarding, and applied on restart. Preserve consent during preference resets.
