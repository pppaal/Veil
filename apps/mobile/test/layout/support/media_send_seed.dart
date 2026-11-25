import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/features/attachments/data/attachment_picker.dart';
import 'package:veil_mobile/src/features/attachments/data/image_preparer.dart';
import 'package:veil_mobile/src/features/attachments/domain/attachment_rules.dart';
import 'package:veil_mobile/src/features/attachments/domain/outgoing_attachment.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_room_screen.dart';
import 'package:veil_mobile/src/features/chat/presentation/message_photo.dart';

import '../../support/fake_attachment_picker.dart';
import '../../support/fake_relay.dart';
import '../../support/media_fixtures.dart';
import 'phone_layout_probe.dart';

// What the send cases pick and how they drive the picks: photos that look
// like photos, a lease to send as a file, the system pickers scripted, and
// the waits that let real file work and isolates run inside a widget test.

/// A photo as the phone prepares one: a lake under hills at the end of the
/// afternoon, [width] x [height], as a JPEG. Made once per size.
Uint8List lakePhoto({int width = 1200, int height = 900}) =>
    _photos.putIfAbsent((width, height), () => img.encodeJpg(_lake(width, height), quality: kPhotoJpegQuality));

final Map<(int, int), Uint8List> _photos = {};

img.Image _lake(int width, int height) {
  final image = img.Image(width: width, height: height);
  final horizon = (height * 0.58).round();
  final random = Random(7);
  int mix(int a, int b, double t) => (a + (b - a) * t).round().clamp(0, 255);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final t = y / horizon;
      // Sky: pale gold low down, clear blue above.
      var (r, g, b) = (mix(118, 246, t), mix(164, 214, t), mix(214, 170, t));
      // The far hills, then the near ones, as two soft ridges.
      final far = horizon - 70 * height / 900 - 40 * sin(x / width * pi * 2.2 + 0.6) * height / 900;
      final near = horizon - 20 * height / 900 - 55 * sin(x / width * pi * 1.4 + 2.1) * height / 900;
      if (y > far) (r, g, b) = (92, 112, 128);
      if (y > near) (r, g, b) = (58, 86, 70);
      if (y > horizon) {
        // The lake mirrors the sky, darker, with a little ripple.
        final depth = (y - horizon) / (height - horizon);
        final ripple = random.nextInt(9) - 4;
        (r, g, b) = (mix(150, 40, depth) + ripple, mix(176, 70, depth) + ripple, mix(196, 98, depth) + ripple);
      }
      image.setPixelRgb(x, y, r, g, b);
    }
  }
  // The sun, low over the far ridge.
  img.fillCircle(image,
      x: (width * 0.68).round(),
      y: (horizon - 120 * height / 900).round(),
      radius: (34 * height / 900).round(),
      color: img.ColorRgb8(255, 236, 196));
  return image;
}

/// A lease to send as a file.
const leaseFileName = 'Lease agreement 2026.pdf';

/// A phone photo picked under File: it keeps its location.
const photoAsFileName = 'IMG_2041.JPG';

/// The folder standing for the plugins' cache in the send cases.
Directory pluginCacheFolder() =>
    Directory(p.join(Directory.systemTemp.path, 'veil-layout-plugin-cache'))..createSync(recursive: true);

/// The system pickers, scripted: [photo] for Photos, [file] (named
/// [fileName], reported as [fileSize]) for File.
FakeAttachmentPicker scriptedPicker({
  Uint8List? photo,
  List<int>? file,
  String fileName = leaseFileName,
  int? fileSize,
}) =>
    FakeAttachmentPicker(pluginCacheFolder())
      ..photo = photo
      ..file = file
      ..fileName = fileName
      ..reportedSize = fileSize;

/// Prepares a picked photo as the engine would, without the engine: what
/// was picked is already a prepared photo.
class SeedPreparer implements ImagePreparer {
  @override
  Future<PreparedImage> prepare(String sourcePath) async {
    final bytes = await File(sourcePath).readAsBytes();
    final decoded = img.decodeJpg(bytes);
    if (decoded == null) throw const ImagePrepareException('not a photo');
    return PreparedImage(bytes: bytes, contentType: 'image/jpeg', width: decoded.width, height: decoded.height);
  }
}

/// The overrides of a case that picks: [picker], its cache as the place
/// the pickers' copies are deleted from, and [preparer] (the seed preparer
/// unless given).
List<Override> pickingOverrides(FakeAttachmentPicker picker, {ImagePreparer? preparer}) => [
      attachmentPickerProvider.overrideWithValue(picker),
      pickerCopyRootsProvider.overrideWithValue(PickerCopyRoots.at([picker.pluginCache])),
      imagePreparerProvider.overrideWithValue(preparer ?? SeedPreparer()),
    ];

/// Lets file work and isolates started from the widget tree run (they
/// never finish inside the test's fake clock) until [until] holds.
Future<void> pumpUntil(WidgetTester tester, bool Function() until, {int rounds = 120, String? reason}) async {
  for (var i = 0; i < rounds && !until(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(until(), isTrue, reason: reason ?? 'the picked attachment never showed');
}

/// Taps the composer's plus and the sheet's [row] ('photos' or 'file').
Future<void> attachFrom(WidgetTester tester, String row) async {
  await tester.tap(find.byKey(const ValueKey('composer-attach')));
  await pumpFrames(tester, frames: 4);
  await tester.tap(find.byKey(ValueKey('attach-$row')));
  await tester.pump();
}

/// Decodes every image on screen, which a widget test only does inside
/// runAsync, so a render shows the photo.
Future<void> decodeImagesOnScreen(WidgetTester tester) async {
  for (final element in find.byType(Image).evaluate().toList()) {
    final image = element.widget as Image;
    await tester.runAsync(() => precacheImage(image.image, element));
  }
  await tester.pump();
}

/// Says the app is in front and unlocked, as VeilApp does on the phone (the
/// layout world has no VeilApp): the media service then opens what the
/// chat shows, the user's own photo from its sealed blob included.
void appInFront(WidgetTester tester) {
  final container = ProviderScope.containerOf(tester.element(find.byType(ChatRoomScreen)));
  container.read(messengerControllerProvider).media.setInUse(true);
}

/// Waits until every photo bubble on screen has its photo drawn: decrypted
/// in an isolate and decoded on the engine's threads, which only real time
/// moves.
Future<void> awaitOwnPhotos(WidgetTester tester) async {
  final drawn = find.descendant(
    of: find.byType(MessagePhoto),
    matching: find.byWidgetPredicate((widget) => widget is RawImage && widget.image != null),
  );
  await pumpUntil(
    tester,
    () => drawn.evaluate().isNotEmpty && drawn.evaluate().length == find.byType(MessagePhoto).evaluate().length,
    rounds: 300,
    reason: 'the own photo never showed from its blob',
  );
  // The tile grows into the photo.
  await pumpFrames(tester, frames: 4);
}

/// Waits for [future], started from the widget tree, letting the file work
/// and isolates behind it run and the test's clock move (the messenger's
/// writes are debounced on it), and returns its value.
Future<T> settled<T>(WidgetTester tester, Future<T> future, {String? reason}) async {
  var done = false;
  late T value;
  Object? failure;
  future.then((result) {
    value = result;
    done = true;
  }, onError: (Object error) {
    failure = error;
    done = true;
  });
  await pumpUntil(tester, () => done, reason: reason ?? 'the work never finished');
  if (failure != null) throw failure!;
  return value;
}

/// Sends [attachment]-to-be from the chat on screen, as the composer does
/// once the preview or the dialog said Send: staged first, then sealed and
/// queued.
Future<void> sendFromChat(WidgetTester tester, List<int> bytes, OutgoingAttachment Function(String path) attachment) async {
  final container = ProviderScope.containerOf(tester.element(find.byType(ChatRoomScreen)));
  final paths = container.read(attachmentStoragePathsProvider);
  final messenger = container.read(messengerControllerProvider);
  final conversationId = tester.widget<ChatRoomScreen>(find.byType(ChatRoomScreen)).conversationId;
  final staging = await settled(tester, paths.stagingDir());
  final file = File(p.join(staging.path, 'staged-${DateTime.now().microsecondsSinceEpoch}'))..writeAsBytesSync(bytes);
  final queued = await settled(
    tester,
    messenger.sendAttachment(conversationId: conversationId, attachment: attachment(file.path)),
    reason: 'the attachment was never queued',
  );
  expect(queued, isTrue, reason: 'the attachment was not queued');
  await pumpFrames(tester, frames: 3);
}

/// The lease's bytes.
Uint8List leaseBytes() => pdfBytes('lease 2026');

/// The relay the app on screen talks to.
FakeRelay relayOf(WidgetTester tester) {
  final container = ProviderScope.containerOf(tester.element(find.byType(ChatRoomScreen)));
  return (container.read(apiClientProvider) as FakeRelayClient).relay;
}
