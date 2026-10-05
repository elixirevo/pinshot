# MacAppEssentials integration

The host imports the local package at `../tools/library`, configurable with `MAC_APP_ESSENTIALS_PATH`. Initial integration was verified against revision `b3e36a462ea6da4ba3d3272c08526765d9aca3c0` (0.5.1). It uses the package directly; no shared UI sources are copied into this repository. Preserve the library's `Integrations/MacAppUpdatesSparkle` relative layout.

| Shared product | PinShot integration |
| --- | --- |
| MacAppCore | One process-language resolver; saved choice applies after restart |
| MacAppSettings | Settings window and navigation, shortcut recorder, native permission adapters, login item status, support and scoped resets |
| MacAppMenuBar | Stable status item/menu with read-only state providers and deferred actions |
| MacAppMainMenu | Native Edit/Window commands, Settings, About, Help and sidebar action |
| MacAppLifecycle | Accessory mode, window close keeps running, Finder reopen |
| MacAppOnboarding | Guide images, versioned terms receipt, first-run completion and review |
| MacAppUpdatesSparkle | One updater, deferred start, shared UI/menu model and KVO |
| MacAppDiagnosticsSentry | Opt-in crash-only reporting with shared consent and restart policy |

PinShot owns capture, annotation, image export, frame editing, macros, Carbon hotkey registration and history retention. Existing `hotkey.*`, `screenshot.style.v1`, `pins.history.*`, `save.directory.*`, saved-region and macro keys are preserved. Login item state continues to come from SMAppService, and update preferences continue to come from Sparkle. Sentry crash reporting is optional, off by default and shared between General settings and onboarding. Usage analytics is disabled.

## Build and packaging

`Package.swift` separates `PinShotApp`, the app entry point, and the existing executable regression suite. `make test` builds the test product in Debug with testable imports. `make` builds Release and packages all four MacAppEssentials UI resource bundles, the host resource bundle and Sparkle.framework. `make universal` builds both architectures and combines the executables; `make sign-adhoc` also signs the universal bundle. Developer ID signing and notarization still use the release workflow.

The minimum OS is macOS 13 in Package.swift, Info.plist, icon compilation, linker arguments and Homebrew metadata. The build script passes the selected SDK version independently of the deployment target and checks Mach-O `minos` and `sdk`. The SDK must support the package's macOS 26 glass APIs (Xcode 26+); they remain availability guarded for macOS 13–15. Package.resolved pins Sparkle 2.10.0 and Sentry Cocoa 9.30.0. `make sparkle` is retained for the command-line release/signing/feed tools, not as the app's SDK linkage.

## First-run and legal flow

`PinShot.onboarding.completedVersion` and `PinShot.terms.acceptance` are separate keys. The app creates read-only models/menus first; global hotkeys, capture entry points and updater startup remain disabled until required agreement is stored and the user finishes or dismisses the remaining setup. No permission prompt is triggered at startup. The settings and onboarding surfaces share a single PermissionSettingsModel. Updated terms use the dedicated agreement window when onboarding is already complete.

Read-only legal sheets live under Help & Support with the onboarding-review action. No legal sidebar categories or invented public document URLs are used. Both translations and their full text are bundled. Missing/corrupt legal resources fail startup instead of silently substituting an empty document. Corrupt agreement receipts keep the gate closed. Review does not delete or rewrite acceptance or original completion records.

The versioned Korean/English text is in `Sources/Resources/{en,ko}.lproj/{terms,privacy}.txt`. Keep released versions in repository history; increment the legal version for substantive changes requiring new agreement. The documents use the operator/contact supplied by the user: elixirevo / elixirevo@gmail.com. The drafting rationale and sources are in [legal provenance](legal/README.md).

## Onboarding screenshots

`Sources/Resources/onboarding-editor.png` and `onboarding-pins.png` were captured on 2026-10-05 from the running native PinShot UI using the existing fixture preview modes. The editor was operated to select a region and add arrow/text annotations. The pin shows its actual close/copy/save/draw/history controls. Only generated sample content is pictured; no desktop documents were captured. Images have localized accessibility descriptions.

## Verification

- `make test`: existing geometry, Retina rendering, annotations, frame migration, history retention and pin UI regressions, plus shared permission confirmation/status, legal-resource completeness, explicit agreement, scope-preserving reset, version/language changes, review and corrupt receipts.
- `make universal`: arm64 and x86_64 executables, resource bundle packaging, minos 13.0 and actual SDK metadata.
- UI: 740×500pt settings content, Korean and English onboarding, light/dark appearance, image steps, legal full-text scrolling, read-only privacy sheet, and Help & Support navigation.
- Permission, login item and updater previews use fake/unavailable providers. Live OS grants and downloaded update installation are not performed by regression tests.

## Sentry

Project: https://elixirevo.sentry.io/settings/projects/pinshot/ (organization/team `elixirevo`, platform `apple-macos`, US region). `Sources/Resources/SentryConfiguration.json` contains only public configuration, provisioned through the package's `scripts/sentry-setup.py`. The developer management token stays in Keychain or the CI environment.

`AppDiagnostics` owns the shared adapter. It starts only after the app's required agreement flow and only with consent active at process launch. Changing `MacAppLibrary.crashReportingEnabled` requires restart; onboarding, permissions, terms acceptance and capture resets never opt the user in. Existing users do not repeat onboarding merely because this optional feature was added. They can enable it in General settings or review onboarding.

Only fatal exception events pass the package filter. Screenshots are not attached; performance, sessions, network tracking, logs, metrics and replay are disabled. Technical exception information is not guaranteed anonymous. The project's default data scrubber and IP scrubbing are enabled. The updated privacy policy describes the US recipient, local pending reports, restart/withdrawal behavior and retention criteria. Earlier policy text is archived independently of the unchanged Terms version.

Sentry is statically linked. Packaging copies its privacy manifest and license into the app and saves `PinShot.app.dSYM` beside it. Universal builds merge both architecture dSYMs; preserve the symbols for each released build. Upload the exact build's symbols explicitly:

```sh
make sign-adhoc
python3 scripts/upload_sentry_symbols.py build/PinShot.app.dSYM
```

The uploader uses the shared developer profile/Keychain, or `SENTRY_AUTH_TOKEN` in CI. It does not upload source bundles. Run this for each release after building and before discarding artifacts. Building the app does not contact the Sentry management API or upload symbols.

Regression tests use isolated preferences, validate bundled configuration and exercise consent/restart/withdrawal without starting Sentry or sending crash events. Symbol upload verifies debug-file processing, not end-to-end crash delivery. A real crash-receipt test remains a separate explicit test run.

References: [Sentry macOS data collection](https://docs.sentry.io/platforms/apple/guides/macos/data-management/data-collected/), [debug symbols](https://docs.sentry.io/platforms/apple/guides/macos/dsym/), and the package's `docs/sentry-setup.md` / `docs/service-integrations.md`.
