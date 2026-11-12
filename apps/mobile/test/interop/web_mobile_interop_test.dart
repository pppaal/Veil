// Cross-implementation interoperability of the two protocol-v2 clients: the
// mobile adapter (LibCryptoAdapter) and the web demo's modules
// (apps/web-demo/src), which apps/web-demo/interop/web-peer.mjs runs under
// Node. Each client's known-answer tests replay the shared vectors on their
// own; here the two implementations exchange real frames in both
// directions, through a stand-in relay and key directory, so a change that
// keeps one client self-consistent but breaks the other fails CI.
//
// Every id and every delivery order is fixed; only key material is fresh.
@Timeout(Duration(seconds: 30))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:veil_mobile/src/core/crypto/bytes.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/lib_crypto_adapter.dart';
import 'package:veil_mobile/src/core/crypto/x3dh/identity_keys.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/reactions.dart';
import 'package:veil_mobile/src/features/security/domain/safety_numbers.dart';

// docs/crypto-envelope-spec.md, "Frame" and "X3DH": a frame starts
// 0x02 || type, and a PreKey frame's 168-byte header ends with the one-time
// prekey id, 0xFFFFFFFF when none was claimed.
const _frameVersion = 0x02;
const _preKeyFrame = 0x01;
const _normalFrame = 0x02;
const _oneTimePrekeyIdOffset = 2 + 164;
const _noOneTimePrekey = 0xFFFFFFFF;

var _lastId = 0;

/// The next fixed UUID v4 (users, devices, conversations, attachments).
String _nextId() => '00000000-0000-4000-8000-${(++_lastId).toRadixString(16).padLeft(12, '0')}';

Uint8List _frame(Map<String, dynamic> envelope) => b64uDecode(envelope['ciphertext'] as String);

int _frameType(Map<String, dynamic> envelope) {
  final frame = _frame(envelope);
  expect(frame[0], _frameVersion);
  return frame[1];
}

int _oneTimePrekeyId(Map<String, dynamic> envelope) => readU32be(_frame(envelope), _oneTimePrekeyIdOffset);

/// What the relay stores of a posted envelope and serves back
/// (ConversationMessageSummary): routing fields, ciphertext, an attachment
/// reduced to its id, and the expiry. The recipient is not stored.
Map<String, dynamic> _relay(Map<String, dynamic> posted) {
  final attachment = posted['attachment'] as Map<String, dynamic>?;
  return {
    for (final field in ['version', 'conversationId', 'senderDeviceId', 'ciphertext', 'nonce', 'messageType'])
      field: posted[field],
    'attachment': attachment == null ? null : {'attachmentId': attachment['attachmentId']},
    'expiresAt': posted['expiresAt'],
  };
}

/// apps/web-demo/interop/web-peer.mjs, seen from the mobile package root
/// that `flutter test` runs in. Null when no web demo sits next to the
/// mobile app: scripts/flutterw.mjs tests a copy of apps/mobile alone on
/// Windows.
File? _webPeerScript() {
  final script = File(p.normalize(p.join(Directory.current.path, '..', 'web-demo', 'interop', 'web-peer.mjs')));
  return script.existsSync() ? script : null;
}

/// The web peer process, driven by one JSON line per request.
class _WebPeerProcess {
  _WebPeerProcess._(this._process) {
    _process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(_onLine);
    _process.stderr.transform(utf8.decoder).listen(_stderr.write);
    // A crashed peer fails every call still waiting instead of hanging the
    // test until it times out.
    unawaited(_process.exitCode.then((code) {
      for (final pending in _pending.values) {
        pending.completeError(StateError('web peer exited with code $code\n$_stderr'));
      }
      _pending.clear();
    }));
  }

  final Process _process;
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  final _stderr = StringBuffer();
  var _lastRequest = 0;

  static Future<_WebPeerProcess> start(File script) async =>
      _WebPeerProcess._(await Process.start('node', [script.path]));

  void _onLine(String line) {
    final response = json.decode(line) as Map<String, dynamic>;
    final pending = _pending.remove(response['id']);
    if (pending == null) return;
    if (response['error'] != null) {
      pending.completeError(StateError('web peer: ${response['error']}'));
    } else {
      pending.complete((response['result'] as Map).cast<String, dynamic>());
    }
  }

  Future<Map<String, dynamic>> call(String op, Map<String, dynamic> arguments) {
    final id = ++_lastRequest;
    final response = Completer<Map<String, dynamic>>();
    _pending[id] = response;
    _process.stdin.writeln(json.encode({'id': id, 'op': op, ...arguments}));
    return response.future;
  }

  Future<void> close() async {
    await _process.stdin.close();
    await _process.exitCode;
  }
}

/// A decrypt result in the status names both clients share.
class _Opened {
  const _Opened(this.status, this.reason, this.body);

  final String status;
  final String? reason;
  final String body;
}

void _expectOpened(_Opened opened, String body) {
  expect(opened.status, 'ok', reason: 'failed to open "$body": ${opened.reason}');
  expect(opened.body, body);
}

/// One registered device of either client.
abstract class _Client {
  String get userId;
  String get deviceId;
  String get identityPublicKey;
  String get signedPrekeyBundle;

  /// The one-time prekeys a device uploads (POST /prekeys wire form).
  Future<List<Map<String, dynamic>>> uploadOneTimePrekeys();

  Future<bool> holdsOneTimePrekey(int keyId);

  /// Starts a session from [peer]'s key-directory entry.
  Future<void> bootstrap(String conversationId, _Client peer, Map<String, dynamic> entry);

  /// A text message as relayed to [to].
  Future<Map<String, dynamic>> sendText(String conversationId, _Client to, String body);

  Future<_Opened> receive(Map<String, dynamic> relayed);
}

/// [device] as the mobile adapter takes a recipient.
KeyBundle _keyBundle(_Client device) => KeyBundle(
    userId: device.userId,
    deviceId: device.deviceId,
    handle: '',
    identityPublicKey: device.identityPublicKey,
    signedPrekeyBundle: device.signedPrekeyBundle);

/// The key directory's entry for [device] (KeysResponse.devices[i]). With
/// [claim] it hands out the second one-time prekey the device uploaded, so a
/// responder that found its key by anything but the id would pick the wrong
/// one.
Future<Map<String, dynamic>> _directoryEntry(_Client device, {required bool claim}) async => {
      'deviceId': device.deviceId,
      'identityPublicKey': device.identityPublicKey,
      'signedPrekeyBundle': device.signedPrekeyBundle,
      'isActive': true,
      'oneTimePrekey': claim ? (await device.uploadOneTimePrekeys())[1] : null,
    };

class _WebClient implements _Client {
  _WebClient._(this._peer, this.name, this.userId, this.deviceId, this.identityPublicKey, this.signedPrekeyBundle);

  final _WebPeerProcess _peer;
  final String name;
  @override
  final String userId;
  @override
  final String deviceId;
  @override
  final String identityPublicKey;
  @override
  final String signedPrekeyBundle;

  static Future<_WebClient> create(_WebPeerProcess peer) async {
    final userId = _nextId();
    final deviceId = _nextId();
    final name = 'web-$deviceId';
    final published = await peer.call('create', {'name': name, 'userId': userId, 'deviceId': deviceId});
    return _WebClient._(peer, name, userId, deviceId, published['identityPublicKey'] as String,
        published['signedPrekeyBundle'] as String);
  }

  @override
  Future<List<Map<String, dynamic>>> uploadOneTimePrekeys() async =>
      ((await _peer.call('uploadOneTimePrekeys', {'name': name}))['prekeys'] as List).cast<Map<String, dynamic>>();

  @override
  Future<bool> holdsOneTimePrekey(int keyId) async =>
      (await _peer.call('holdsOneTimePrekey', {'name': name, 'keyId': keyId}))['held'] as bool;

  @override
  Future<void> bootstrap(String conversationId, _Client peer, Map<String, dynamic> entry) async {
    final result = await _peer.call('bootstrap', {'name': name, 'conversationId': conversationId, 'entry': entry});
    expect(result['started'], isTrue);
  }

  /// Sends [content] (src/domain/content.js) as the web app does, or a raw
  /// inner [payload] for fields the app's content model never sets.
  Future<Map<String, dynamic>> send(String conversationId, _Client to,
      {Map<String, dynamic>? content, Map<String, dynamic>? payload}) async {
    final result = await _peer.call('encrypt', {
      'name': name,
      'conversationId': conversationId,
      'recipientUserId': to.userId,
      'content': content,
      'payload': payload,
    });
    return _relay(result['envelope'] as Map<String, dynamic>);
  }

  @override
  Future<Map<String, dynamic>> sendText(String conversationId, _Client to, String body) =>
      send(conversationId, to, content: {'kind': 'text', 'text': body});

  /// The web cipher's result: status, reason, payload, and the app content.
  Future<Map<String, dynamic>> decrypt(Map<String, dynamic> relayed) =>
      _peer.call('decrypt', {'name': name, 'envelope': relayed});

  @override
  Future<_Opened> receive(Map<String, dynamic> relayed) async {
    final result = await decrypt(relayed);
    final payload = result['payload'] as Map<String, dynamic>?;
    return _Opened(result['status'] as String, result['reason'] as String?, payload?['body'] as String? ?? '');
  }
}

class _MobileClient implements _Client {
  _MobileClient._(this.adapter, this._prekeys, this.identity, this.userId, this.deviceId);

  final LibCryptoAdapter adapter;
  final InMemoryLocalPrekeyStore _prekeys;
  final DeviceIdentityMaterial identity;
  @override
  final String userId;
  @override
  final String deviceId;

  /// Wired as the app wires its adapter: an identity loader and a prekey
  /// store this test can look into.
  static Future<_MobileClient> create() async {
    final adapter = LibCryptoAdapter();
    final prekeys = InMemoryLocalPrekeyStore();
    adapter.setLocalPrekeyStore(prekeys);
    final userId = _nextId();
    final deviceId = _nextId();
    final identity = await adapter.identity.generateDeviceIdentity(deviceId);
    adapter.setLocalIdentityLoader(() async => identity.identityPrivateKeyRef);
    return _MobileClient._(adapter, prekeys, identity, userId, deviceId);
  }

  @override
  String get identityPublicKey => identity.identityPublicKey;

  @override
  String get signedPrekeyBundle => identity.signedPrekeyBundle;

  @override
  Future<List<Map<String, dynamic>>> uploadOneTimePrekeys() async => [
        for (final prekey in await adapter.generateOneTimePrekeys(count: 3))
          {'keyId': prekey.keyId, 'publicKey': prekey.publicKey},
      ];

  @override
  Future<bool> holdsOneTimePrekey(int keyId) async => await _prekeys.loadOneTimePrekey(keyId) != null;

  /// Mirrors VeilMessengerController's bootstrap from a directory entry.
  @override
  Future<void> bootstrap(String conversationId, _Client peer, Map<String, dynamic> entry) async {
    final claimed = entry['oneTimePrekey'] as Map<String, dynamic>?;
    await adapter.sessions.bootstrapSession(SessionBootstrapRequest(
      conversationId: conversationId,
      localDeviceId: deviceId,
      localUserId: userId,
      remoteUserId: peer.userId,
      remoteDeviceId: entry['deviceId'] as String,
      remoteIdentityPublicKey: entry['identityPublicKey'] as String,
      remoteSignedPrekeyBundle: entry['signedPrekeyBundle'] as String,
      remoteOneTimePrekey: claimed == null
          ? null
          : OneTimePrekey(keyId: claimed['keyId'] as int, publicKey: claimed['publicKey'] as String),
    ));
  }

  Future<Map<String, dynamic>> send(String conversationId, _Client to, String body,
      {MessageKind kind = MessageKind.text, DateTime? expiresAt, AttachmentReference? attachment}) async {
    final envelope = await adapter.messaging.encryptMessage(
      conversationId: conversationId,
      senderDeviceId: deviceId,
      recipientUserId: to.userId,
      body: body,
      messageKind: kind,
      recipientBundle: _keyBundle(to),
      expiresAt: expiresAt,
      attachment: attachment,
    );
    return _relay(adapter.envelopeCodec.encodeApiEnvelope(envelope));
  }

  @override
  Future<Map<String, dynamic>> sendText(String conversationId, _Client to, String body) =>
      send(conversationId, to, body);

  Future<DecryptedMessage> decrypt(Map<String, dynamic> relayed) =>
      adapter.messaging.decryptMessage(adapter.envelopeCodec.decodeApiEnvelope(relayed));

  @override
  Future<_Opened> receive(Map<String, dynamic> relayed) async {
    final message = await decrypt(relayed);
    return _Opened(message.status.name, message.failureReason, message.body);
  }
}

void main() {
  final script = _webPeerScript();
  // CI checks out the whole repository, so there a missing peer fails.
  final skip = script == null && Platform.environment['CI'] != 'true'
      ? 'apps/web-demo is not next to apps/mobile in this checkout'
      : null;
  late _WebPeerProcess peer;
  // Stays null when setUpAll failed, so teardown adds no second error.
  _WebPeerProcess? started;

  group('web <-> mobile protocol v2', () {
    setUpAll(() async {
      if (script == null) {
        throw StateError('apps/web-demo/interop/web-peer.mjs not found from ${Directory.current.path}');
      }
      peer = started = await _WebPeerProcess.start(script);
    });
    tearDownAll(() async => started?.close());

    /// Alternating turns of one to three messages, each delivered in reverse
    /// order, then a turn in which both sides send before either receives.
    Future<void> ratchetTurns(String conversationId, _Client a, _Client b) async {
      for (var turn = 0; turn < 6; turn++) {
        final (from, to) = turn.isEven ? (a, b) : (b, a);
        final batch = [
          for (var i = 0; i <= turn % 3; i++) ('t$turn.$i', await from.sendText(conversationId, to, 't$turn.$i')),
        ];
        for (final (body, envelope) in batch.reversed) {
          expect(_frameType(envelope), _normalFrame);
          _expectOpened(await to.receive(envelope), body);
        }
      }
      final fromA = [await a.sendText(conversationId, b, 'a.0'), await a.sendText(conversationId, b, 'a.1')];
      final fromB = [await b.sendText(conversationId, a, 'b.0'), await b.sendText(conversationId, a, 'b.1')];
      _expectOpened(await a.receive(fromB[1]), 'b.1');
      _expectOpened(await b.receive(fromA[1]), 'a.1');
      _expectOpened(await a.receive(fromB[0]), 'b.0');
      _expectOpened(await b.receive(fromA[0]), 'a.0');
      _expectOpened(await b.receive(await a.sendText(conversationId, b, 'a.2')), 'a.2');
      _expectOpened(await a.receive(await b.sendText(conversationId, a, 'b.2')), 'b.2');
    }

    Future<void> firstContact(_Client initiator, _Client responder, {required bool withOneTimePrekey}) async {
      final conversationId = _nextId();
      final entry = await _directoryEntry(responder, claim: withOneTimePrekey);
      final claimedId = (entry['oneTimePrekey'] as Map<String, dynamic>?)?['keyId'] as int?;
      if (claimedId != null) expect(await responder.holdsOneTimePrekey(claimedId), isTrue);
      await initiator.bootstrap(conversationId, responder, entry);

      // Until the responder answers, every frame repeats the PreKey header,
      // naming the claimed one-time prekey or none.
      final opening = [
        for (final body in ['i0', 'i1', 'i2', 'i3']) await initiator.sendText(conversationId, responder, body),
      ];
      for (final envelope in opening) {
        expect(_frameType(envelope), _preKeyFrame);
        expect(_oneTimePrekeyId(envelope), claimedId ?? _noOneTimePrekey);
      }
      _expectOpened(await responder.receive(opening[0]), 'i0');
      if (claimedId != null) {
        expect(await responder.holdsOneTimePrekey(claimedId), isFalse, reason: 'a one-time prekey is used once');
      }
      // i1 is skipped over and i3 held back past the last frame received.
      _expectOpened(await responder.receive(opening[2]), 'i2');

      // The responder answers with Normal frames, which arrive in reverse.
      final replies = [
        await responder.sendText(conversationId, initiator, 'r0'),
        await responder.sendText(conversationId, initiator, 'r1'),
      ];
      expect(replies.map(_frameType), everyElement(_normalFrame));
      _expectOpened(await initiator.receive(replies[1]), 'r1');
      _expectOpened(await initiator.receive(replies[0]), 'r0');

      // The reply completed the handshake: the initiator stops repeating the
      // PreKey header and steps the DH ratchet.
      final next = await initiator.sendText(conversationId, responder, 'i4');
      expect(_frameType(next), _normalFrame);
      _expectOpened(await responder.receive(next), 'i4');
      // The initiator's first chain still opens, each frame once: i3 from the
      // keys stashed when its chain was left (PN), i1 from those stashed when
      // i2 skipped it (N).
      _expectOpened(await responder.receive(opening[3]), 'i3');
      _expectOpened(await responder.receive(opening[1]), 'i1');
      expect((await responder.receive(opening[3])).status, 'replayed');
      expect((await responder.receive(opening[1])).status, 'replayed');
      expect((await initiator.receive(replies[0])).status, 'replayed');

      await ratchetTurns(conversationId, initiator, responder);
    }

    for (final webInitiates in [true, false]) {
      for (final withOneTimePrekey in [true, false]) {
        final (from, to) = webInitiates ? ('web', 'mobile') : ('mobile', 'web');
        test('$from starts a session with $to ${withOneTimePrekey ? 'with' : 'without'} a one-time prekey, '
            'then both ratchet through reordered turns', () async {
          final web = await _WebClient.create(peer);
          final mobile = await _MobileClient.create();
          await (webInitiates
              ? firstContact(web, mobile, withOneTimePrekey: withOneTimePrekey)
              : firstContact(mobile, web, withOneTimePrekey: withOneTimePrekey));
        });
      }
    }

    test("each side authenticates the other's signed prekey bundle and refuses a forged one", () async {
      final web = await _WebClient.create(peer);
      final mobile = await _MobileClient.create();
      Future<Map<String, dynamic>> verifiedOnWeb(String bundle, String identityKey) =>
          peer.call('verifyBundle', {'bundle': bundle, 'identityKey': identityKey});
      String movedTimestamp(String bundle) {
        final fields = json.decode(utf8.decode(b64uDecode(bundle))) as Map<String, dynamic>;
        fields['spkTs'] = (fields['spkTs'] as int) - 1;
        return b64uEncode(utf8.encode(json.encode(fields)));
      }

      final fromWeb = await verifyRemoteBundle(web.signedPrekeyBundle, web.identityPublicKey);
      expect(fromWeb, isA<PrekeyBundleV2>().having((bundle) => bundle.spkId, 'spkId', 1));
      expect(await verifiedOnWeb(mobile.signedPrekeyBundle, mobile.identityPublicKey), {'ok': true, 'spkId': 1});

      await expectLater(verifyRemoteBundle(web.signedPrekeyBundle, mobile.identityPublicKey), throwsStateError);
      await expectLater(verifyRemoteBundle(movedTimestamp(web.signedPrekeyBundle), web.identityPublicKey),
          throwsStateError);
      expect(await verifiedOnWeb(mobile.signedPrekeyBundle, web.identityPublicKey),
          {'ok': false, 'reason': 'bad_signature'});
      expect(await verifiedOnWeb(movedTimestamp(mobile.signedPrekeyBundle), mobile.identityPublicKey),
          {'ok': false, 'reason': 'bad_signature'});
    });

    test('safety numbers and verification codes agree across clients', () async {
      final web = await _WebClient.create(peer);
      final other = await _WebClient.create(peer);
      final mobile = await _MobileClient.create();
      Map<String, String> party(_Client client) => {'identityKey': client.identityPublicKey, 'userId': client.userId};
      final mobileKey = b64uDecode(mobile.identityPublicKey);
      String mobileNumber(_Client remote) => computeSafetyNumberV2(
          localUserId: mobile.userId,
          localIdentityKey: mobileKey,
          remoteUserId: remote.userId,
          remoteIdentityKey: b64uDecode(remote.identityPublicKey));
      SafetyQrVerification mobileScans(String code, _Client remote) => verifyScannedSafetyQr(
          scannedPayload: code,
          localUserId: mobile.userId,
          localIdentityKey: mobileKey,
          remoteUserId: remote.userId,
          remoteIdentityKey: b64uDecode(remote.identityPublicKey));
      final mobileCode = encodeSafetyQrPayload(
          localUserId: mobile.userId,
          localIdentityKey: mobileKey,
          remoteUserId: web.userId,
          remoteIdentityKey: b64uDecode(web.identityPublicKey));

      final onWeb = await peer.call('safetyNumber', {'local': party(web), 'remote': party(mobile)});
      expect(onWeb['number'], matches(RegExp(r'^\d{60}$')));
      expect(mobileNumber(web), onWeb['number']);
      expect(mobileScans(onWeb['code'] as String, web), SafetyQrVerification.verified);
      expect(
          await peer.call('matchesPeerCode', {'local': party(web), 'remote': party(mobile), 'code': mobileCode}),
          {'match': true});

      // A key the server substituted shows on both sides.
      expect(mobileNumber(other), isNot(onWeb['number']));
      expect(mobileScans(onWeb['code'] as String, other), SafetyQrVerification.mismatch);
      expect(
          await peer.call('matchesPeerCode', {'local': party(other), 'remote': party(mobile), 'code': mobileCode}),
          {'match': false});
    });

    test('attachment pointer v2: a blob sealed by one client opens on the other', () async {
      final web = await _WebClient.create(peer);
      final mobile = await _MobileClient.create();
      final conversationId = _nextId();
      await web.bootstrap(conversationId, mobile, await _directoryEntry(mobile, claim: false));
      _expectOpened(await mobile.receive(await web.sendText(conversationId, mobile, 'hi')), 'hi');
      final data = Uint8List.fromList(List.generate(5000, (i) => i * 7 & 0xff));

      // Web to mobile, as the web app sends an image.
      final webAttachmentId = _nextId();
      final sealed = await peer.call('encryptAttachment',
          {'attachmentId': webAttachmentId, 'contentType': 'image/png', 'data': b64uEncode(data)});
      final image = await web.send(conversationId, mobile,
          content: {'kind': 'image', 'text': '', 'attachment': sealed['pointer']});
      expect(image['attachment'], {'attachmentId': webAttachmentId});
      final received = await mobile.decrypt(image);
      expect(received.status, DecryptStatus.ok, reason: received.failureReason);
      expect(received.messageKind, MessageKind.image);
      final reference = received.attachment!;
      expect(reference.attachmentId, webAttachmentId);
      expect(reference.contentType, 'image/png');
      expect(reference.sizeBytes, data.length);
      expect(reference.algorithmHint, 'aes256gcm-v2');
      final webBlob = b64uDecode(sealed['blob'] as String);
      Future<List<int>> openOnMobile(AttachmentReference reference) => mobile.adapter.messaging.decryptAttachment(
          reference: reference, ciphertext: webBlob, localIdentityPrivateRef: mobile.identity.identityPrivateKeyRef);
      expect(await openOnMobile(reference), data);

      // Mobile to web, as the mobile app sends a file.
      final mobileAttachmentId = _nextId();
      final file = await mobile.adapter.messaging.encryptAttachment(
          attachmentId: mobileAttachmentId,
          storageKey: '',
          contentType: 'application/pdf',
          plaintext: data,
          recipientBundle: _keyBundle(web));
      final message = await mobile.send(conversationId, web, 'report.pdf',
          kind: MessageKind.file, attachment: file.reference);
      expect(message['attachment'], {'attachmentId': mobileAttachmentId});
      final opened = await web.decrypt(message);
      expect(opened['status'], 'ok', reason: opened['reason'] as String?);
      final content = opened['content'] as Map<String, dynamic>;
      expect(content['kind'], 'file');
      expect(content['text'], 'report.pdf');
      final pointer = content['attachment'] as Map<String, dynamic>;
      expect(pointer, containsPair('id', mobileAttachmentId));
      expect(pointer, containsPair('ct', 'application/pdf'));
      expect(pointer, containsPair('sz', data.length));
      final mobileBlob = b64uEncode(file.ciphertext);
      expect(await peer.call('decryptAttachment', {'pointer': pointer, 'blob': mobileBlob}), {'data': b64uEncode(data)});

      // The AAD binds the id: under another id the blob opens on neither side.
      final otherId = _nextId();
      expect(
          await peer.call('decryptAttachment', {
            'pointer': {...pointer, 'id': otherId},
            'blob': mobileBlob,
          }),
          contains('error'));
      await expectLater(openOnMobile(reference.copyWith(attachmentId: otherId)), throwsA(anything));
    });

    test('message kinds, reactions, expiry and bodies past the 64 KiB bucket keep their meaning', () async {
      final web = await _WebClient.create(peer);
      final mobile = await _MobileClient.create();
      final conversationId = _nextId();
      await mobile.bootstrap(conversationId, web, await _directoryEntry(web, claim: true));
      _expectOpened(await web.receive(await mobile.sendText(conversationId, web, 'hi')), 'hi');
      final expiry = DateTime.utc(2030, 1, 2, 3, 4, 5, 6);
      final target = _nextId();
      const family = '\u{1F468}‍\u{1F469}‍\u{1F467}';

      // Mobile to web: every kind with an authenticated expiry; the reaction
      // is built by mobile's codec and read by web's.
      for (final kind in MessageKind.values) {
        final body = kind == MessageKind.reaction
            ? ReactionPayload(target: target, emoji: family, add: true).encode()
            : 'mobile ${kind.name} \u{1F600} é';
        final result =
            await web.decrypt(await mobile.send(conversationId, web, body, kind: kind, expiresAt: expiry));
        expect(result['status'], 'ok', reason: result['reason'] as String?);
        final payload = result['payload'] as Map<String, dynamic>;
        expect(payload['kind'], kind.name);
        expect(payload['body'], body);
        expect(payload['expiresAt'], expiry.millisecondsSinceEpoch);
        if (kind == MessageKind.reaction) {
          expect((result['content'] as Map)['reaction'], {'target': target, 'emoji': family, 'op': 'add'});
        }
      }

      // Web to mobile: every kind with an authenticated expiry.
      for (final kind in MessageKind.values) {
        final body = 'web ${kind.name} \u{1F600}';
        final received = await mobile.decrypt(await web.send(conversationId, mobile,
            payload: {'body': body, 'kind': kind.name, 'expiresAt': expiry.millisecondsSinceEpoch}));
        expect(received.status, DecryptStatus.ok, reason: received.failureReason);
        expect(received.messageKind, kind);
        expect(received.body, body);
        expect(received.expiresAt?.millisecondsSinceEpoch, expiry.millisecondsSinceEpoch);
      }

      // A reaction and a reply as the web app sends them. Mobile has no reply
      // link: the reply reads as its text.
      final reaction = await mobile.decrypt(await web.send(conversationId, mobile, content: {
        'kind': 'reaction',
        'reaction': {'target': target, 'emoji': family, 'op': 'remove'},
      }));
      expect(reaction.status, DecryptStatus.ok, reason: reaction.failureReason);
      expect(reaction.messageKind, MessageKind.reaction);
      final decoded = ReactionPayload.tryDecode(reaction.body)!;
      expect((decoded.target, decoded.emoji, decoded.add), (target, family, false));
      final reply = await mobile.decrypt(
          await web.send(conversationId, mobile, content: {'kind': 'reply', 'text': 're', 'replyTo': target}));
      expect((reply.status, reply.messageKind, reply.body), (DecryptStatus.ok, MessageKind.text, 're'));

      // Bodies that need more than the 64 KiB padding bucket.
      final long = 'z' * 70000;
      _expectOpened(await web.receive(await mobile.sendText(conversationId, web, long)), long);
      _expectOpened(await mobile.receive(await web.sendText(conversationId, mobile, long)), long);
    });
  }, skip: skip);
}
