import 'dart:convert';

import 'package:flutter/services.dart';

import 'crypto_engine.dart';
import 'lib_crypto_adapter.dart' show createDefaultCryptoAdapter;

/// Platform-channel adapter that delegates the cryptographic core to the
/// native `libsignal` bridge (Android Kotlin / iOS Swift) instead of the
/// self-implemented Dart Double Ratchet in [createDefaultCryptoAdapter].
///
/// STATUS: work-in-progress, Android-first. Opt in with
/// `--dart-define=VEIL_CRYPTO_ADAPTER=libsignal`. The default build keeps the
/// existing adapter, so this file does not change runtime behavior unless the
/// flag is set. The native side (`VeilCryptoBridge`) must be built and verified
/// on a real device before this path is trusted — it is pre-audit.
///
/// The wire-format JSON codecs ([keyBundles], [envelopeCodec]) are pure
/// serialization with no crypto, so they are reused verbatim from the existing
/// adapter; only identity, device-auth, messaging, and session bootstrap are
/// routed to native.
const kLibsignalAdapterId = 'libsignal-v1';

const _channel = MethodChannel('io.veil.crypto/bridge');

class CryptoBridgeException implements Exception {
  CryptoBridgeException({required this.code, this.message});

  /// Stable code from the channel contract:
  /// sessionNotFound | identityMismatch | decryptFailed | keyWipeRequired |
  /// bridgeUnavailable.
  final String code;
  final String? message;

  @override
  String toString() => 'CryptoBridgeException($code): $message';
}

Future<Map<String, dynamic>> _invoke(
  String method,
  Map<String, dynamic> args,
) async {
  try {
    final result = await _channel.invokeMapMethod<String, dynamic>(method, args);
    return result ?? const <String, dynamic>{};
  } on PlatformException catch (e) {
    throw CryptoBridgeException(code: e.code, message: e.message);
  }
}

String _b64(List<int> bytes) => base64Encode(bytes);

List<int> _unb64(String value) => base64Decode(value);

String _kindName(MessageKind kind) => kind.name;

MessageKind _kindFromName(String name) =>
    MessageKind.values.firstWhere((k) => k.name == name, orElse: () => MessageKind.text);

Map<String, dynamic> _keyBundleToMap(KeyBundle bundle) => <String, dynamic>{
      'userId': bundle.userId,
      'deviceId': bundle.deviceId,
      'handle': bundle.handle,
      'identityPublicKey': bundle.identityPublicKey,
      'signedPrekeyBundle': bundle.signedPrekeyBundle,
    };

Map<String, dynamic> _attachmentRefToMap(AttachmentReference ref) => <String, dynamic>{
      'attachmentId': ref.attachmentId,
      'storageKey': ref.storageKey,
      'contentType': ref.contentType,
      'sizeBytes': ref.sizeBytes,
      'sha256': ref.sha256,
      'encryptedKey': ref.encryptedKey,
      'nonce': ref.nonce,
      'algorithmHint': ref.algorithmHint,
    };

AttachmentReference _attachmentRefFromMap(Map<String, dynamic> map) => AttachmentReference(
      attachmentId: map['attachmentId'] as String,
      storageKey: map['storageKey'] as String,
      contentType: map['contentType'] as String,
      sizeBytes: (map['sizeBytes'] as num).toInt(),
      sha256: map['sha256'] as String,
      encryptedKey: map['encryptedKey'] as String,
      nonce: map['nonce'] as String,
      algorithmHint: map['algorithmHint'] as String?,
    );

SessionBootstrapMaterial _bootstrapMaterialFromMap(Map<String, dynamic> map) =>
    SessionBootstrapMaterial(
      sessionLocator: map['sessionLocator'] as String,
      sessionEnvelopeVersion: map['sessionEnvelopeVersion'] as String,
      requiresLocalPersistence: map['requiresLocalPersistence'] as bool? ?? true,
      sessionSchemaVersion: (map['sessionSchemaVersion'] as num?)?.toInt() ?? 1,
      localDeviceId: map['localDeviceId'] as String,
      remoteDeviceId: map['remoteDeviceId'] as String,
      remoteIdentityFingerprint: map['remoteIdentityFingerprint'] as String,
      auditHint: map['auditHint'] as String?,
    );

class LibsignalBridgeAdapter implements CryptoAdapter {
  LibsignalBridgeAdapter() : _codecSource = createDefaultCryptoAdapter();

  // Only the JSON codecs are reused from the existing adapter; the crypto path
  // below is fully native.
  final CryptoAdapter _codecSource;

  @override
  String get adapterId => kLibsignalAdapterId;

  @override
  final DeviceIdentityProvider identity = _BridgeIdentity();

  @override
  final DeviceAuthChallengeSigner deviceAuth = _BridgeDeviceAuth();

  @override
  KeyBundleCodec get keyBundles => _codecSource.keyBundles;

  @override
  CryptoEnvelopeCodec get envelopeCodec => _codecSource.envelopeCodec;

  @override
  final MessageCryptoEngine messaging = _BridgeMessaging();

  @override
  final ConversationSessionBootstrapper sessions = _BridgeSessions();
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
  Future<String> extractIdentityPublicKeyFromPrivateRef(String identityPrivateRef) async {
    final r = await _invoke('extractIdentityPublicKey', {
      'identityPrivateKeyRef': identityPrivateRef,
    });
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

class _BridgeMessaging implements MessageCryptoEngine {
  @override
  Future<CryptoEnvelope> encryptMessage({
    required String conversationId,
    required String senderDeviceId,
    required String recipientUserId,
    required String body,
    required MessageKind messageKind,
    required KeyBundle recipientBundle,
    DateTime? expiresAt,
    AttachmentReference? attachment,
  }) async {
    final r = await _invoke('encryptMessage', {
      'conversationId': conversationId,
      'senderDeviceId': senderDeviceId,
      'recipientUserId': recipientUserId,
      'plaintext': _b64(utf8.encode(body)),
      'messageKind': _kindName(messageKind),
      'recipientBundle': _keyBundleToMap(recipientBundle),
      'expiresAt': expiresAt?.toUtc().toIso8601String(),
      'attachment': attachment == null ? null : _attachmentRefToMap(attachment),
    });
    return CryptoEnvelope(
      version: r['version'] as String? ?? kLibsignalAdapterId,
      conversationId: conversationId,
      senderDeviceId: senderDeviceId,
      recipientUserId: recipientUserId,
      ciphertext: r['ciphertext'] as String,
      nonce: r['nonce'] as String? ?? '',
      messageKind: messageKind,
      expiresAt: expiresAt,
      attachment: attachment,
    );
  }

  @override
  Future<DecryptedMessage> decryptMessage(CryptoEnvelope envelope) async {
    final r = await _invoke('decryptMessage', {
      'version': envelope.version,
      'conversationId': envelope.conversationId,
      'senderDeviceId': envelope.senderDeviceId,
      'recipientUserId': envelope.recipientUserId,
      'ciphertext': envelope.ciphertext,
      'nonce': envelope.nonce,
      'messageKind': _kindName(envelope.messageKind),
    });
    final expiresIso = r['expiresAt'] as String?;
    return DecryptedMessage(
      body: utf8.decode(_unb64(r['plaintext'] as String)),
      messageKind: r['messageKind'] == null
          ? envelope.messageKind
          : _kindFromName(r['messageKind'] as String),
      expiresAt: expiresIso == null ? envelope.expiresAt : DateTime.tryParse(expiresIso),
      attachment: envelope.attachment,
    );
  }

  @override
  Future<AttachmentCipher> encryptAttachment({
    required String attachmentId,
    required String storageKey,
    required String contentType,
    required List<int> plaintext,
    required KeyBundle recipientBundle,
  }) async {
    final r = await _invoke('encryptAttachmentKey', {
      'attachmentId': attachmentId,
      'storageKey': storageKey,
      'contentType': contentType,
      'plaintext': _b64(plaintext),
      'recipientBundle': _keyBundleToMap(recipientBundle),
    });
    return AttachmentCipher(
      reference: _attachmentRefFromMap((r['reference'] as Map).cast<String, dynamic>()),
      ciphertext: _unb64(r['ciphertext'] as String),
    );
  }

  @override
  Future<List<int>> decryptAttachment({
    required AttachmentReference reference,
    required List<int> ciphertext,
    required String localIdentityPrivateRef,
  }) async {
    final r = await _invoke('decryptAttachmentKey', {
      'reference': _attachmentRefToMap(reference),
      'ciphertext': _b64(ciphertext),
      'localIdentityPrivateRef': localIdentityPrivateRef,
    });
    return _unb64(r['plaintext'] as String);
  }
}

class _BridgeSessions implements ConversationSessionBootstrapper {
  final Set<String> _bootstrapped = <String>{};

  @override
  Future<SessionBootstrapMaterial> bootstrapSession(SessionBootstrapRequest request) async {
    final r = await _invoke('bootstrapSession', {
      'conversationId': request.conversationId,
      'localDeviceId': request.localDeviceId,
      'localUserId': request.localUserId,
      'remoteUserId': request.remoteUserId,
      'remoteDeviceId': request.remoteDeviceId,
      'remoteIdentityPublicKey': request.remoteIdentityPublicKey,
      'remoteSignedPrekeyBundle': request.remoteSignedPrekeyBundle,
    });
    _bootstrapped.add(request.conversationId);
    return _bootstrapMaterialFromMap(r);
  }

  @override
  Future<SessionBootstrapMaterial> bootstrapSessionFromInbound(
    InboundSessionBootstrapRequest request,
  ) async {
    final r = await _invoke('bootstrapSessionFromInbound', {
      'conversationId': request.conversationId,
      'localDeviceId': request.localDeviceId,
      'localUserId': request.localUserId,
      'localIdentityPrivateRef': request.localIdentityPrivateRef,
      'remoteUserId': request.remoteUserId,
      'remoteDeviceId': request.remoteDeviceId,
      'remoteEphemeralPublicKey': _b64(request.remoteEphemeralPublicKey),
    });
    _bootstrapped.add(request.conversationId);
    return _bootstrapMaterialFromMap(r);
  }

  @override
  bool hasSessionFor(String conversationId) => _bootstrapped.contains(conversationId);

  @override
  Future<bool> forceRekeyNextSend(String conversationId) async {
    final r = await _invoke('forceRekey', {'conversationId': conversationId});
    return r['armed'] as bool? ?? false;
  }
}
