# PinShot legal documents

The app owns the versioned plain-text documents in `Sources/Resources/en.lproj` and `Sources/Resources/ko.lproj`. They are adapted from `../tools/library/docs/legal/terms-template.{en,ko}.md`, `privacy-template.{en,ko}.md`, their README and privacy-template-guide.md, read on 2026-10-05.

The user supplied `elixirevo` and `elixirevo@gmail.com` for the operator and private contact. The text reflects the current free, direct-distribution app: no accounts, payments, cloud screenshot uploads, advertising or usage analytics; optional Sentry crash reports; local images/preferences/terms receipts; optional GitHub update connections and user-submitted Gmail/GitHub support. Paid/App Store template options were removed; Sentry uses the template’s optional crash-reporting variant. No business address, registration number, fixed provider-log retention period or particular governing-law jurisdiction was invented.

The default history limit deletes original history PNGs after a successful new save. The documents expressly describe this behavior and distinguish it from user-created copies, editor saves and macro saves. General resets preserve terms receipts and onboarding completion. Read-only document viewing does not imply agreement.

External sources checked during adaptation:

- [GitHub General Privacy Statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement): hosting, support submissions, connection information, international processing and provider-controlled retention.
- [Google Privacy Policy](https://policies.google.com/privacy): Gmail content, international processing and provider deletion/retention policies.
- [Sparkle customization](https://sparkle-project.org/documentation/customization/): separate check/download preferences and system-profile controls. The app explicitly sets `SUEnableSystemProfiling=false` and retains its existing signed feed/key.
- [Korean Personal Information Protection Act](https://www.law.go.kr/법령/개인정보보호법/제30조): the package's policy-structure reference.
- [Personal Information Dispute Mediation Committee](https://www.kopico.go.kr) and [KISA privacy center](https://privacy.kisa.or.kr): the template's external rights-remedy contacts.

Before a public release, the operator should verify any legally required identity/address disclosures and the actual support-account/provider retention and international-transfer arrangements. These are operator facts that source code cannot establish. The implementation and documents do not certify legal compliance. Publishing the documents, introducing a paid service, or adding remote data collection is a separate release decision.

Sentry update (privacy version 2026-10-05.1): optional, default-off fatal exception reporting through Functional Software, Inc., US region verified from the organization API. Default server scrubbing and project IP scrubbing are enabled. The SDK keeps at most 20 cache items and does not initialize on non-consenting launches; enabling later can send cached reports. The policy does not invent a fixed server retention duration: it identifies applicable project retention and provider deletion/backup criteria. Terms text and its acceptance version are unchanged. Previous privacy translations are preserved in `archive/2026-10-05/`.

Additional references: [Sentry Privacy Policy](https://sentry.io/privacy/), [Data Processing Addendum](https://sentry.io/legal/dpa/), package crash-only adapter and `docs/legal/privacy-template-guide.md`. End-to-end event content/receipt has not been tested by sending a crash.
