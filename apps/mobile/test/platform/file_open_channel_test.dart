import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:veil_mobile/src/core/platform/file_open_channel.dart';

// The Dart side of veil/file_open: what it sends, how each reply reads, and
// that nothing outside the open folder ever reaches the platform.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(MethodChannelFileOpen.channelName);
  late Directory temporary;
  late List<MethodCall> calls;
  late Object? reply;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('veil-file-open-');
    calls = [];
    reply = 'opened';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (reply is PlatformException) throw reply!;
      return reply;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    temporary.deleteSync(recursive: true);
  });

  MethodChannelFileOpen opener() => MethodChannelFileOpen(temporaryRoot: () async => temporary);

  File inOpenFolder(String name) => File(p.join(temporary.path, 'veil_open', 'Ab3x', name))
    ..createSync(recursive: true)
    ..writeAsStringSync('%PDF-1.4');

  test('sends the path and the type, and reads each reply', () async {
    final file = inOpenFolder('Lease agreement.pdf');
    for (final (answer, result) in [
      ('opened', FileOpenResult.opened),
      ('closed', FileOpenResult.closed),
      ('noApp', FileOpenResult.noApp),
      ('failed', FileOpenResult.failed),
      ('something else', FileOpenResult.failed),
      (null, FileOpenResult.failed),
    ]) {
      reply = answer;
      expect(await opener().open(file.path, mimeType: 'application/pdf'), result, reason: '$answer');
    }
    expect(calls, hasLength(6));
    expect(calls.first.method, 'open');
    expect(calls.first.arguments, {'path': file.resolveSymbolicLinksSync(), 'mimeType': 'application/pdf'});
  });

  test('asks mayHandOver right before the platform, after its own checks: false sends nothing', () async {
    final file = inOpenFolder('lease.pdf');
    var allowed = true;
    var askedAfterChecks = false;
    final open = MethodChannelFileOpen(temporaryRoot: () async {
      // The app locks while the temporary directory is looked up.
      allowed = false;
      return temporary;
    }).open(file.path, mimeType: 'application/pdf', mayHandOver: () {
      askedAfterChecks = true;
      return allowed;
    });
    expect(await open, FileOpenResult.lockedFirst);
    expect(askedAfterChecks, isTrue);
    expect(calls, isEmpty, reason: 'the platform was asked after the lock');
  });

  test('the iOS side refusing because the app locked reads as locked first', () async {
    final file = inOpenFolder('lease.pdf');
    reply = 'locked';
    expect(await opener().open(file.path, mimeType: 'application/pdf', mayHandOver: () => true),
        FileOpenResult.lockedFirst);
  });

  test('a platform error or a missing plugin reads as failed', () async {
    final file = inOpenFolder('notes.txt');
    reply = PlatformException(code: 'boom');
    expect(await opener().open(file.path, mimeType: 'text/plain'), FileOpenResult.failed);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    expect(await opener().open(file.path, mimeType: 'text/plain'), FileOpenResult.failed);
  });

  test('a path outside the open folder makes no call', () async {
    final staging = File(p.join(temporary.path, 'veil_attachment_cache', 'picked.jpg'))
      ..createSync(recursive: true)
      ..writeAsStringSync('x');
    final media = File(p.join(temporary.path, 'veil_media', 'a' * 64))
      ..createSync(recursive: true)
      ..writeAsStringSync('x');
    final escaping = p.join(temporary.path, 'veil_open', '..', 'veil_attachment_cache', 'picked.jpg');
    // A link inside the folder that points out of it.
    final link = Link(p.join(temporary.path, 'veil_open', 'link.jpg'))
      ..createSync(staging.path, recursive: true);
    for (final path in [
      staging.path,
      media.path,
      escaping,
      link.path,
      p.join(temporary.path, 'veil_open', 'missing.pdf'),
      p.join(temporary.path, 'veil_open'),
      '/etc/hosts',
      '',
    ]) {
      expect(await opener().open(path, mimeType: 'application/pdf'), FileOpenResult.failed, reason: path);
    }
    expect(calls, isEmpty);
  });
}
