import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/util/base64url.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/session_policy.dart';

ConversationSessionState _session({
  String remoteDeviceId = 'dev-selene',
  String localDeviceId = 'dev-local',
  String remoteIdentityPublicKey = 'ik-selene',
}) {
  return ConversationSessionState(
    sessionLocator: 'session://conv-1',
    sessionEnvelopeVersion: 'veil-envelope-v1',
    requiresLocalPersistence: true,
    sessionSchemaVersion: 3,
    localDeviceId: localDeviceId,
    remoteDeviceId: remoteDeviceId,
    remoteIdentityFingerprint: 'fp',
    bootstrappedAt: DateTime.utc(2026, 4, 1),
    remoteIdentityPublicKey: remoteIdentityPublicKey,
  );
}

KeyBundle _bundle({String deviceId = 'dev-selene', String identityPublicKey = 'ik-selene'}) {
  return KeyBundle(
    userId: 'user-selene',
    deviceId: deviceId,
    handle: 'selene',
    identityPublicKey: identityPublicKey,
    signedPrekeyBundle: 'spk',
  );
}

ConversationPreview _conversation({ConversationSessionState? session, String deviceId = ''}) {
  return ConversationPreview(
    id: 'conv-1',
    peerHandle: 'selene',
    peerDisplayName: null,
    recipientBundle: _bundle(deviceId: deviceId),
    lastEnvelope: null,
    updatedAt: DateTime.utc(2026, 4, 1),
    sessionState: session,
  );
}

SessionAction _decide({
  bool engineHasSession = true,
  ConversationSessionState? session,
  KeyBundle? bundle,
}) {
  return decideSession(
    engineHasSession: engineHasSession,
    session: session,
    localDeviceId: 'dev-local',
    bundle: bundle ?? _bundle(),
  );
}

void main() {
  group('decideSession', () {
    test('bootstraps only when the engine has no session', () {
      expect(_decide(engineHasSession: false, session: _session()), SessionAction.bootstrap);
    });

    test('reuses a live session for the same device', () {
      expect(_decide(session: _session()), SessionAction.reuse);
    });

    test('reuses an engine session the preview never recorded', () {
      expect(_decide(session: null), SessionAction.reuse);
    });

    test('a changed remote device bootstraps', () {
      expect(
        _decide(session: _session(), bundle: _bundle(deviceId: 'dev-selene-2')),
        SessionAction.bootstrap,
      );
    });

    test('a session recorded for another local device bootstraps', () {
      expect(
        _decide(session: _session(localDeviceId: 'dev-old-phone')),
        SessionAction.bootstrap,
      );
    });

    test('an accepted new identity key for the same device bootstraps', () {
      expect(
        _decide(session: _session(), bundle: _bundle(identityPublicKey: 'ik-reinstalled')),
        SessionAction.bootstrap,
      );
    });

    test('the same identity key spelled with padding is not a new key', () {
      final key = List<int>.generate(32, (i) => i);
      expect(base64Url.encode(key), endsWith('='));
      expect(
        _decide(
          session: _session(remoteIdentityPublicKey: base64UrlNoPadEncode(key)),
          bundle: _bundle(identityPublicKey: base64Url.encode(key)),
        ),
        SessionAction.reuse,
      );
    });

    test('a session without a recorded identity key is reused', () {
      expect(
        _decide(session: _session(remoteIdentityPublicKey: ''), bundle: _bundle(identityPublicKey: 'ik-anything')),
        SessionAction.reuse,
      );
    });
  });

  group('keepSession', () {
    test('pins the served identity key on a session that has none yet', () {
      final conversation = _conversation(session: _session(remoteIdentityPublicKey: ''));
      final served = _bundle(deviceId: 'dev-selene', identityPublicKey: 'ik-selene');

      final kept = keepSession(conversation, served);

      expect(kept.sessionState!.remoteIdentityPublicKey, 'ik-selene');
      expect(kept.sessionState!.sessionLocator, 'session://conv-1');
      expect(kept.recipientBundle, same(served));
    });

    test('an engine session the preview never recorded takes the served bundle', () {
      final conversation = _conversation();
      final served = _bundle(deviceId: 'dev-selene');

      final kept = keepSession(conversation, served);

      expect(kept.sessionState, isNull);
      expect(kept.recipientBundle, same(served));
    });
  });

  group('comesFromNewPeerDevice', () {
    CryptoEnvelope frameFrom(String senderDeviceId) => CryptoEnvelope(
          version: 'veil-envelope-v1',
          conversationId: 'conv-1',
          senderDeviceId: senderDeviceId,
          recipientUserId: 'user-local',
          ciphertext: 'c',
          nonce: 'n',
          messageKind: MessageKind.text,
        );

    test('a frame from another peer device signals a move', () {
      expect(
        comesFromNewPeerDevice(_conversation(session: _session()), frameFrom('dev-selene-2'), localDeviceId: 'dev-local'),
        isTrue,
      );
    });

    test('frames from the bound device, from this device or without a session do not', () {
      final conversation = _conversation(session: _session());
      expect(comesFromNewPeerDevice(conversation, frameFrom('dev-selene'), localDeviceId: 'dev-local'), isFalse);
      expect(comesFromNewPeerDevice(conversation, frameFrom('dev-local'), localDeviceId: 'dev-local'), isFalse);
      expect(comesFromNewPeerDevice(conversation, frameFrom(''), localDeviceId: 'dev-local'), isFalse);
      expect(comesFromNewPeerDevice(_conversation(), frameFrom('dev-selene-2'), localDeviceId: 'dev-local'), isFalse);
    });

    test('group frames never do', () {
      final group = _conversation(session: _session()).copyWith(type: ConversationType.group);
      expect(comesFromNewPeerDevice(group, frameFrom('dev-selene-2'), localDeviceId: 'dev-local'), isFalse);
    });
  });

  test('sessionStateFromMaterial records the identity key it was bootstrapped with', () {
    const material = SessionBootstrapMaterial(
      sessionLocator: 'session://conv-1',
      sessionEnvelopeVersion: 'veil-envelope-v1',
      requiresLocalPersistence: true,
      sessionSchemaVersion: 3,
      localDeviceId: 'dev-local',
      remoteDeviceId: 'dev-selene',
      remoteIdentityFingerprint: 'fp',
      auditHint: 'hint',
    );

    final state = sessionStateFromMaterial(material, remoteIdentityPublicKey: 'ik-selene');

    expect(state.remoteIdentityPublicKey, 'ik-selene');
    expect(state.remoteDeviceId, 'dev-selene');
    expect(state.sessionSchemaVersion, 3);
    expect(state.auditHint, 'hint');
  });
}
