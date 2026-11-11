import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_adapter_registry.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/lib_crypto_adapter.dart';
import 'package:veil_mobile/src/core/crypto/libsignal_bridge_adapter.dart';
import 'package:veil_mobile/src/core/crypto/message_padding.dart';

// Dart-side contract tests for the libsignal bridge: every CryptoAdapter
// method maps to the documented channel method / fields, native responses
// are decoded into the boundary types, and native errors surface as typed
// failures (never a plaintext fallback). The native handlers themselves are
// verified on real toolchains (see docs/libsignal-migration-implementation.md §9).

String b64u(List<int> b) => base64Url.encode(b).replaceAll('=', '');
List<int> unb64u(String s) => base64Url.decode(s.padRight(s.length + ((4 - s.length % 4) % 4), '='));

/// Scripted stand-in for the Kotlin/Swift handler. Records every call and
/// "encrypts" by storing plaintext under an opaque handle, which is enough
/// to check the Dart plumbing end to end.
class _FakeNative {
  final List<MethodCall> calls = [];
  final Map<String, List<int>> vault = {};
  final Set<String> sessions = {};
  PlatformException? nextError;
  int counter = 0;

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    final err = nextError;
    if (err != null) {
      nextError = null;
      throw err;
    }
    final args = (call.arguments as Map).cast<String, dynamic>();
    switch (call.method) {
      case 'generateDeviceIdentity':
        return {
          'identityPublicKey': 'id-pub-${args['deviceId']}',
          'identityPrivateKeyRef': 'ref-${args['deviceId']}',
          'signedPrekeyBundle': 'bundle-${args['deviceId']}',
        };
      case 'extractIdentityPublicKey':
        return {'identityPublicKey': 'id-pub-from-${args['identityPrivateKeyRef']}'};
      case 'bootstrapSession':
        sessions.add(args['conversationId'] as String);
        return {'remoteIdentityFingerprint': 'fp-${args['remoteDeviceId']}'};
      case 'encryptMessage':
        if (!sessions.contains(args['conversationId'])) {
          throw PlatformException(code: 'sessionNotFound');
        }
        counter += 1;
        final handle = 'ct-$counter';
        vault[handle] = unb64u(args['plaintext'] as String);
        return {'ciphertext': handle, 'messageType': counter == 1 ? 3 : 2};
      case 'decryptMessage':
        final pt = vault[args['ciphertext']];
        if (pt == null) throw PlatformException(code: 'decryptFailed');
        sessions.add(args['conversationId'] as String);
        return {'plaintext': b64u(pt)};
      case 'encryptAttachmentKey':
        counter += 1;
        final handle = 'wk-$counter';
        vault[handle] = unb64u(args['attachmentKey'] as String);
        return {'wrappedKey': handle, 'wrapNonce': 'wn-$counter'};
      case 'decryptAttachmentKey':
        final k = vault[args['wrappedKey']];
        if (k == null) throw PlatformException(code: 'decryptFailed');
        return {'attachmentKey': b64u(k)};
      case 'wipeCryptoState':
        sessions.clear();
        vault.clear();
        return {'wiped': true};
    }
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(kLibsignalChannelName);
  late _FakeNative native;
  late LibsignalBridgeAdapter adapter;

  setUp(() {
    native = _FakeNative();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, native.handle);
    adapter = LibsignalBridgeAdapter();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('registry selects adapters by flag and fails loud on typos', () {
    expect(createCryptoAdapterFor('lib'), isA<LibCryptoAdapter>());
    expect(createCryptoAdapterFor('libsignal'), isA<LibsignalBridgeAdapter>());
    expect(createCryptoAdapterFor('libsignal').adapterId, kLibsignalAdapterId);
    expect(() => createCryptoAdapterFor('libsodium'), throwsArgumentError);
    // Default build stays on the in-Dart ratchet until the bridge is verified.
    expect(kCryptoAdapterSelection, 'lib');
  });

  test('identity generation maps to the channel and returns opaque refs', () async {
    final material = await adapter.identity.generateDeviceIdentity('dev-1');
    expect(material.identityPublicKey, 'id-pub-dev-1');
    expect(material.identityPrivateKeyRef, 'ref-dev-1');
    expect(material.signedPrekeyBundle, 'bundle-dev-1');
    expect(native.calls.single.method, 'generateDeviceIdentity');
    expect(native.calls.single.arguments, {'deviceId': 'dev-1'});

    final pub = await adapter.identity.extractIdentityPublicKeyFromPrivateRef('ref-dev-1');
    expect(pub, 'id-pub-from-ref-dev-1');
  });

  test('bootstrap → encrypt → decrypt round-trips through the bridge', () async {
    const bundle = KeyBundle(
      userId: 'user-b',
      deviceId: 'dev-b',
      handle: 'bob',
      identityPublicKey: 'id-pub-dev-b',
      signedPrekeyBundle: 'bundle-dev-b',
    );
    expect(adapter.sessions.hasSessionFor('conv-1'), isFalse);
    expect(
      () => adapter.messaging.encryptMessage(
        conversationId: 'conv-1',
        senderDeviceId: 'dev-a',
        recipientUserId: 'user-b',
        body: 'x',
        messageKind: MessageKind.text,
        recipientBundle: bundle,
      ),
      throwsStateError,
    );

    final material = await adapter.sessions.bootstrapSession(const SessionBootstrapRequest(
      conversationId: 'conv-1',
      localDeviceId: 'dev-a',
      localUserId: 'user-a',
      remoteUserId: 'user-b',
      remoteDeviceId: 'dev-b',
      remoteIdentityPublicKey: 'id-pub-dev-b',
      remoteSignedPrekeyBundle: 'bundle-dev-b',
    ));
    expect(material.requiresLocalPersistence, isFalse);
    expect(material.sessionSchemaVersion, kLibsignalSessionSchemaVersion);
    expect(material.remoteIdentityFingerprint, 'fp-dev-b');
    expect(material.sessionEnvelopeVersion, kLibsignalEnvelopeVersion);
    expect(adapter.sessions.hasSessionFor('conv-1'), isTrue);
    final bootstrapArgs = (native.calls.last.arguments as Map).cast<String, dynamic>();
    expect(bootstrapArgs['remoteSignedPrekeyBundle'], 'bundle-dev-b');
    expect(bootstrapArgs['remoteIdentityPublicKey'], 'id-pub-dev-b');

    final expires = DateTime.utc(2030, 1, 1);
    final envelope = await adapter.messaging.encryptMessage(
      conversationId: 'conv-1',
      senderDeviceId: 'dev-a',
      recipientUserId: 'user-b',
      body: 'hello libsignal',
      messageKind: MessageKind.text,
      recipientBundle: bundle,
      expiresAt: expires,
    );
    expect(envelope.version, kLibsignalEnvelopeVersion);
    expect(envelope.nonce, 'prekey'); // first message = PreKeySignalMessage
    expect(envelope.ciphertext, 'ct-1');
    final encArgs = (native.calls.last.arguments as Map).cast<String, dynamic>();
    expect(encArgs['remoteDeviceId'], 'dev-b');
    // Plaintext handed to native is the padded JSON payload — body never
    // appears unpadded or unstructured on the channel.
    final handed = unb64u(encArgs['plaintext'] as String);
    expect(handed.length, MessagePadding.bucketFor(handed.length));
    // Same inner payload codec as the lib adapter (pv 2).
    final inner = json.decode(utf8.decode(MessagePadding.unpad(handed))) as Map<String, dynamic>;
    expect(inner['pv'], 2);
    expect(inner['b'], 'hello libsignal');
    expect(inner['k'], 'text');
    expect(inner['x'], expires.millisecondsSinceEpoch);

    final second = await adapter.messaging.encryptMessage(
      conversationId: 'conv-1',
      senderDeviceId: 'dev-a',
      recipientUserId: 'user-b',
      body: 'again',
      messageKind: MessageKind.text,
      recipientBundle: bundle,
    );
    expect(second.nonce, 'signal'); // steady state = SignalMessage

    final decrypted = await adapter.messaging.decryptMessage(envelope);
    expect(decrypted.status, DecryptStatus.ok);
    expect(decrypted.body, 'hello libsignal');
    expect(decrypted.messageKind, MessageKind.text);
    expect(decrypted.expiresAt?.toUtc(), expires);
    final decArgs = (native.calls.last.arguments as Map).cast<String, dynamic>();
    expect(decArgs['messageType'], 3);
    expect(decArgs['senderDeviceId'], 'dev-a');

    // API envelope codec keeps the libsignal fields intact.
    final jsonEnv = adapter.envelopeCodec.encodeApiEnvelope(envelope);
    expect(jsonEnv['version'], 'libsignal-v1');
    expect(jsonEnv['nonce'], 'prekey');
    final back = adapter.envelopeCodec.decodeApiEnvelope(jsonEnv);
    expect(back.ciphertext, 'ct-1');
    expect(back.nonce, 'prekey');
  });

  test('native errors become placeholders, never plaintext or crashes', () async {
    const envelope = CryptoEnvelope(
      version: kLibsignalEnvelopeVersion,
      conversationId: 'conv-1',
      senderDeviceId: 'dev-b',
      recipientUserId: 'user-a',
      ciphertext: 'ct-unknown',
      nonce: 'signal',
      messageKind: MessageKind.text,
    );
    final failed = await adapter.messaging.decryptMessage(envelope);
    expect(failed.body, '[Decryption failed]');
    expect(failed.status, DecryptStatus.failed);
    expect(failed.failureReason, 'decryptFailed');

    native.nextError = PlatformException(code: 'sessionNotFound');
    final missing = await adapter.messaging.decryptMessage(envelope);
    expect(missing.body, '[Session not established — sync required]');
    expect(missing.status, DecryptStatus.sessionMissing);

    native.nextError = PlatformException(code: 'identityMismatch');
    final rejected = await adapter.messaging.decryptMessage(envelope);
    expect(rejected.body, '[Identity changed — verify safety number]');
    expect(rejected.status, DecryptStatus.identityRejected);

    // Unknown nonce tag = not a libsignal frame.
    const bogus = CryptoEnvelope(
      version: kLibsignalEnvelopeVersion,
      conversationId: 'conv-1',
      senderDeviceId: 'dev-b',
      recipientUserId: 'user-a',
      ciphertext: 'ct-1',
      nonce: 'AAAA',
      messageKind: MessageKind.text,
    );
    final invalid = await adapter.messaging.decryptMessage(bogus);
    expect(invalid.body, '[Unable to decrypt: invalid envelope]');
    expect(invalid.status, DecryptStatus.failed);

    // Identity generation has no safe fallback: typed exception.
    native.nextError = PlatformException(code: 'keyWipeRequired', message: 'store corrupt');
    await expectLater(
      adapter.identity.generateDeviceIdentity('dev-9'),
      throwsA(isA<CryptoBridgeException>().having((e) => e.code, 'code', 'keyWipeRequired')),
    );
  });

  test('missing native plugin surfaces as bridgeUnavailable', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await expectLater(
      adapter.identity.generateDeviceIdentity('dev-1'),
      throwsA(isA<CryptoBridgeException>().having((e) => e.code, 'code', 'bridgeUnavailable')),
    );
  });

  test('attachments: native wraps the key, Dart seals the blob, round-trip', () async {
    const bundle = KeyBundle(
      userId: 'user-b',
      deviceId: 'dev-b',
      handle: 'bob',
      identityPublicKey: 'id-pub-dev-b',
      signedPrekeyBundle: 'bundle-dev-b',
    );
    final plaintext = List<int>.generate(5000, (i) => i % 251);
    final cipher = await adapter.messaging.encryptAttachment(
      attachmentId: 'att-1',
      storageKey: 'k/att-1',
      contentType: 'image/png',
      plaintext: plaintext,
      recipientBundle: bundle,
    );
    expect(cipher.reference.algorithmHint, kLibsignalAttachmentAlgoHint);
    expect(cipher.reference.encryptedKey, startsWith('wk-'));
    expect(cipher.reference.nonce.split('.'), hasLength(2));
    expect(cipher.ciphertext.length, plaintext.length + 16);
    final wrapArgs = (native.calls.last.arguments as Map).cast<String, dynamic>();
    expect(wrapArgs['recipientSignedPrekeyBundle'], 'bundle-dev-b');
    expect(wrapArgs['recipientIdentityPublicKey'], 'id-pub-dev-b');

    final restored = await adapter.messaging.decryptAttachment(
      reference: cipher.reference,
      ciphertext: cipher.ciphertext,
      localIdentityPrivateRef: 'ref-dev-b',
    );
    expect(restored, plaintext);
    final unwrapArgs = (native.calls.last.arguments as Map).cast<String, dynamic>();
    expect(unwrapArgs['identityPrivateKeyRef'], 'ref-dev-b');
    expect(unwrapArgs['wrappedKey'], cipher.reference.encryptedKey);

    // Tampered blob is rejected before any key is unwrapped.
    final tampered = List<int>.from(cipher.ciphertext)..[0] ^= 1;
    final callsBefore = native.calls.length;
    await expectLater(
      adapter.messaging.decryptAttachment(
        reference: cipher.reference,
        ciphertext: tampered,
        localIdentityPrivateRef: 'ref-dev-b',
      ),
      throwsStateError,
    );
    expect(native.calls.length, callsBefore);
  });

  test('wipeCryptoState clears native state and local session hints', () async {
    await adapter.sessions.bootstrapSession(const SessionBootstrapRequest(
      conversationId: 'conv-1',
      localDeviceId: 'dev-a',
      localUserId: 'user-a',
      remoteUserId: 'user-b',
      remoteDeviceId: 'dev-b',
      remoteIdentityPublicKey: 'id-pub-dev-b',
      remoteSignedPrekeyBundle: 'bundle-dev-b',
    ));
    expect(adapter.sessions.hasSessionFor('conv-1'), isTrue);
    expect(await adapter.wipeCryptoState(), isTrue);
    expect(adapter.sessions.hasSessionFor('conv-1'), isFalse);
    expect(native.calls.last.method, 'wipeCryptoState');
    expect(native.calls.last.arguments, {'scope': 'all'});
  });
}
