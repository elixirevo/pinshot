# Releasing PinShot

The app uses Sparkle 2.10.0 from its official binary distribution. `make sparkle` downloads the pinned archive, verifies its SHA-256, and caches the framework and signing tools in `.build/sparkle`. Builds embed the framework and set a bundle-relative loader path.

`deploy.json` connects the Makefile to the shared `../tools/deploy/deploy.sh` pipeline. It builds separate Apple Silicon and Intel apps, signs nested components with Developer ID, notarizes and staples both apps and DMGs, generates a signed appcast, verifies the artifacts, then publishes GitHub and Homebrew releases.

## Prerequisites

- Xcode 26 or later with Icon Composer, GitHub CLI, and Homebrew.
- The Developer ID identity and existing notarytool Keychain profile named in `deploy.json`.
- The PinShot-specific Sparkle signing account `pinshot-2026-09`, named in `deploy.json` and created for 1.2.0. Its public key must match `SUPublicEDKey` in `Info.plist` and `sparkle-public-key.txt`. Reuse this account for subsequent releases; never generate a replacement key as part of a build. Private keys stay in Keychain.
- A clean checkout of `elixirevo/homebrew-tap` at `../tools/homebrew-tap`.

## Release steps

1. Update `CFBundleShortVersionString` and `CFBundleVersion` in `Info.plist`, and write `docs/releases/<version>.md`. Build numbers must increase across releases. The shared pipeline uses the plist build number for Intel and that number plus one for Apple Silicon, so each next release needs at least two new build numbers. Version 1.2.0 uses 1200 and 1201.
2. Run `make test` and `make sparkle`.
3. Run `../tools/deploy/deploy.sh . doctor`, then `../tools/deploy/deploy.sh . prepare`.
4. Inspect `dist/deploy/<version>/`: both DMGs, `appcast.xml`, `SHA256SUMS.txt`, the generated cask, and notarization records. The cask under `homebrew/Casks` is a template; the pipeline fills in final hashes.
5. Commit the source and configuration. Run `../tools/deploy/deploy.sh . publish` to push the source/tag, publish the verified GitHub release, and audit/commit/push the Homebrew cask.

The update feed is `https://github.com/elixirevo/pinshot/releases/latest/download/appcast.xml`. Upload it alongside both DMGs in each release. Never modify signed feed or package bytes after verification. The pipeline selects the correct architecture and verifies its signature, version, and hash before publication.

Existing 1.1.2 installations have no updater, so users need a one-time DMG or Homebrew upgrade to 1.2.0. Keep the same bundle identifier and Sparkle signing account for future updates.
