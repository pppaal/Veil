import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
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

SessionDecision _decide({
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
      expect(_decide(engineHasSession: false, session: _session()).action, SessionAction.bootstrap);
    });

    test('reuses a live session for the same device', () {
      final decision = _decide(session: _session());
      expect(decision.action, SessionAction.reuse);
      expect(decision.identityMismatch, isFalse);
    });

    test('reuses an engine session the preview never recorded', () {
      expect(_decide(session: null).action, SessionAction.reuse);
    });

    test('a changed remote device bootstraps', () {
      expect(
        _decide(session: _session(), bundle: _bundle(deviceId: 'dev-selene-2')).action,
        SessionAction.bootstrap,
      );
    });

    test('a session recorded for another local device bootstraps', () {
      expect(
        _decide(session: _session(localDeviceId: 'dev-old-phone')).action,
        SessionAction.bootstrap,
      );
    });

    test('a new identity key on the same device keeps the session and flags it', () {
      final decision = _decide(
        session: _session(),
        bundle: _bundle(identityPublicKey: 'ik-impostor'),
      );
      expect(decision.action, SessionAction.reuse);
      expect(decision.identityMismatch, isTrue);
    });

    test('a session without a recorded identity key cannot be compared', () {
      final decision = _decide(
        session: _session(remoteIdentityPublicKey: ''),
        bundle: _bundle(identityPublicKey: 'ik-anything'),
      );
      expect(decision.identityMismatch, isFalse);
    });
  });

  group('sendNeedsPeerBundle', () {
    test('steady-state sends never touch the directory', () {
      expect(
        sendNeedsPeerBundle(
          engineHasSession: true,
          rekeyArmed: false,
          conversation: _conversation(session: _session(), deviceId: 'dev-selene'),
        ),
        isFalse,
      );
      expect(
        sendNeedsPeerBundle(
          engineHasSession: true,
          rekeyArmed: false,
          conversation: _conversation(),
        ),
        isFalse,
      );
    });

    test('no session, an armed rekey or a changed device need the bundle', () {
      expect(
        sendNeedsPeerBundle(engineHasSession: false, rekeyArmed: false, conversation: _conversation()),
        isTrue,
      );
      expect(
        sendNeedsPeerBundle(
          engineHasSession: true,
          rekeyArmed: true,
          conversation: _conversation(session: _session()),
        ),
        isTrue,
      );
      expect(
        sendNeedsPeerBundle(
          engineHasSession: true,
          rekeyArmed: false,
          conversation: _conversation(session: _session(), deviceId: 'dev-selene-2'),
        ),
        isTrue,
      );
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
