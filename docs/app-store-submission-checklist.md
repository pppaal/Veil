# App Store (iOS) Submission Readiness Checklist

_Snapshot at commit `5ce92f3`. Companion to `docs/production-deployment.md` and
`docs/deployment-readiness-review.md`._

**Bottom line: do not submit to the public App Store yet.** The hard blocker is
the external cryptographic audit — VEIL ships a *self-implemented* Signal-style
Double Ratchet (`apps/mobile/lib/src/core/crypto/lib_crypto_adapter.dart` on the
Dart `cryptography` package), **not** Signal's audited `libsignal`. Shipping
custom, un-audited crypto to real users is explicitly rejected by
`docs/audited-crypto-library-decision.md` (Candidate C: *Rejected*) and blocked
at API boot by `VEIL_AUDITED_CRYPTO_ATTESTED`.

The store-mechanics side, however, is in good shape — most items that usually
cause a review rejection are already handled.

## The gating path (in order)

1. **Adopt an audited crypto library.** Per the decision doc, the plan is a
   `libsignal`-class audited session library behind the existing `CryptoAdapter`
   boundary, bridged natively (Android Kotlin / iOS Swift / Flutter platform
   channel) — not reimplemented in Dart. See
   `docs/audited-crypto-adapter-execution.md`.
2. **External security + crypto audit** of the new adapter path. Hand off with
   `pnpm audit:handoff` (verified working — emits
   `artifacts/veil-audit-handoff-<sha>.tar.gz`). Outreach templates:
   `docs/audit-rfp-email-en.md`, firm shortlist in
   `docs/external-audit-firm-shortlist.md`.
3. **Remediate findings** and empty `docs/external-review-remediation-tracker.md`.
4. **Session-state migration** from the interim adapter to the audited one
   (`docs/crypto-session-state-migration.md`) — existing beta users' sessions
   must not break.
5. Only then set `VEIL_AUDITED_CRYPTO_ATTESTED=true` and submit.

## iOS store-mechanics status

| Item | State | Notes |
|---|---|---|
| Bundle ID | ✅ | `io.veil.mobile` set in `Runner.xcodeproj` |
| Export compliance flag | ✅ | `ITSAppUsesNonExemptEncryption = true` declared in `Info.plist` |
| Privacy manifest | ✅ | `ios/Runner/PrivacyInfo.xcprivacy` present |
| Android release signing | ✅ | Gated on `keystore.properties`; no debug-key fallback (build fails loud) |
| iOS distribution signing / provisioning | ☐ | Apple Developer account, distribution cert, App Store provisioning profile — operator step, not in repo |
| App Store Connect record | ☐ | App name, subtitle, category, age rating, screenshots (6.7" + 5.5" iPhone) |
| Encryption export **filing** | ☐ | Flag=true means Apple expects docs. File the annual US self-classification (and FR encryption declaration if distributing in France). The flag being declared avoids the review block; the *filing* is still an operator task |
| Privacy "Nutrition Label" | ☐ | Complete in App Store Connect. VEIL collects no message content; be precise about device identifiers / diagnostics actually collected |
| Real-device release QA | ☐ | `docs/production-deployment.md` §5: onboarding, chat, attachments, app lock (biometric/PIN), revoke, device transfer on physical iPhone |
| Push (APNs) | ☐ | `VEIL_PUSH_PROVIDER=none` today. APNs key + push privacy review (`docs/push-privacy-review-checklist.md`) before background notifications work |

## Review-rejection risks specific to VEIL

- **"No recovery" UX.** Losing the device permanently loses the conversation.
  Reviewers may flag this as data loss / broken functionality. Pre-empt it in
  App Review notes: state that it is an intentional privacy design, and make the
  in-app onboarding warning explicit and unmissable.
- **No account / no phone number.** Explain the device-bound identity model in
  review notes so it isn't mistaken for a broken sign-up flow.
- **Encryption.** With export compliance declared and filed, this should pass;
  keep the self-classification paperwork on hand.
- **Guideline 5.1 / data collection.** Keep the privacy label consistent with
  the metadata the server actually retains (call-record and prekey retention
  windows are configurable — see `env.schema.ts`).

## What is genuinely ready now

- Private beta over TLS (VPS or Cloudflare Tunnel) — see the deployment
  readiness review.
- Store-mechanics scaffolding (signing gates, export flag, privacy manifest,
  bundle IDs) — the parts that are easy to forget are done.

The dominant remaining work is **crypto (adopt audited lib → audit → remediate)**,
exactly as the repo's own decision docs prescribe. Everything else is standard
release checklist execution.
