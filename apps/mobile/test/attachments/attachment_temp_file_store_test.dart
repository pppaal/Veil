import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:veil_mobile/src/core/network/veil_api_client.dart';
import 'package:veil_mobile/src/features/attachments/data/attachment_storage_paths.dart';
import 'package:veil_mobile/src/features/attachments/data/attachment_temp_file_store.dart';

import '../support/fake_relay.dart';
import '../support/messenger_party.dart';

// Staging holds a picked plaintext only until it is sealed, so nothing in it
// is wanted after a restart, however fresh (D39).

void main() {
  late Directory root;
  late AttachmentStoragePaths paths;
  late DefaultAttachmentTempFileStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('veil-staging-');
    paths = AttachmentStoragePaths(
      temporaryRoot: () async => Directory(p.join(root.path, 'tmp'))..createSync(recursive: true),
      supportRoot: () async => Directory(p.join(root.path, 'support'))..createSync(recursive: true),
      systemTempRoot: () => Directory(p.join(root.path, 'system-tmp'))..createSync(recursive: true),
      sweepSystemTemp: false,
    );
    store = DefaultAttachmentTempFileStore(paths: paths);
  });

  tearDown(() => root.deleteSync(recursive: true));

  Future<File> stagedNow(String name) async =>
      File(p.join((await paths.stagingDir()).path, name))..writeAsStringSync('picked plaintext');

  test('the cleanup at start deletes a staging file written a moment ago', () async {
    final fresh = await stagedNow('a3f9');
    Directory(p.join((await paths.stagingDir()).path, 'left-folder')).createSync();

    await store.cleanupOrphanedFiles(keepPaths: const <String>{});

    expect(fresh.existsSync(), isFalse);
    expect((await paths.stagingDir()).listSync(), isEmpty);
  });

  test('it keeps only what it is told to keep', () async {
    final kept = await stagedNow('kept');
    final dropped = await stagedNow('dropped');

    await store.cleanupOrphanedFiles(keepPaths: {kept.path});

    expect(kept.existsSync(), isTrue);
    expect(dropped.existsSync(), isFalse);
  });

  test('a staged file that is gone fails as attachment_upload_invalid, with nothing made up in its place', () async {
    await expectLater(
      store.createOpaqueBlob(filename: 'brief.pdf', sizeBytes: 64, existingPath: p.join(root.path, 'gone')),
      throwsA(isA<VeilApiException>().having((error) => error.code, 'code', 'attachment_upload_invalid')),
    );
    await expectLater(
      store.createOpaqueBlob(filename: 'brief.pdf', sizeBytes: 64),
      throwsA(isA<VeilApiException>().having((error) => error.code, 'code', 'attachment_upload_invalid')),
    );
    expect((await paths.stagingDir()).listSync(), isEmpty);
  });

  test('a restart of the messenger empties staging', () async {
    final relay = FakeRelay();
    final alice = await MessengerParty.join(relay, handle: 'alice', userId: 'user-alice', deviceId: 'dev-alice');
    addTearDown(alice.dispose);
    await alice.signIn();
    final staging = await alice.attachmentPaths.stagingDir();
    final picked = File(p.join(staging.path, 'picked-moments-ago'))..writeAsStringSync('plaintext');

    await alice.restart();

    expect(picked.existsSync(), isFalse);
    expect(staging.listSync(), isEmpty);
  });
}
