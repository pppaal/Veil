# libsignal Migration — Implementation Guide

_Execution-level companion to `docs/audited-crypto-library-decision.md` (which
picks libsignal) and `docs/crypto-mobile-bridge-design.md` (which defines the
channel contract). This document is the concrete recipe: dependencies, drop-in
Dart bridge, native handler skeletons, migration, and a build-and-verify
checklist._

> **Status: code landed, opt-in only, native side never built.** The Dart
> bridge adapter, registry flag, Kotlin handler + Keystore-sealed stores, Swift
> handler + Keychain stores, the opt-in Gradle dependency and ProGuard rules
> are all in the tree (file list in §0). The Dart side is covered by
> `flutter analyze` + unit tests (`test/libsignal_bridge_adapter_test.dart`)
> and is what CI runs.
>
> **Default builds leave out the native bridge and the libsignal dependency.**
> On Android the bridge sources (`android/app/src/libsignal`) and
> `org.signal:libsignal-android` are compiled in only with
> `-Pveil.libsignal=true` (Gradle) or `--android-project-arg=veil.libsignal=true`
> (Flutter); otherwise a stub registrar (`android/app/src/nolibsignal`) is
> used. On iOS `Runner/Crypto/VeilCryptoBridge.swift` is not in the Runner
> target: opting in means adding it and the `LibSignalClient` package to the
> target and registering `VeilCryptoBridgePlugin` in `AppDelegate.swift`
> (the comment there has the line). Without the bridge, selecting
> `--dart-define=VEIL_CRYPTO_ADAPTER=libsignal` reports the adapter
> unavailable.
>
> **Neither bridge has ever been built into an app.** The Kotlin and Swift
> handlers have not been compiled or run: that needs an Android SDK and
> **macOS + Xcode**, neither of which exists on the Linux box this was written
> on. Every libsignal symbol the native code touches is marked
> `VERIFY(0.86.5)` — check each against the pinned release's API before the
> first device build (§9). The default adapter is the Dart ratchet. Do **not**
> flip `VEIL_AUDITED_CRYPTO_ATTESTED` based on this doc; it is pre-audit
> engineering.

## 0. What is in the tree

| Piece | Path | Verified how |
|---|---|---|
| Dart bridge adapter | `apps/mobile/lib/src/core/crypto/libsignal_bridge_adapter.dart` | analyze + 7 unit tests (mock channel) |
| Registry flag | `apps/mobile/lib/src/core/crypto/crypto_adapter_registry.dart` | unit test |
| Android handler | `apps/mobile/android/app/src/libsignal/kotlin/io/veil/mobile/crypto/VeilCryptoBridge.kt` (opt-in source set) | **not compiled** |
| Android stores | `…/src/libsignal/kotlin/io/veil/mobile/crypto/SealedSignalProtocolStore.kt`, `…/KeystoreSealedStore.kt` | **not compiled** |
| Android wiring | `MainActivity.kt` calls `LibsignalBridgeRegistrar` (the real one in `src/libsignal`, a no-op in `src/nolibsignal`); `app/build.gradle.kts` adds `org.signal:libsignal-android:0.86.5` and the `src/libsignal` source set only under `veil.libsignal=true`; `proguard-rules.pro` | default build: stub only; opt-in build **never compiled** |
| iOS handler + stores | `apps/mobile/ios/Runner/Crypto/VeilCryptoBridge.swift` | **not in the Runner target, not compiled**; guarded by `#if canImport(LibSignalClient)` |
| iOS wiring | none by default: `AppDelegate.swift` carries the registration line as a comment; the file, the SPM package and that line must be added (§2) | **not compiled** |
| Server allowlist | `packages/shared/src/domain/protocol.ts` accepts `libsignal-v1`; `signedPrekeyBundle` limit raised to 8 KiB for Kyber bundles | API unit tests |

### Decisions baked into the code (confirm or change before audit)

- **Wire format.** `CryptoEnvelope.ciphertext` = serialized libsignal
  `CiphertextMessage`; `CryptoEnvelope.nonce` = `prekey` or `signal` (the
  message type), because libsignal manages its own nonces and the server
  requires a non-empty nonce field. Envelope version `libsignal-v1`.
- **Inner payload stays in Dart.** `{body, kind, expiresAt, att}` JSON +
  `MessagePadding` is built in Dart and handed to native as bytes, same as
  today, so native is "bytes in, bytes out" and never parses app structure.
- **Key bundle (`signedPrekeyBundle`) v2 shape**: base64url JSON with
  `registrationId`, `signedPreKey{Id,,Signature}`, `kyberPreKey{Id,,Signature}`
  (Kyber-1024 last-resort, PQXDH) and one one-time `preKey`. `identityPublicKey`
  is the 33-byte libsignal-serialized identity key. Prekey *replenishment*
  (uploading more one-time prekeys as they are consumed) is not wired yet;
  the last-resort Kyber key keeps bundles usable meanwhile.
- **Addresses.** VEIL device ids are per-device UUIDs already, so every
  libsignal `ProtocolAddress` is `(deviceId, 1)`.
- **Identity ref.** `identityPrivateKeyRef` is the constant
  `veil-libsignal-identity-v1`; the real key pair lives only in the native
  store. `extractIdentityPublicKey` resolves it natively.
- **Trust model.** Stores are trust-on-first-use then pinned: a changed peer
  identity makes libsignal throw `UntrustedIdentityException`, mapped to
  `identityMismatch`, which the app surfaces as the Safety-Number-changed
  state. Keys are never auto-accepted after rotation.
- **Attachments.** Blob AES-256-GCM stays in Dart (`cryptography`); the
  content key is wrapped natively with ephemeral X25519 → HKDF → AES-GCM to
  the recipient's *signed prekey* (signature verified against their identity
  first). Wire shape `ephPub(33) || ct || tag` under hint `x25519-aes256gcm`,
  byte-compatible between Android and iOS.
- **Device auth.** Relay challenge signing keeps the pure-Dart Ed25519 signer;
  it authenticates to the server and is not message crypto.
- **Group Sender Keys under libsignal** are *not* wired: the sealer needs the
  local X25519 private key, which the bridge never exposes. Follow-up: add
  `sealGroupSenderKey` / `unsealGroupSenderKey` channel methods so sealing runs
  natively too (`app_state.dart` only builds the group coordinator when the
  Dart adapter is active).
- **Storage.** Android: AES-256-GCM key in AndroidKeyStore seals every record
  into SharedPreferences (no androidx.security dependency). iOS: Keychain,
  `AfterFirstUnlockThisDeviceOnly`, never iCloud-synced.

## Why this reduces audit scope

Today the ratchet is our own Dart code, so an external audit must review the
entire crypto core. After this migration the crypto core is `libsignal` —
already audited and battle-tested by Signal — and the review scope shrinks to
**our integration**: the platform-channel boundary, the secure-storage-backed
stores, key lifecycle on revoke/transfer/wipe, and the migration. That is a much
smaller, cheaper, more defensible audit.

## Important consequence: the wire format changes

`libsignal` uses its own message serialization (`PreKeySignalMessage`,
`SignalMessage`, `CiphertextMessage`), not VEIL's `veil-envelope-v1`. This is a
**clean cutover**, not a compatibility layer:

- The `CryptoEnvelope` version becomes e.g. `libsignal-v1`.
- Existing sessions and cached ciphertext from the old adapter are **not
  decryptable** by the new one. On upgrade, invalidate old session state and
  re-bootstrap (see "Migration"). This is acceptable under VEIL's no-recovery,
  device-bound model — there is no historical-message decryption guarantee
  across a crypto-core swap.
- Keep the old adapter available behind a flag during rollout so a build can be
  reverted without a data-format trap.

## 1. Library selection

| Platform | Package | Distribution |
|---|---|---|
| Android | `org.signal:libsignal-android` | Maven Central (prebuilt AAR with the Rust core) |
| iOS | `LibSignalClient` | Swift Package Manager or CocoaPods (prebuilt xcframework) |
| Rust core | `signalapp/libsignal` | source of truth; pin an exact release tag |

- **License:** libsignal is AGPL-3.0 — compatible with VEIL (AGPL-3.0-only).
- **Pinned: `0.86.5`** (latest on Maven Central at the time of writing;
  recorded in `docs/reproducible-builds.md`). Use the same tag for the Swift
  package. Confirm the exact Maven/SPM coordinates and
  symbol names against that release's README — the API is stable in shape but
  version-sensitive in detail, so treat the symbol names in the skeletons below
  as the well-known API, to be verified against your pinned tag.

## 2. Dependency wiring

**pubspec.yaml** — no new Dart crypto dep; the bridge is platform channels only.
Remove reliance on `cryptography` for the message path once cut over (keep it
only if still used elsewhere).

**android/app/build.gradle.kts** — already declares, behind the
`veil.libsignal` Gradle property (off by default):

```kotlin
if (veilLibsignal) {
    implementation("org.signal:libsignal-android:0.86.5")
}
```

**ios/Podfile** (or the app's SwiftPM manifest) — add:

```ruby
pod 'LibSignalClient', '~> <PINNED_VERSION>'
```

libsignal ships prebuilt binaries, so no Rust toolchain is needed for app
builds; it is needed only if you build libsignal from source for reproducibility.

## 3. Dart side — bridge adapter (drop-in)

New file `apps/mobile/lib/src/core/crypto/libsignal_bridge_adapter.dart`. It
implements the existing `CryptoAdapter` surface by delegating to a single
`MethodChannel('io.veil.crypto/bridge')`. Native owns all key/session bytes; Dart
holds only opaque refs and migration-safe metadata (per the bridge design).

```dart
import 'package:flutter/services.dart';
import 'crypto_engine.dart';

const _channel = MethodChannel('io.veil.crypto/bridge');

/// Adapter id surfaced to the registry and metrics. Distinct from
/// LibCryptoAdapter's 'lib-x3dh-x25519-aes256gcm-v4' (and the retired
/// 'lib-x25519-aes256gcm-v3') so mixed-version sessions are detectable.
const kLibsignalAdapterId = 'libsignal-v1';

class LibsignalBridgeAdapter implements CryptoAdapter {
  LibsignalBridgeAdapter();

  @override
  String get adapterId => kLibsignalAdapterId;

  @override
  final DeviceIdentityProvider identity = _BridgeIdentity();
  @override
  final DeviceAuthChallengeSigner deviceAuth = _BridgeDeviceAuth();
  @override
  final KeyBundleCodec keyBundles = _BridgeKeyBundleCodec();
  @override
  final CryptoEnvelopeCodec envelopeCodec = _BridgeEnvelopeCodec();
  @override
  final MessageCryptoEngine messaging = _BridgeMessaging();
  @override
  final ConversationSessionBootstrapper sessions = _BridgeSessions();
}

/// Central invoke helper. Maps native PlatformExceptions (stable `code`
/// strings from the channel contract) to typed Dart failures so app logic
/// never sees a raw libsignal error and never gets a plaintext fallback.
Future<Map<String, dynamic>> _invoke(
  String method,
  Map<String, dynamic> args,
) async {
  try {
    final res = await _channel.invokeMapMethod<String, dynamic>(method, args);
    return res ?? const {};
  } on PlatformException catch (e) {
    throw CryptoBridgeException(code: e.code, message: e.message);
  }
}

class CryptoBridgeException implements Exception {
  CryptoBridgeException({required this.code, this.message});
  final String code; // sessionNotFound | identityMismatch | decryptFailed | ...
  final String? message;
  @override
  String toString() => 'CryptoBridgeException($code): $message';
}

class _BridgeIdentity implements DeviceIdentityProvider {
  @override
  Future<DeviceIdentityMaterial> generateDeviceIdentity(String deviceId) async {
    final r = await _invoke('generateDeviceIdentity', {'deviceId': deviceId});
    return DeviceIdentityMaterial(
      identityPublicKey: r['identityPublicKey'] as String,
      identityPrivateKeyRef: r['identityPrivateKeyRef'] as String,
      signedPrekeyBundle: r['signedPrekeyBundle'] as String,
    );
  }

  @override
  Future<String> extractIdentityPublicKeyFromPrivateRef(String ref) async {
    final r = await _invoke('extractIdentityPublicKey', {'identityPrivateKeyRef': ref});
    return r['identityPublicKey'] as String;
  }
}

class _BridgeDeviceAuth implements DeviceAuthChallengeSigner {
  @override
  Future<DeviceAuthKeyMaterial> generateAuthKeyMaterial() async {
    final r = await _invoke('generateAuthKeyMaterial', const {});
    return DeviceAuthKeyMaterial(
      publicKey: r['publicKey'] as String,
      privateKey: r['privateKey'] as String,
    );
  }

  @override
  Future<String> signChallenge({
    required String challenge,
    required DeviceAuthKeyMaterial keyMaterial,
  }) async {
    final r = await _invoke('signChallenge', {
      'challenge': challenge,
      'privateKey': keyMaterial.privateKey,
    });
    return r['signature'] as String;
  }
}

// _BridgeMessaging, _BridgeSessions, _BridgeKeyBundleCodec, _BridgeEnvelopeCodec
// follow the same shape: each abstract method → one _invoke(...) call whose
// method name and fields match the "Channel method contract" table in
// docs/crypto-mobile-bridge-design.md. encryptMessage returns a CryptoEnvelope
// built from {version, ciphertext, header}; decryptMessage returns a
// DecryptedMessage from {body, messageKind, expiresAt, attachment}. Attachment
// key wrap/unwrap map to encryptAttachmentKey/decryptAttachmentKey. Session
// bootstrap maps to processPreKeyBundle on the native side.
```

> The codec classes (`KeyBundleCodec`, `CryptoEnvelopeCodec`) are pure Dart
> (JSON ↔ model) and can largely be **reused from the existing adapter** — they
> don't touch crypto, only the API envelope shape. Only the `version` string and
> the ciphertext bytes' meaning change.

## 4. Android — Kotlin handler skeleton

`android/app/src/main/kotlin/io/veil/mobile/crypto/VeilCryptoBridge.kt`. Wire it
in `MainActivity.configureFlutterEngine`:

```kotlin
MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "io.veil.crypto/bridge")
    .setMethodCallHandler(VeilCryptoBridge(applicationContext))
```

```kotlin
// Uses org.signal.libsignal.protocol.* — verify names against the pinned version.
class VeilCryptoBridge(context: Context) : MethodChannel.MethodCallHandler {
    // Stores MUST be backed by hardware-backed encrypted storage (Keystore +
    // EncryptedSharedPreferences / SQLCipher). Native owns all session bytes.
    private val identityStore: IdentityKeyStore = SecureIdentityStore(context)
    private val sessionStore: SessionStore = SecureSessionStore(context)
    private val preKeyStore: PreKeyStore = SecurePreKeyStore(context)
    private val signedPreKeyStore: SignedPreKeyStore = SecureSignedPreKeyStore(context)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "generateDeviceIdentity" -> result.success(generateIdentity(call))
                "bootstrapSession" -> result.success(bootstrap(call))          // SessionBuilder.process(PreKeyBundle)
                "encryptMessage" -> result.success(encrypt(call))              // SessionCipher.encrypt
                "decryptMessage" -> result.success(decrypt(call))              // SessionCipher.decrypt(PreKeySignalMessage|SignalMessage)
                "encryptAttachmentKey" -> result.success(wrapAttachmentKey(call))
                "decryptAttachmentKey" -> result.success(unwrapAttachmentKey(call))
                "hasSession" -> result.success(mapOf("present" to hasSession(call)))
                "wipeCryptoState" -> result.success(mapOf("wiped" to wipe(call)))
                // generateAuthKeyMaterial / signChallenge / extractIdentityPublicKey ...
                else -> result.notImplemented()
            }
        } catch (e: NoSessionException) {
            result.error("sessionNotFound", e.message, null)
        } catch (e: UntrustedIdentityException) {
            result.error("identityMismatch", e.message, null)
        } catch (e: Exception) {
            result.error("decryptFailed", e.message, null) // never leak plaintext / never fall through
        }
    }
    // generateIdentity(): IdentityKeyPair + registrationId + signed prekey +
    //   one-time prekeys → return public identity + opaque private ref + bundle.
    // bootstrap(): build PreKeyBundle from the peer's directory bundle, run
    //   SessionBuilder(stores, address).process(bundle); persist via stores.
    // encrypt()/decrypt(): SessionCipher(stores, address); serialize/parse the
    //   CiphertextMessage bytes as the envelope ciphertext.
}
```

## 5. iOS — Swift handler skeleton

`ios/Runner/Crypto/VeilCryptoBridge.swift`, registered in `AppDelegate`:

```swift
let channel = FlutterMethodChannel(name: "io.veil.crypto/bridge",
                                   binaryMessenger: controller.binaryMessenger)
let bridge = VeilCryptoBridge()
channel.setMethodCallHandler { call, result in bridge.handle(call, result) }
```

```swift
import LibSignalClient // verify product/module name against the pinned version

final class VeilCryptoBridge {
  // Stores backed by Keychain / Secure Enclave; native owns all session bytes.
  private let stores = SecureSignalStores()

  func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    do {
      switch call.method {
      case "generateDeviceIdentity": result(try generateIdentity(call))
      case "bootstrapSession":       result(try bootstrap(call))   // processPreKeyBundle
      case "encryptMessage":         result(try encrypt(call))     // signalEncrypt
      case "decryptMessage":         result(try decrypt(call))     // signalDecrypt / signalDecryptPreKey
      case "encryptAttachmentKey":   result(try wrapAttachmentKey(call))
      case "decryptAttachmentKey":   result(try unwrapAttachmentKey(call))
      case "hasSession":             result(["present": try hasSession(call)])
      case "wipeCryptoState":        result(["wiped": try wipe(call)])
      default:                       result(FlutterMethodNotImplemented)
      }
    } catch SignalError.untrustedIdentity { result(FlutterError(code: "identityMismatch", message: nil, details: nil)) }
      catch { result(FlutterError(code: "decryptFailed", message: "\(error)", details: nil)) }
  }
}
```

## 6. Registry wiring (both adapters coexist)

Change `crypto_adapter_registry.dart` to select by a compile-time flag so the
old adapter stays the default until the new path is verified on real devices:

```dart
import 'crypto_engine.dart';
import 'lib_crypto_adapter.dart' as lib_adapter;
import 'libsignal_bridge_adapter.dart';

// --dart-define=VEIL_CRYPTO_ADAPTER=libsignal to opt in.
const _selected = String.fromEnvironment('VEIL_CRYPTO_ADAPTER', defaultValue: 'lib');

CryptoAdapter createConfiguredCryptoAdapter() {
  switch (_selected) {
    case 'libsignal':
      return LibsignalBridgeAdapter();
    case 'lib':
    default:
      return lib_adapter.createDefaultCryptoAdapter();
  }
}
```

## 7. Migration (session-state)

- On first launch of a libsignal build, detect the stored adapter id. If it is
  a `LibCryptoAdapter` id (`lib-x3dh-x25519-aes256gcm-v4`, or the retired
  `lib-x25519-aes256gcm-v3`), **drop all persisted session snapshots** and
  clear the skipped-key stash — do not attempt to convert them.
- Force re-bootstrap: next outbound message to each conversation runs
  `bootstrapSession`; inbound `PreKeySignalMessage` runs
  `bootstrapSessionFromInbound`.
- `remoteIdentityFingerprint` mismatch must force re-bootstrap and surface a
  Safety-Number-changed prompt (existing screen).
- **No migration path may introduce recovery semantics** — dropping old sessions
  is correct here, not a bug.
- Device transfer / revoke / logout must call `wipeCryptoState(all)` so native
  session bytes and identity refs are cleared, matching current behavior.

## 8. Test plan (Gate: no merge to default without these)

- **Dart adapter tests** — mock the MethodChannel, assert each `CryptoAdapter`
  method maps to the right channel call and decodes responses (mirrors the
  existing adapter's unit tests).
- **Android + iOS native integration tests** — round-trip encrypt/decrypt,
  prekey bootstrap, identity-mismatch rejection, wipe.
- **Cross-device interop fixtures** — extend `docs/crypto-interoperability-fixtures.md`:
  a message encrypted on Android decrypts on iOS and vice versa.
- **Transfer / revoke retests** after enabling libsignal (device-bound identity,
  old-device-required join must still hold).
- **Migration test** — an app upgraded from the old adapter clears old sessions
  and re-bootstraps cleanly.
- CI `pnpm ci:mobile` (codegen + analyze + test) must stay green on the Dart side
  before the flag is ever defaulted on.

## 9. Build & verify checklist (run on a real toolchain)

```bash
# Android (no Mac needed):
cd apps/mobile
flutter pub get
flutter analyze                                   # Dart bridge must be clean
flutter test                                      # adapter unit tests
# Without --android-project-arg the bridge and libsignal are left out and the
# adapter reports itself unavailable.
flutter build apk --dart-define=VEIL_CRYPTO_ADAPTER=libsignal \
  --android-project-arg=veil.libsignal=true
# install on two Android devices, exchange messages end-to-end

# iOS (needs macOS + Xcode). First, in Xcode: add Runner/Crypto/VeilCryptoBridge.swift
# and the LibSignalClient package (§2) to the Runner target, and uncomment the
# VeilCryptoBridgePlugin registration in AppDelegate.swift.
flutter build ios --dart-define=VEIL_CRYPTO_ADAPTER=libsignal
# run on two devices; verify Safety Numbers + attachments + transfer/revoke
```

## 10. Rollout & rollback

1. Land the code with the flag **off** (default stays the old adapter) so CI and
   normal builds are unaffected. Done: default builds leave out the native
   bridge and the libsignal dependency on both platforms; opting in takes
   `-Pveil.libsignal=true` / `--android-project-arg=veil.libsignal=true` on
   Android and the Xcode steps in §9 on iOS. Neither opt-in build has been
   produced yet.
2. Dogfood `--dart-define=VEIL_CRYPTO_ADAPTER=libsignal` on real devices; run the
   interop + migration tests.
3. Flip the default to `libsignal` only after interop and migration pass on both
   platforms. Keep the old adapter one release for rollback.
4. Update the audit packet (`docs/external-security-review-packet.md`) to point
   the review at the **integration**, not a custom crypto core, then hand off.
5. `VEIL_AUDITED_CRYPTO_ATTESTED=true` remains gated on the external audit of the
   integration passing — unchanged by this migration.

## Related docs

- [audited-crypto-library-decision.md](docs/audited-crypto-library-decision.md)
- [crypto-mobile-bridge-design.md](docs/crypto-mobile-bridge-design.md)
- [audited-crypto-adapter-execution.md](docs/audited-crypto-adapter-execution.md)
- [crypto-session-state-migration.md](docs/crypto-session-state-migration.md)
- [crypto-interoperability-fixtures.md](docs/crypto-interoperability-fixtures.md)
