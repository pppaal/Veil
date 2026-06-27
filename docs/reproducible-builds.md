# VEIL — Reproducible Builds

VEIL is AGPL open source. That only means something if the app users
install can be shown to come from *this* source — otherwise "open source"
is a claim, not a verifiable fact. This document is the process for
rebuilding the Android app from a tagged commit and confirming it matches
the published artifact, plus the determinism prerequisites that make it
possible.

Status: **prerequisites in place, full bit-exactness pending hardware
validation.** The toolchain is pinned (below) and a verification harness is
provided; the remaining work is running that harness on release hardware
and publishing expected hashes per release. Do not claim "reproducible
builds" as done until that runs green for a tagged release.

## Why it matters

A user (or a journalist, or an auditor) should be able to take the APK from
the Play Store, rebuild from the matching git tag, and get the same bytes —
proving the binary wasn't backdoored between source and store. This is the
trust substrate the rest of VEIL's security claims lean on: there's little
point in a great ratchet if the shipped binary can't be tied to the
reviewed source.

## Pinned toolchain (the hard prerequisites)

Reproducibility requires every input to be fixed:

| Input | Pin | Where |
| --- | --- | --- |
| Flutter SDK | **3.44.4** (stable) | `.github/workflows/ci.yml` (`flutter-version`) |
| Dart SDK | bundled with Flutter 3.44.4 | transitively pinned |
| Android Gradle Plugin | `8.11.1` | `android/settings.gradle.kts` |
| Kotlin | `2.2.20` | `android/settings.gradle.kts` |
| pnpm | `10.28.0` | `.github/workflows/ci.yml` |
| Dart deps | exact | `pubspec.lock` (committed) |

The Flutter version is the one that previously floated: CI used
`channel: stable` with no version, so every run built with whatever stable
was current — which both broke reproducibility and caused SDK-drift
analyzer failures. It is now pinned. **Bump it deliberately**, in the same
commit that updates this table.

## How to verify (third party)

1. `git checkout <release tag>`.
2. Install Flutter **3.44.4** exactly (e.g. via `fvm install 3.44.4`).
3. `cd apps/mobile && flutter pub get`.
4. `flutter build appbundle --release` (you'll need an upload keystore; the
   *content* reproducibility is checked with signatures excluded — see
   below — because Play App Signing re-signs anyway).
5. Compare against the published artifact with the harness:
   `scripts/verify-reproducible-build.sh <your.aab> <published.aab>`.

The harness normalizes out the parts that are *expected* to differ (the
APK-signing block under `META-INF/`, and zip entry timestamps) and
sha256-compares the rest. A match proves the compiled Dart/Kotlin/native
code and resources are identical.

## Known non-determinism to control

These are the usual sources; the harness normalizes the first two and the
toolchain pins address the rest:

- **Zip entry timestamps** — normalized in the harness; for true on-disk
  determinism set `SOURCE_DATE_EPOCH` to the tag's commit time at build.
- **Signing block** — excluded (Play re-signs via App Signing).
- **Toolchain version skew** — fixed by the pins above.
- **Absolute paths / build-host leakage** — build in a clean checkout at a
  fixed path (the harness flags any embedded build-path strings).
- **R8/dexing ordering** — deterministic for a fixed AGP/R8 version (pinned).

## Next steps

- [ ] Run `verify-reproducible-build.sh` on two independent clean builds of
      a tagged release; resolve any diffs it surfaces.
- [ ] Publish expected normalized hashes alongside each GitHub release.
- [ ] Set `SOURCE_DATE_EPOCH` from the commit timestamp in the release build
      to remove timestamp normalization entirely.
- [ ] Once green for a release, update the Status line above and add the
      badge/claim to the README.
