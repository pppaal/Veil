import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/app/router/app_router.dart';
import 'package:veil_mobile/src/app/system_sheet_grace.dart';
import 'package:veil_mobile/src/app/veil_app.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/notifications/local_notification_service.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/app_lock/presentation/app_lock_screen.dart';
import 'package:veil_mobile/src/features/attachments/data/attach_flow.dart';
import 'package:veil_mobile/src/features/attachments/data/image_preparer.dart';
import 'package:veil_mobile/src/features/attachments/presentation/photo_send_screen.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_room_screen.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';

import '../layout/support/layout_seed.dart';
import '../layout/support/media_send_seed.dart';
import '../support/fake_platform_security.dart';
import '../support/media_fixtures.dart';
import 'phone_app.dart';

// Sending a photo and a file from a chat on a phone: the plus, the sheet,
// the preview, the dialog's words, the bubble, the draft across a lock, and
// a picker on Android that does not lock the app.

const _chat = '/chat/$chatConversationId';

void main() {
  late LayoutIdentities identities;
  final en = lookupAppLocalizations(const Locale('en'));

  setUpAll(() async {
    await loadBundledFonts();
    identities = await LayoutIdentities.generate();
  });

  Finder plus() => find.byTooltip(en.chatAttachAction);

  testWidgets('the plus is on an enabled composer, 44 px, and offers Photos and File', (tester) async {
    await withPhoneApp(tester, identities, location: _chat, body: (world) async {
      expect(plus(), findsOneWidget);
      expect(tester.getSize(plus()).shortestSide, greaterThanOrEqualTo(44));
      await tester.tap(plus());
      await pumpFrames(tester, frames: 4);
      expect(find.text(en.chatAttachPhotos), findsOneWidget);
      expect(find.byIcon(Icons.photo_library_outlined), findsOneWidget);
      expect(find.text(en.chatAttachFile), findsOneWidget);
      // In the sheet: the chat behind it holds the lease the user sent.
      expect(find.descendant(of: find.byType(BottomSheet), matching: find.byIcon(Icons.insert_drive_file_outlined)),
          findsOneWidget);
    });
    // Every other chat of the account has it too.
    await withPhoneApp(tester, identities, location: '/chat/$emptyChatConversationId', body: (world) async {
      expect(plus(), findsOneWidget);
    });
  });

  testWidgets('a blocked chat has no composer, so no plus', (tester) async {
    await withPhoneApp(
      tester,
      identities,
      location: _chat,
      attention: const ChatAttention(peerBlocked: true),
      body: (world) async => expect(plus(), findsNothing),
    );
  });

  testWidgets('a held chat offers no plus while who the peer is waits', (tester) async {
    await withPhoneApp(
      tester,
      identities,
      location: _chat,
      attention: const ChatAttention(accountHeld: true),
      body: (world) async => expect(plus(), findsNothing),
    );
  });

  testWidgets('a photo is previewed, sent, and shows as the sender\'s own photo message', (tester) async {
    final picker = scriptedPicker(photo: lakePhoto());
    await withPhoneApp(tester, identities, location: _chat, overrides: pickingOverrides(picker), body: (world) async {
      await attachFrom(tester, 'photos');
      await pumpUntil(tester, () => find.byType(PhotoSendScreen).evaluate().isNotEmpty);
      expect(find.byTooltip(en.commonClose), findsOneWidget);
      // What is typed stays a draft: the preview has no caption.
      expect(find.descendant(of: find.byType(PhotoSendScreen), matching: find.byType(TextField)), findsNothing);
      await pumpUntil(tester, () => find.descendant(of: find.byType(PhotoSendScreen), matching: find.byType(Image)).evaluate().isNotEmpty);

      // The page has slid in.
      await pumpFrames(tester, frames: 4);
      final before = world.messenger.messagesFor(chatConversationId).length;
      await tester.tap(find.byKey(const ValueKey('photo-send-send')));
      await pumpUntil(tester, () => world.messenger.messagesFor(chatConversationId).length == before + 1,
          reason: 'the photo was not queued');
      await pumpFrames(tester, frames: 4);
      expect(find.byType(PhotoSendScreen), findsNothing);
      final own = world.messenger.messagesFor(chatConversationId).last;
      expect(own.isMine, isTrue);
      final opened = await settled(tester, world.messenger.decryptMessage(own));
      expect(opened.messageKind, MessageKind.image);
      expect(opened.body, isEmpty);
      expect(opened.attachment!.contentType, 'image/jpeg');
      await pumpFrames(tester, frames: 3);
      expect(find.text('Encrypted attachment'), findsNothing);
      expect(picker.pluginCache.listSync(), isEmpty, reason: 'the plugin copy stayed');
    });
  });

  testWidgets('closing the preview sends nothing and leaves nothing staged', (tester) async {
    final picker = scriptedPicker(photo: lakePhoto());
    await withPhoneApp(tester, identities, location: _chat, overrides: pickingOverrides(picker), body: (world) async {
      final before = world.messenger.messagesFor(chatConversationId).length;
      await attachFrom(tester, 'photos');
      await pumpUntil(tester, () => find.byType(PhotoSendScreen).evaluate().isNotEmpty);
      await pumpFrames(tester, frames: 4);
      await tester.tap(find.byKey(const ValueKey('photo-send-close')));
      await pumpUntil(tester, () => find.byType(PhotoSendScreen).evaluate().isEmpty);
      final staging = await settled(tester, world.attachmentPaths.stagingDir());
      await pumpUntil(tester, () => staging.listSync().isEmpty, reason: 'the staged photo stayed');
      expect(world.messenger.messagesFor(chatConversationId), hasLength(before));
    });
  });

  testWidgets('a file asks first, in plain words, with the location line for a photo picked as a file', (tester) async {
    final picker = scriptedPicker(file: jpegWithMetadata(width: 320, height: 240), fileName: photoAsFileName);
    await withPhoneApp(tester, identities, location: _chat, overrides: pickingOverrides(picker), body: (world) async {
      await attachFrom(tester, 'file');
      await pumpUntil(tester, () => find.byType(AlertDialog).evaluate().isNotEmpty);
      expect(find.text(en.chatSendFileTitle(photoAsFileName, peerNames[peerHandle]!.replaceAll(' ', '\u00A0'))), findsOneWidget);
      expect(find.descendant(of: find.byType(AlertDialog), matching: find.textContaining('JPG · ')), findsOneWidget);
      expect(find.text(en.chatSendFileKeepsMetadata), findsOneWidget);

      final before = world.messenger.messagesFor(chatConversationId).length;
      await tester.tap(find.byKey(const ValueKey('attach-file-send')));
      await pumpUntil(tester, () => world.messenger.messagesFor(chatConversationId).length == before + 1,
          reason: 'the file was not queued');
      final opened = await settled(tester, world.messenger.decryptMessage(world.messenger.messagesFor(chatConversationId).last));
      expect(opened.messageKind, MessageKind.file);
      expect(opened.body, photoAsFileName);
    });
  });

  testWidgets('a PDF\'s dialog has no location line', (tester) async {
    final picker = scriptedPicker(file: leaseBytes());
    await withPhoneApp(tester, identities, location: _chat, overrides: pickingOverrides(picker), body: (world) async {
      await attachFrom(tester, 'file');
      await pumpUntil(tester, () => find.byType(AlertDialog).evaluate().isNotEmpty);
      expect(find.text(en.chatSendFileTitle(leaseFileName, peerNames[peerHandle]!.replaceAll(' ', '\u00A0'))), findsOneWidget);
      expect(find.descendant(of: find.byType(AlertDialog), matching: find.textContaining('PDF · ')), findsOneWidget);
      expect(find.text(en.chatSendFileKeepsMetadata), findsNothing);
    });
  });

  testWidgets('a file over 25 MB says so and sends nothing', (tester) async {
    final picker = scriptedPicker(file: leaseBytes(), fileSize: 30 * 1024 * 1024);
    await withPhoneApp(tester, identities, location: _chat, overrides: pickingOverrides(picker), body: (world) async {
      await attachFrom(tester, 'file');
      await pumpUntil(tester, () => find.byType(SnackBar).evaluate().isNotEmpty);
      expect(find.text(en.chatAttachTooBig('25 MB')), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  testWidgets('a photo that cannot be prepared says so', (tester) async {
    final picker = scriptedPicker(photo: notAnImage());
    await withPhoneApp(tester, identities, location: _chat, overrides: pickingOverrides(picker), body: (world) async {
      await attachFrom(tester, 'photos');
      await pumpUntil(tester, () => find.text(en.chatAttachPhotoFailed).evaluate().isNotEmpty);
      expect(find.byType(PhotoSendScreen), findsNothing);
    });
  });

  testWidgets('the draft and a pick held over a lock come back after the unlock, through the real router', (tester) async {
    final picker = scriptedPicker(file: leaseBytes())..gate = Completer<void>();
    usePhoneView(tester, phoneSmall);
    final world = await LayoutWorld.create(
      identities: identities,
      account: LayoutAccount.signedIn,
      locale: 'en',
      overrides: pickingOverrides(picker),
    );
    try {
      final router = world.container.read(appRouterProvider);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: world.container,
        child: MaterialApp.router(
          theme: VeilTheme.dark(fontFamily: layoutFontFamily),
          locale: const Locale('en'),
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ));
      await pumpFrames(tester);
      unawaited(router.push(_chat));
      await pumpFrames(tester);
      expect(find.byType(ChatRoomScreen), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'the lease is attached');
      await tester.pump();
      // The file picker is up when the app locks.
      await attachFrom(tester, 'file');
      await pumpUntil(tester, () => world.container.read(systemSheetGraceProvider).sheetRunning);

      final session = world.container.read(appSessionProvider.notifier);
      session.lock();
      world.container.read(systemSheetGraceProvider).closeAllForLock();
      await pumpFrames(tester, frames: 6);
      expect(find.byType(AppLockScreen), findsOneWidget);
      expect(find.byType(ChatRoomScreen), findsNothing);
      // The picker answers after the lock: held for the chat, not shown.
      picker.gate!.complete();
      final flow = world.container.read(attachFlowProvider(chatConversationId));
      await pumpUntil(tester, () => flow.held.value != null, reason: 'the late pick was not held');
      expect(find.byType(AlertDialog), findsNothing);

      session.unlock();
      await pumpFrames(tester, frames: 6);
      expect(find.byType(ChatRoomScreen), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'the lease is attached');
      await pumpUntil(tester, () => find.byType(AlertDialog).evaluate().isNotEmpty, reason: 'the held pick was not offered');
      expect(find.text(en.chatSendFileTitle(leaseFileName, peerNames[peerHandle]!.replaceAll(' ', '\u00A0'))), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      world.dispose();
    }
  });

  // The chat open through the real router, as an unlock rebuilds it.
  Future<LayoutWorld> openChatThroughRouter(WidgetTester tester, List<Override> overrides) async {
    usePhoneView(tester, phoneSmall);
    final world = await LayoutWorld.create(
      identities: identities,
      account: LayoutAccount.signedIn,
      locale: 'en',
      overrides: overrides,
    );
    final router = world.container.read(appRouterProvider);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: world.container,
      child: MaterialApp.router(
        theme: VeilTheme.dark(fontFamily: layoutFontFamily),
        locale: const Locale('en'),
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ));
    await pumpFrames(tester);
    unawaited(router.push(_chat));
    await pumpFrames(tester);
    expect(find.byType(ChatRoomScreen), findsOneWidget);
    return world;
  }

  Future<void> closeApp(WidgetTester tester, LayoutWorld world) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    world.dispose();
  }

  testWidgets(
      'a photo preview the lock takes down is offered again after the unlock, also when the unlock comes before the photo is ready',
      (tester) async {
    final picker = scriptedPicker(photo: lakePhoto());
    final preparer = _GatedPreparer();
    final world = await openChatThroughRouter(tester, pickingOverrides(picker, preparer: preparer));
    try {
      await attachFrom(tester, 'photos');
      await pumpUntil(tester, () => find.byType(PhotoSendScreen).evaluate().isNotEmpty);
      await pumpFrames(tester, frames: 4);
      final staging = await settled(tester, world.attachmentPaths.stagingDir());
      final flow = world.container.read(attachFlowProvider(chatConversationId));

      // The photo is still being prepared under the spinner when the app
      // locks, and still when the user is back (Face ID beats a large HEIC).
      final session = world.container.read(appSessionProvider.notifier);
      session.lock();
      await pumpFrames(tester, frames: 6);
      expect(find.byType(AppLockScreen), findsOneWidget);
      expect(find.byType(PhotoSendScreen), findsNothing);
      expect(flow.held.value, isA<PhotoPick>(), reason: 'the photo the lock took down was not held');

      session.unlock();
      await pumpUntil(tester, () => find.byType(PhotoSendScreen).evaluate().isNotEmpty,
          reason: 'the held photo was not offered again');
      expect(staging.listSync(), hasLength(1), reason: 'the staged photo went');
      preparer.gate.complete();
      await pumpUntil(tester,
          () => find.descendant(of: find.byType(PhotoSendScreen), matching: find.byType(Image)).evaluate().isNotEmpty,
          reason: 'the photo never showed');

      final before = world.messenger.messagesFor(chatConversationId).length;
      await pumpFrames(tester, frames: 4);
      await tester.tap(find.byKey(const ValueKey('photo-send-send')));
      await pumpUntil(tester, () => world.messenger.messagesFor(chatConversationId).length == before + 1,
          reason: 'the photo was not queued');
    } finally {
      await closeApp(tester, world);
    }
  });

  testWidgets('a file dialog the lock takes down is offered again after the unlock', (tester) async {
    final picker = scriptedPicker(file: leaseBytes());
    final world = await openChatThroughRouter(tester, pickingOverrides(picker));
    try {
      await attachFrom(tester, 'file');
      await pumpUntil(tester, () => find.byType(AlertDialog).evaluate().isNotEmpty);
      final staging = await settled(tester, world.attachmentPaths.stagingDir());

      final session = world.container.read(appSessionProvider.notifier);
      session.lock();
      await pumpFrames(tester, frames: 6);
      expect(find.byType(AlertDialog), findsNothing);
      expect(world.container.read(attachFlowProvider(chatConversationId)).held.value, isA<FilePick>());

      session.unlock();
      await pumpUntil(tester, () => find.byType(AlertDialog).evaluate().isNotEmpty,
          reason: 'the held file was not offered again');
      expect(find.text(en.chatSendFileTitle(leaseFileName, peerNames[peerHandle]!.replaceAll(' ', '\u00A0'))), findsOneWidget);
      expect(staging.listSync(), hasLength(1));
    } finally {
      await closeApp(tester, world);
    }
  });

  testWidgets('a pick held while the user is attaching another is offered once that is done', (tester) async {
    final picker = scriptedPicker(file: leaseBytes())..gate = Completer<void>();
    final world = await openChatThroughRouter(tester, pickingOverrides(picker));
    try {
      await attachFrom(tester, 'file');
      await pumpUntil(tester, () => world.container.read(systemSheetGraceProvider).sheetRunning);
      final session = world.container.read(appSessionProvider.notifier);
      session.lock();
      world.container.read(systemSheetGraceProvider).closeAllForLock();
      await pumpFrames(tester, frames: 6);
      session.unlock();
      await pumpFrames(tester, frames: 6);
      expect(find.byType(ChatRoomScreen), findsOneWidget);

      // The attach sheet is open again when the first picker answers late.
      await tester.tap(find.byKey(const ValueKey('composer-attach')));
      await pumpFrames(tester, frames: 4);
      picker.gate!.complete();
      final flow = world.container.read(attachFlowProvider(chatConversationId));
      await pumpUntil(tester, () => flow.held.value != null, reason: 'the late pick was not held');
      expect(find.byType(AlertDialog), findsNothing);

      // The sheet closed with nothing picked: the held pick is offered.
      Navigator.of(tester.element(find.text(en.chatAttachFile))).pop();
      await pumpUntil(tester, () => find.byType(AlertDialog).evaluate().isNotEmpty,
          reason: 'the held pick was left to expire');
      expect(find.text(en.chatSendFileTitle(leaseFileName, peerNames[peerHandle]!.replaceAll(' ', '\u00A0'))), findsOneWidget);
    } finally {
      await closeApp(tester, world);
    }
  });

  testWidgets('on Android, the app hidden behind a picker does not lock, and the pick comes back', (tester) async {
    final picker = scriptedPicker(file: leaseBytes())..gate = Completer<void>();
    final platform = RecordingPlatformSecurity();
    addTearDown(platform.close);
    final world = await LayoutWorld.create(
      identities: identities,
      account: LayoutAccount.signedIn,
      locale: 'en',
      overrides: [
        ...pickingOverrides(picker),
        platformSecurityServiceProvider.overrideWithValue(platform),
        systemSheetGraceProvider.overrideWithValue(SystemSheetGrace(isIOS: false)),
        localNotificationServiceProvider.overrideWithValue(_QuietNotifications()),
      ],
    );
    usePhoneView(tester, phoneSmall);
    try {
      await tester.pumpWidget(UncontrolledProviderScope(container: world.container, child: const VeilApp()));
      await pumpFrames(tester);
      unawaited(world.container.read(appRouterProvider).push(_chat));
      await pumpFrames(tester);
      expect(find.byType(ChatRoomScreen), findsOneWidget);

      await attachFrom(tester, 'file');
      await pumpUntil(tester, () => world.container.read(systemSheetGraceProvider).sheetRunning);
      // The picker is another app's activity: Veil goes through inactive,
      // hidden and paused, and back.
      for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();
      expect(world.container.read(appSessionProvider).locked, isFalse);
      picker.gate!.complete();
      for (final state in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await pumpUntil(tester, () => find.byType(AlertDialog).evaluate().isNotEmpty, reason: 'the pick did not come back');
      expect(world.container.read(appSessionProvider).locked, isFalse);
      expect(find.byType(AppLockScreen), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      world.dispose();
    }
  });
}

/// Prepares a photo only once [gate] opens, as a large photo takes a while.
class _GatedPreparer implements ImagePreparer {
  final Completer<void> gate = Completer<void>();
  final SeedPreparer _inner = SeedPreparer();

  @override
  Future<PreparedImage> prepare(String sourcePath) async {
    await gate.future;
    return _inner.prepare(sourcePath);
  }
}

class _QuietNotifications implements LocalNotificationService {
  @override
  void Function(String? conversationId)? onNotificationTapped;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> showMessageNotification({required String conversationId, required String title, required String body}) async {}

  @override
  Future<void> cancelConversation(String conversationId) async {}
}
