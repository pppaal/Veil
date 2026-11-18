import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/features/attachments/presentation/photo_viewer_screen.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_message_list.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_room_screen.dart';
import 'package:veil_mobile/src/features/chat/presentation/message_file_card.dart';
import 'package:veil_mobile/src/features/chat/presentation/message_photo.dart';
import 'package:veil_mobile/src/features/reactions/presentation/reaction_picker_widget.dart';

import 'layout_seed.dart';
import 'layout_world.dart';
import 'media_receive_seed.dart';
import 'phone_layout_probe.dart';
import 'screen_cases.dart';

// The layout cases of received photos and files: photos in a chat and their
// states, the file card, the photo viewer and Save.

const _chat = '/chat/$chatConversationId';

const List<ScreenCase> mediaReceiveScreenCases = [
  // Two photos from Sam, one of alex's, his signed lease and a voice
  // message from the web, everything fetched and opened.
  ScreenCase(
    'chat-room-photos',
    screen: ChatRoomScreen,
    file: 'chat_room_screen.dart',
    location: _chat,
    afterSession: seedChatPhotos,
    settle: _awaitBubblePhotos,
    primaryExtent: chatMessagesExtent,
    minPrimaryShare: minPrimaryContentShare,
  ),
  // The same chat once the user has gone down to the newest message: the
  // chat opens at its unread divider (D48), so the newest rows (alex's
  // photo, the lease, the voice message) are below the first screen there.
  ScreenCase(
    'chat-room-photos-newest',
    screen: ChatRoomScreen,
    file: 'chat_room_screen.dart',
    location: _chat,
    afterSession: seedChatPhotos,
    settle: _awaitPhotosAtNewest,
    primaryExtent: chatMessagesExtent,
    minPrimaryShare: minPrimaryContentShare,
  ),
  // A photo on its way, one whose fetch failed, one the server no longer
  // has, a file not fetched yet and one on its way; shown from the newest
  // message, since the chat opens at its unread divider above them.
  ScreenCase(
    'chat-room-photo-states',
    screen: ChatRoomScreen,
    file: 'chat_room_screen.dart',
    location: _chat,
    afterSession: seedPhotoStates,
    settle: _showNewest,
    primaryExtent: chatMessagesExtent,
    minPrimaryShare: minPrimaryContentShare,
  ),
  ScreenCase(
    'photo-viewer',
    screen: PhotoViewerScreen,
    file: 'photo_viewer_screen.dart',
    location: _chat,
    afterSession: seedOnePhoto,
    settle: _openViewer,
  ),
  ScreenCase(
    'photo-viewer-portrait',
    screen: PhotoViewerScreen,
    file: 'photo_viewer_screen.dart',
    location: _chat,
    afterSession: _seedPortrait,
    settle: _openViewer,
  ),
  ScreenCase(
    'photo-viewer-save-dialog',
    screen: PhotoViewerScreen,
    file: 'photo_viewer_screen.dart',
    location: _chat,
    afterSession: seedOnePhoto,
    settle: _openSaveDialog,
  ),
  // A long press on the lease: Save above Report.
  ScreenCase(
    'chat-room-message-actions-file',
    screen: ChatRoomScreen,
    file: 'chat_room_screen.dart',
    location: _chat,
    afterSession: seedLease,
    settle: _openFileActions,
  ),
  // In a group, who sent a photo is named in a strip above it.
  ScreenCase(
    'group-chat-photo',
    screen: ChatRoomScreen,
    file: 'chat_room_screen.dart',
    location: '/chat/$groupConversationId',
    withGroup: true,
    afterSession: seedGroupPhoto,
    settle: _awaitBubblePhotos,
    primaryExtent: chatMessagesExtent,
    minPrimaryShare: minPrimaryContentShare,
  ),
];

Future<void> _seedPortrait(LayoutWorld world) => seedOnePhoto(world, portrait: true);

// Photos decode on the engine's own threads, which only real time moves.
// [count] by default: every photo bubble the list has built.
Future<void> _awaitPhotos(WidgetTester tester, Finder images, {int? count}) async {
  int wanted() => count ?? find.byType(MessagePhoto).evaluate().length;
  for (var i = 0; i < 300 && (images.evaluate().isEmpty || images.evaluate().length < wanted()); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  expect(images, findsNWidgets(wanted()), reason: 'the photos did not open');
  // Each tile grows into its photo.
  await pumpFrames(tester, frames: 4);
}

// An image widget draws a RawImage before its photo is in; only one with
// the photo counts.
final Finder _drawnImage = find.byWidgetPredicate((widget) => widget is RawImage && widget.image != null);
final Finder _bubblePhotos = find.descendant(of: find.byType(MessagePhoto), matching: _drawnImage);

Future<void> _awaitBubblePhotos(WidgetTester tester) => _awaitPhotos(tester, _bubblePhotos);

// Down to the newest message, as the user does from a chat that opened at
// its unread divider.
Future<void> _showNewest(WidgetTester tester) async {
  final list = find.descendant(of: find.byType(ChatMessageList), matching: find.byType(Scrollable)).first;
  tester.state<ScrollableState>(list).position.jumpTo(0);
  await pumpFrames(tester, frames: 4);
}

Future<void> _awaitPhotosAtNewest(WidgetTester tester) async {
  await _awaitBubblePhotos(tester);
  await _showNewest(tester);
  await _awaitBubblePhotos(tester);
}

Future<void> _openViewer(WidgetTester tester) async {
  await _awaitBubblePhotos(tester);
  await tester.tap(_bubblePhotos.last);
  await pumpFrames(tester, frames: 4);
  await _awaitPhotos(tester, find.descendant(of: find.byType(PhotoViewerScreen), matching: _drawnImage),
      count: 1);
}

Future<void> _openSaveDialog(WidgetTester tester) async {
  await _openViewer(tester);
  await tester.tap(find.byKey(const ValueKey('photo-viewer-save')));
  await pumpFrames(tester, frames: 4);
  expect(find.byType(AlertDialog), findsOneWidget, reason: 'the Save dialog did not open');
}

Future<void> _openFileActions(WidgetTester tester) async {
  await tester.longPress(find.byType(MessageFileCard));
  await pumpFrames(tester, frames: 4);
  expect(find.byType(ReactionPickerWidget), findsOneWidget, reason: 'the message menu did not open');
}
