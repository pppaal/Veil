import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/network/veil_api_client.dart';
import 'package:veil_mobile/src/features/attachments/domain/attachment_rules.dart';
import 'package:veil_mobile/src/features/attachments/domain/outgoing_attachment.dart';
import 'package:veil_mobile/src/features/attachments/presentation/photo_send_screen.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_room_screen.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';

import '../../support/fake_relay.dart';
import '../../support/media_fixtures.dart';
import 'layout_world.dart';
import 'media_send_seed.dart';
import 'phone_layout_probe.dart';
import 'screen_cases.dart';

// The layout cases of sending photos and files: the attach sheet, the photo
// preview, the file dialog, uploads in a chat and a failed one.

const _chat = '/chat/$chatConversationId';

const List<ScreenCase> mediaSendScreenCases = [
  ScreenCase(
    'chat-room-attach-sheet',
    screen: ChatRoomScreen,
    file: 'chat_room_screen.dart',
    location: _chat,
    settle: _openAttachSheet,
  ),
  // The preview of a landscape photo, and of a portrait one.
  ScreenCase(
    'photo-send',
    screen: PhotoSendScreen,
    file: 'photo_send_screen.dart',
    location: _chat,
    overrides: _landscapePick,
    settle: _previewPhoto,
  ),
  ScreenCase(
    'photo-send-portrait',
    screen: PhotoSendScreen,
    file: 'photo_send_screen.dart',
    location: _chat,
    overrides: _portraitPick,
    settle: _previewPhoto,
  ),
  // The question before a file goes, and the one for a photo picked as a
  // file, with the line that it keeps any location saved in it.
  ScreenCase(
    'chat-room-file-confirm',
    screen: ChatRoomScreen,
    file: 'chat_room_screen.dart',
    location: _chat,
    overrides: _leasePick,
    settle: _confirmFile,
  ),
  ScreenCase(
    'chat-room-file-confirm-photo-as-file',
    screen: ChatRoomScreen,
    file: 'chat_room_screen.dart',
    location: _chat,
    overrides: _photoAsFilePick,
    settle: _confirmFile,
  ),
  // An own photo and an own file while they upload, and both once they
  // could not be sent.
  ScreenCase(
    'chat-room-uploading',
    screen: ChatRoomScreen,
    file: 'chat_room_screen.dart',
    location: _chat,
    beforeSession: _holdUploads,
    settle: _uploadPhotoAndFile,
  ),
  ScreenCase(
    'chat-room-upload-failed',
    screen: ChatRoomScreen,
    file: 'chat_room_screen.dart',
    location: _chat,
    beforeSession: _holdUploads,
    settle: _failPhotoAndFileUploads,
  ),
  // A file over the limit: a toast, nothing staged.
  ScreenCase(
    'chat-room-file-too-big',
    screen: ChatRoomScreen,
    file: 'chat_room_screen.dart',
    location: _chat,
    overrides: _hugePick,
    settle: _pickHugeFile,
  ),
];

List<Override> _landscapePick() => pickingOverrides(scriptedPicker(photo: lakePhoto()));

List<Override> _portraitPick() => pickingOverrides(scriptedPicker(photo: lakePhoto(width: 900, height: 1200)));

List<Override> _leasePick() => pickingOverrides(scriptedPicker(file: leaseBytes()));

List<Override> _photoAsFilePick() =>
    pickingOverrides(scriptedPicker(file: jpegWithMetadata(width: 320, height: 240), fileName: photoAsFileName));

List<Override> _hugePick() => pickingOverrides(scriptedPicker(file: leaseBytes(), fileSize: kMaxFileBytes + 4 * 1024 * 1024));

// Every upload waits, so a sent photo or file stays mid-upload.
void _holdUploads(FakeRelay relay) => relay.uploadGate = Completer<void>();

Future<void> _openAttachSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('composer-attach')));
  await pumpFrames(tester, frames: 4);
  expect(find.byKey(const ValueKey('attach-photos')), findsOneWidget, reason: 'the attach sheet did not open');
}

Future<void> _previewPhoto(WidgetTester tester) async {
  await attachFrom(tester, 'photos');
  await pumpUntil(tester, () => find.descendant(of: find.byType(PhotoSendScreen), matching: find.byType(Image)).evaluate().isNotEmpty);
  await decodeImagesOnScreen(tester);
  await pumpFrames(tester, frames: 3);
}

Future<void> _confirmFile(WidgetTester tester) async {
  await attachFrom(tester, 'file');
  await pumpUntil(tester, () => find.byType(AlertDialog).evaluate().isNotEmpty);
  await pumpFrames(tester, frames: 3);
}

Future<void> _pickHugeFile(WidgetTester tester) async {
  await attachFrom(tester, 'file');
  await pumpUntil(tester, () => find.byType(SnackBar).evaluate().isNotEmpty);
  await pumpFrames(tester, frames: 3);
}

Future<void> _uploadPhotoAndFile(WidgetTester tester) async {
  appInFront(tester);
  await sendFromChat(tester, lakePhoto(), (path) => OutgoingAttachment.photo(path: path, contentType: 'image/jpeg'));
  await sendFromChat(
    tester,
    leaseBytes(),
    (path) => OutgoingAttachment.file(path: path, name: leaseFileName, contentType: contentTypeForName(leaseFileName)),
  );
  // The file waits behind the photo: one chat sends in order.
  await pumpUntil(tester, () => _relay(tester).uploadTickets.length == 1, reason: 'the upload never started');
  // The photo shows from the blob it was sealed into, under the scrim.
  await awaitOwnPhotos(tester);
}

Future<void> _failPhotoAndFileUploads(WidgetTester tester) async {
  appInFront(tester);
  await sendFromChat(tester, lakePhoto(), (path) => OutgoingAttachment.photo(path: path, contentType: 'image/jpeg'));
  await sendFromChat(
    tester,
    leaseBytes(),
    (path) => OutgoingAttachment.file(path: path, name: leaseFileName, contentType: contentTypeForName(leaseFileName)),
  );
  final relay = _relay(tester);
  await pumpUntil(tester, () => relay.uploadTickets.length == 1, reason: 'the upload never started');
  // The storage refuses both: not worth retrying, so each send fails for
  // good, the file once the photo before it has. (Handled here too, in case
  // an upload has not reached the gate yet.)
  relay.uploadGate!
    ..future.ignore()
    ..completeError(
        VeilApiException('Attachment upload failed: HTTP 403', code: 'attachment_upload_failed', statusCode: 403));
  await pumpUntil(
    tester,
    () => find.text(lookupAppLocalizations(const Locale('en')).chatNotSentTapToRetry).evaluate().length == 2,
    reason: 'the sends never failed',
  );
  // The toast that says so has gone by the time anyone looks again: its
  // clock starts once it is in, and it slides out.
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 5));
  // A failed photo keeps the photo, without the scrim; the failed file its
  // file glyph and the cross that removes it.
  await awaitOwnPhotos(tester);
  expect(find.byTooltip(lookupAppLocalizations(const Locale('en')).chatCancelAction), findsNWidgets(2),
      reason: 'a failed photo or file has no cross to remove it');
}

FakeRelay _relay(WidgetTester tester) => relayOf(tester);
