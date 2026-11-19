import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/network/veil_api_client.dart';

import 'fake_relay.dart';
import 'mock_relay_parties.dart';

// The fake relay's attachment rules, as the API keeps them, and the knobs
// attachment tests turn: what a download ticket needs, what storage serves,
// and the failures a hostile or broken relay produces.

const _id = '3f2504e0-4f89-41d3-9a0c-0305e82c3301';
const _other = '9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d';

Matcher _code(String code, {int? status}) {
  var matcher = isA<VeilApiException>().having((error) => error.code, 'code', code);
  if (status != null) matcher = matcher.having((error) => error.statusCode, 'statusCode', status);
  return matcher;
}

void main() {
  late FakeRelay relay;
  late FakeRelayClient alice;
  late FakeRelayClient bob;
  late FakeRelayClient carol;
  final blob = List<int>.generate(300, (i) => i % 256);

  Map<String, dynamic> envelope({String? attachmentId, DateTime? expiresAt, String sender = 'dev-alice'}) => {
        'senderDeviceId': sender,
        'ciphertext': 'sealed',
        'nonce': 'n',
        'messageType': attachmentId == null ? 'text' : 'image',
        'version': 'veil-envelope-v1-dev',
        if (attachmentId != null) 'attachment': {'attachmentId': attachmentId},
        'expiresAt': expiresAt?.toUtc().toIso8601String(),
      };

  Map<String, dynamic> injectPhoto({String id = _id, DateTime? expiresAt, String conversationId = 'conv-ab'}) =>
      relay.inject(senderHandle: 'alice', conversationId: conversationId, envelope: envelope(attachmentId: id, expiresAt: expiresAt));

  setUp(() {
    relay = FakeRelay();
    seedMockParties(relay, 'conv-ab', ['alice', 'bob']);
    seedMockParties(relay, 'conv-cd', ['carol', 'dave']);
    alice = relay.clientFor('alice');
    bob = relay.clientFor('bob');
    carol = relay.clientFor('carol');
  });

  test('a message names its attachment on the relay, by inject or by send', () async {
    final injected = injectPhoto(id: _id.toUpperCase());
    final sent = (await alice.sendMessage('t', {
      'conversationId': 'conv-ab',
      'clientMessageId': 'c-1',
      'envelope': envelope(attachmentId: _other),
    }))['message'] as Map<String, dynamic>;
    relay.inject(senderHandle: 'alice', conversationId: 'conv-ab', envelope: envelope());
    expect(relay.conversations['conv-ab']!.attachmentIds, {injected['id']: _id, sent['id']: _other});
  });

  test('putUploadedBlob stores an uploaded row with the blob\'s hex digest', () {
    relay.putUploadedBlob(_id, blob, uploaderDeviceId: 'dev-alice');
    expect(relay.uploadedBlobs[_id], blob);
    final row = relay.attachments[_id]!;
    expect(row.uploadStatus, 'uploaded');
    expect(row.uploaderDeviceId, 'dev-alice');
    expect(row.sha256, sha256.convert(blob).toString());
    expect(row.sizeBytes, blob.length);
  });

  group('download tickets', () {
    test('unknown is not found, not uploaded is invalid, unreferenced is forbidden', () async {
      await expectLater(bob.getDownloadTicket('t', _id), throwsA(_code('attachment_not_found', status: 404)));
      relay.attachments[_id] = RelayAttachment(uploaderDeviceId: 'dev-alice', sha256: 'x', sizeBytes: 1);
      await expectLater(bob.getDownloadTicket('t', _id), throwsA(_code('attachment_upload_invalid', status: 400)));
      relay.putUploadedBlob(_id, blob, uploaderDeviceId: 'dev-alice');
      await expectLater(bob.getDownloadTicket('t', _id), throwsA(_code('attachment_forbidden', status: 403)));
      expect(relay.downloadTicketRequests, [_id, _id, _id]);
    });

    test('a live message in a conversation of the caller grants a 90 s ticket', () async {
      relay.putUploadedBlob(_id, blob, uploaderDeviceId: 'dev-alice');
      injectPhoto();
      final before = relay.now();
      final ticket = (await bob.getDownloadTicket('t', _id))['ticket'] as Map<String, dynamic>;
      expect(Uri.parse(ticket['downloadUrl'] as String).host, 'download.invalid');
      expect(Uri.parse(ticket['downloadUrl'] as String).pathSegments.last, _id);
      final expiresAt = DateTime.parse(ticket['expiresAt'] as String);
      expect(expiresAt.difference(before).inSeconds, inInclusiveRange(89, 91));
      // Not a member of that conversation: no ticket.
      await expectLater(carol.getDownloadTicket('t', _id), throwsA(_code('attachment_forbidden')));
    });

    test('an expired or deleted message grants nothing', () async {
      relay.putUploadedBlob(_id, blob, uploaderDeviceId: 'dev-alice');
      injectPhoto(expiresAt: relay.now().subtract(const Duration(seconds: 1)));
      await expectLater(bob.getDownloadTicket('t', _id), throwsA(_code('attachment_forbidden')));
      final live = injectPhoto(expiresAt: relay.now().add(const Duration(hours: 1)));
      expect(await bob.getDownloadTicket('t', _id), contains('ticket'));
      relay.deletedMessageIds.add(live['id'] as String);
      await expectLater(bob.getDownloadTicket('t', _id), throwsA(_code('attachment_forbidden')));
    });

    test('an id that is not a UUID is refused before it reaches the relay', () async {
      await expectLater(bob.getDownloadTicket('t', '../keys/x'), throwsA(_code('attachment_id_invalid')));
      expect(relay.downloadTicketRequests, isEmpty);
    });
  });

  group('blob downloads', () {
    Future<String> ticket([String id = _id]) async =>
        ((await bob.getDownloadTicket('t', id))['ticket'] as Map<String, dynamic>)['downloadUrl'] as String;

    setUp(() {
      relay.putUploadedBlob(_id, blob, uploaderDeviceId: 'dev-alice');
      injectPhoto();
    });

    test('storage serves the blob within the cap and records the GET', () async {
      final progress = <int>[];
      expect(
        await bob.downloadEncryptedBlob(downloadUrl: await ticket(), maxBytes: blob.length, onProgress: (got, _) => progress.add(got)),
        blob,
      );
      expect(relay.blobDownloads, [_id]);
      expect(progress, [blob.length]);
      await expectLater(
        bob.downloadEncryptedBlob(downloadUrl: await ticket(), maxBytes: blob.length - 1),
        throwsA(_code('attachment_download_invalid')),
      );
    });

    test('a ticket on another host is refused by the storage policy, with no GET', () async {
      relay.downloadHost = 'elsewhere.example';
      await expectLater(
        bob.downloadEncryptedBlob(downloadUrl: await ticket(), maxBytes: 1 << 20),
        throwsA(_code('attachment_download_invalid')),
      );
      expect(relay.blobDownloads, isEmpty);
    });

    test('a ticket past its 90 s is refused', () async {
      final url = await ticket();
      relay.clockSkew = const Duration(seconds: 91);
      await expectLater(bob.downloadEncryptedBlob(downloadUrl: url, maxBytes: 1 << 20), throwsA(_code('attachment_forbidden', status: 403)));
    });

    test('scripted failures: network, statuses once or sticky, tampering, extra bytes', () async {
      relay.failDownloads = 1;
      await expectLater(bob.downloadEncryptedBlob(downloadUrl: await ticket(), maxBytes: 1 << 20), throwsA(_code('network_unavailable')));
      expect(await bob.downloadEncryptedBlob(downloadUrl: await ticket(), maxBytes: 1 << 20), blob);

      relay.downloadStatus[_id] = 403;
      await expectLater(bob.downloadEncryptedBlob(downloadUrl: await ticket(), maxBytes: 1 << 20), throwsA(_code('attachment_forbidden')));
      expect(await bob.downloadEncryptedBlob(downloadUrl: await ticket(), maxBytes: 1 << 20), blob, reason: 'consumed once');

      relay
        ..downloadStatus[_id] = 404
        ..downloadStatusSticky = true;
      for (var i = 0; i < 2; i++) {
        await expectLater(bob.downloadEncryptedBlob(downloadUrl: await ticket(), maxBytes: 1 << 20), throwsA(_code('attachment_not_found')));
      }
      relay.downloadStatus[_id] = 500;
      await expectLater(
          bob.downloadEncryptedBlob(downloadUrl: await ticket(), maxBytes: 1 << 20), throwsA(_code('attachment_download_failed', status: 500)));
      relay
        ..downloadStatus.clear()
        ..downloadStatusSticky = false;

      relay.tamperedBlobs.add(_id);
      final tampered = await bob.downloadEncryptedBlob(downloadUrl: await ticket(), maxBytes: 1 << 20);
      expect(tampered, hasLength(blob.length));
      expect(tampered, isNot(blob));
      relay.tamperedBlobs.clear();

      relay.oversizedBlobs[_id] = 10;
      expect(await bob.downloadEncryptedBlob(downloadUrl: await ticket(), maxBytes: 1 << 20), hasLength(blob.length + 10));
      await expectLater(
        bob.downloadEncryptedBlob(downloadUrl: await ticket(), maxBytes: blob.length),
        throwsA(_code('attachment_download_invalid')),
      );
    });

    test('a gate holds the GET; a cancel ends it', () async {
      relay.downloadGate = Completer<void>();
      final held = bob.downloadEncryptedBlob(downloadUrl: await ticket(), maxBytes: 1 << 20);
      var done = false;
      unawaited(held.then((_) => done = true));
      await pumpEventQueue();
      expect(done, isFalse);
      relay.downloadGate!.complete();
      expect(await held, blob);

      relay.downloadGate = Completer<void>();
      final signal = AttachmentUploadCancellationSignal();
      final canceled = bob.downloadEncryptedBlob(downloadUrl: await ticket(), maxBytes: 1 << 20, cancellationSignal: signal);
      await pumpEventQueue();
      signal.cancel();
      await expectLater(canceled, throwsA(_code('attachment_download_canceled')));
    });
  });

  group('uploads', () {
    late Directory temp;
    late File file;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('veil-relay-upload-');
      file = File('${temp.path}/sealed')..writeAsBytesSync(blob);
    });
    tearDown(() => temp.deleteSync(recursive: true));

    test('a gate holds the PUT, a cancel fails it, and failures are scripted', () async {
      relay.uploadGate = Completer<void>();
      final held = alice.uploadEncryptedBlobFile(uploadUrl: 'https://upload.invalid/$_id', headers: const {}, file: file);
      await pumpEventQueue();
      expect(relay.uploadedBlobs, isEmpty);
      relay.uploadGate!.complete();
      await held;
      expect(relay.uploadedBlobs[_id], blob);

      relay.uploadGate = Completer<void>();
      final signal = AttachmentUploadCancellationSignal();
      final canceled = alice.uploadEncryptedBlobFile(
          uploadUrl: 'https://upload.invalid/$_other', headers: const {}, file: file, cancellationSignal: signal);
      await pumpEventQueue();
      signal.cancel();
      await expectLater(canceled, throwsA(_code('attachment_upload_canceled')));
      expect(relay.uploadedBlobs.containsKey(_other), isFalse);

      relay
        ..uploadGate = null
        ..failUploads = 1;
      await expectLater(
        alice.uploadEncryptedBlobFile(uploadUrl: 'https://upload.invalid/$_other', headers: const {}, file: file),
        throwsA(_code('network_unavailable')),
      );
      await alice.uploadEncryptedBlobFile(uploadUrl: 'https://upload.invalid/$_other', headers: const {}, file: file);
      expect(relay.uploadedBlobs[_other], blob);
    });
  });

  group('sends with an expiry in the past', () {
    Future<Map<String, dynamic>> send(String clientMessageId, DateTime expiresAt) => alice.sendMessage('t', {
          'conversationId': 'conv-ab',
          'clientMessageId': clientMessageId,
          'envelope': envelope(expiresAt: expiresAt),
        });

    test('are taken by default', () async {
      expect(await send('c-old', relay.now().subtract(const Duration(minutes: 5))), contains('message'));
    });

    test('are refused past 60 s when the relay applies the API\'s rule', () async {
      relay.refusePastExpiry = true;
      await expectLater(
        send('c-old', relay.now().subtract(const Duration(seconds: 61))),
        throwsA(allOf(
          _code('validation_failed', status: 400),
          isA<VeilApiException>().having((error) => error.message, 'message', contains('expiresAt is in the past')),
        )),
      );
      expect(await send('c-recent', relay.now().subtract(const Duration(seconds: 59))), contains('message'));
      expect(await send('c-future', relay.now().add(const Duration(seconds: 10))), contains('message'));
    });
  });
}
