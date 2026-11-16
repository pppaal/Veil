import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/app/router/app_router.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/app_lock/presentation/app_lock_screen.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_room_screen.dart';
import 'package:veil_mobile/src/core/storage/secure_storage_service.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_composer_bar.dart';
import 'package:veil_mobile/src/features/conversations/presentation/conversation_list_screen.dart';
import 'package:veil_mobile/src/features/conversations/presentation/conversation_row.dart';
import 'package:veil_mobile/src/features/reactions/presentation/reaction_picker_widget.dart';
import 'package:veil_mobile/src/features/safety/data/conversation_mutes.dart';
import 'package:veil_mobile/src/features/safety/data/safety_providers.dart';
import 'package:veil_mobile/src/features/safety/presentation/blocked_accounts_screen.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/shared/presentation/veil_ui.dart';

import '../layout/support/layout_seed.dart';
import '../support/copy_finder.dart';
import 'phone_app.dart';

// Blocking, reporting and muting on a phone, through the real routes and
// screens over the fake relay, which enforces a block as the server does.

const _chat = '/chat/$chatConversationId';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LayoutIdentities identities;
  final en = lookupAppLocalizations(const Locale('en'));

  setUpAll(() async {
    await loadBundledFonts();
    identities = await LayoutIdentities.generate();
  });

  Finder inSheet(Finder finder) => find.descendant(of: find.byType(BottomSheet), matching: finder);

  // The glyph the toast on screen leads with, if it has one.
  IconData? toastGlyph(WidgetTester tester) {
    final icons = find.descendant(of: find.byType(SnackBar).last, matching: find.byType(Icon));
    return icons.evaluate().isEmpty ? null : tester.widget<Icon>(icons.first).icon;
  }

  Future<void> openMenu(WidgetTester tester, String entry) async {
    await tester.tap(find.byTooltip(en.chatMenuTooltip));
    await pumpFrames(tester, frames: 3);
    await tester.tap(find.byKey(ValueKey('chat-menu-$entry')));
    await pumpFrames(tester, frames: 4);
  }

  // Typed and sent from the composer.
  Future<void> send(WidgetTester tester, String body) async {
    await tester.enterText(find.descendant(of: find.byType(ChatComposerBar), matching: find.byType(TextField)), body);
    await pumpFrames(tester, frames: 2);
    await tester.tap(find.bySemanticsLabel(en.chatSendAction));
    await pumpFrames(tester, frames: 6);
  }

  // The app's own router: its lock guard, and the stack it keeps over a
  // lock. The chat is opened from Chats, so Back leads there.
  Future<void> withAppRouter(WidgetTester tester, Future<void> Function(LayoutWorld world, GoRouter router) body) async {
    usePhoneView(tester, phoneSmall);
    final world = await LayoutWorld.create(identities: identities, account: LayoutAccount.signedIn, locale: 'en');
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
      await body(world, router);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      world.dispose();
    }
  }

  // Reports the peer for spam from the chat's menu, without blocking them.
  Future<void> reportSpam(WidgetTester tester) async {
    await openMenu(tester, 'report');
    await tester.tap(find.text(en.reportReasonSpam));
    await pumpFrames(tester, frames: 4);
    await tester.tap(find.byKey(const ValueKey('report-also-block')));
    await pumpFrames(tester, frames: 2);
    await tester.tap(find.byKey(const ValueKey('report-confirm')));
    await pumpFrames(tester, frames: 6);
  }

  List<String> relayed(LayoutWorld world) => [
        for (final message in world.relay.conversations[chatConversationId]!.messages) message['clientMessageId'] as String,
      ];

  testWidgets('a block from the chat asks first, takes the composer\'s place, and Unblock gives it back', (tester) async {
    await withPhoneApp(tester, identities, location: _chat, body: (world) async {
      await openMenu(tester, 'block');
      expect(find.text(en.blockConfirmTitle(peerHandle)), findsOneWidget);
      expect(find.text(en.blockConfirmBody), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('block-confirm')));
      await pumpFrames(tester, frames: 4);

      expect(world.relay.blocks['user-$selfHandle']?.keys, ['user-$peerHandle']);
      expect(find.text(en.blockedComposerLine(peerHandle)), findsOneWidget);
      expect(find.byType(ChatComposerBar), findsNothing, reason: 'the server refuses what is sent to a blocked account');
      await tester.tap(find.byTooltip(en.chatMenuTooltip));
      await pumpFrames(tester, frames: 3);
      expect(find.byKey(const ValueKey('chat-menu-unblock')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-menu-block')), findsNothing);
      // Nothing can be sent here, so there is no timer for it.
      expect(find.byKey(const ValueKey('chat-menu-timer')), findsNothing);
      await tester.tapAt(const Offset(20, 300));
      await pumpFrames(tester, frames: 3);

      final before = relayed(world).length;
      await tester.tap(find.widgetWithText(TextButton, en.unblockAction));
      await pumpFrames(tester, frames: 4);
      expect(world.relay.blocks['user-$selfHandle'], isEmpty);
      expect(find.text(en.blockedComposerLine(peerHandle)), findsNothing);
      expect(find.byType(ChatComposerBar), findsOneWidget);

      await send(tester, 'delivered');
      expect(relayed(world), hasLength(before + 1));
      await tester.tap(find.byTooltip(en.chatMenuTooltip));
      await pumpFrames(tester, frames: 3);
      expect(find.byKey(const ValueKey('chat-menu-timer')), findsOneWidget, reason: 'the timer is back with the composer');
      await tester.tapAt(const Offset(20, 300));
      await pumpFrames(tester, frames: 3);
      expect(tester.takeException(), isNull);
    });
  });

  // The menu's items are built when it opens, but what a tap does is looked
  // up when it lands. An item that changed in between (here a block lands
  // from elsewhere while the menu is open, turning Block into Unblock) does
  // nothing, rather than what now sits at its place in the list.
  testWidgets('a menu item that changed while the menu was open does nothing, not the action now in its place',
      (tester) async {
    await withPhoneApp(tester, identities, location: _chat, body: (world) async {
      await tester.tap(find.byTooltip(en.chatMenuTooltip));
      await pumpFrames(tester, frames: 3);
      expect(find.byKey(const ValueKey('chat-menu-block')), findsOneWidget);

      await tester.runAsync(
        () => world.container.read(blockedAccountsProvider).block('user-$peerHandle', handle: peerHandle),
      );
      await pumpFrames(tester, frames: 2);
      expect(world.relay.blocks['user-$selfHandle']?.keys, ['user-$peerHandle']);

      await tester.tap(find.byKey(const ValueKey('chat-menu-block')));
      await pumpFrames(tester, frames: 4);
      expect(world.relay.blocks['user-$selfHandle']?.keys, ['user-$peerHandle'], reason: 'tapping Block unblocked');
      expect(find.text(en.unblockDone(peerHandle)), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text(en.blockedComposerLine(peerHandle)), findsOneWidget);
    });
  });

  // The relay refuses a 1:1 send across a block in either direction: once
  // the peer blocks the user, what the user sends stays with them, not sent.
  testWidgets('a send to someone who blocked the user is refused and shown as not sent', (tester) async {
    await withPhoneApp(tester, identities, location: _chat, body: (world) async {
      world.relay.blocks['user-$peerHandle'] = {'user-$selfHandle': DateTime.utc(2026, 4, 7)};
      final before = relayed(world).length;
      await send(tester, 'not delivered');
      expect(relayed(world), hasLength(before));
      expect(world.messenger.messagesFor(chatConversationId).last.hasFailed, isTrue);
      expect(find.text(en.chatNotSentTapToRetry), findsOneWidget);
      // In the app's words, not the server's.
      expect(findCopy(en.errorPeerUnreachable), findsOneWidget);
      expect(findCopyContaining('Peer'), findsNothing);

      world.relay.blocks.remove('user-$peerHandle');
      await tester.tap(find.text(en.chatNotSentTapToRetry));
      await pumpFrames(tester, frames: 6);
      expect(relayed(world), hasLength(before + 1));
    });
  });

  testWidgets('a report from the chat sends the account, the reason and the chat, and blocks by default',
      (tester) async {
    await withPhoneApp(tester, identities, location: _chat, body: (world) async {
      await openMenu(tester, 'report');
      expect(find.text(en.reportTitle(peerHandle)), findsOneWidget);
      // The sheet is the reasons alone; a tap on one asks in a dialog.
      expect(inSheet(find.byType(FilledButton)), findsNothing);
      expect(inSheet(find.byType(Switch)), findsNothing);

      await tester.tap(find.text(en.reportReasonHarassment));
      await pumpFrames(tester, frames: 4);
      expect(find.text(en.reportConfirmTitle(peerHandle)), findsOneWidget);
      expect(find.text(en.reportFooterChat), findsOneWidget);
      expect(
        tester.widget<CheckboxListTile>(find.byKey(const ValueKey('report-also-block'))).value,
        isTrue,
        reason: 'Also block is ticked by default',
      );
      await tester.tap(find.byKey(const ValueKey('report-confirm')));
      await pumpFrames(tester, frames: 6);

      expect(world.relay.reports.single.fields, {
        'reportedUserId': 'user-$peerHandle',
        'reason': 'harassment',
        'conversationId': chatConversationId,
      });
      expect(world.relay.blocks['user-$selfHandle']?.keys, ['user-$peerHandle']);
      expect(findCopy(en.reportSentAndBlocked(peerHandle)), findsOneWidget);
      expect(find.text(en.blockedComposerLine(peerHandle)), findsOneWidget);
    });
  });

  testWidgets('a report from a message names it, and with Also block off blocks no one', (tester) async {
    await withPhoneApp(tester, identities, location: _chat, body: (world) async {
      // Only someone else's message offers it.
      await tester.longPress(find.text(latestOwnChatLine));
      await pumpFrames(tester, frames: 4);
      expect(find.byKey(const ValueKey('message-report')), findsNothing, reason: 'our own message offered a report');
      await tester.tapAt(const Offset(20, 20));
      await pumpFrames(tester, frames: 4);

      await tester.longPress(find.text(latestChatLine));
      await pumpFrames(tester, frames: 4);
      await tester.tap(find.byKey(const ValueKey('message-report')));
      await pumpFrames(tester, frames: 4);

      await tester.tap(find.text(en.reportReasonScam));
      await pumpFrames(tester, frames: 4);
      expect(find.text(en.reportFooterMessage), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('report-also-block')));
      await pumpFrames(tester, frames: 2);
      await tester.tap(find.byKey(const ValueKey('report-confirm')));
      await pumpFrames(tester, frames: 6);

      final reported = world.messenger.messagesFor(chatConversationId).firstWhere(
            (message) => message.id == world.relay.reports.single.fields['messageId'],
          );
      expect(reported.isMine, isFalse);
      expect(world.relay.reports.single.fields, {
        'reportedUserId': 'user-$peerHandle',
        'reason': 'scam',
        'conversationId': chatConversationId,
        'messageId': reported.id,
      });
      expect(world.relay.blocks['user-$selfHandle'], isNull);
      expect(findCopy(en.reportSent), findsOneWidget);
    });
  });

  // The server refuses a reaction to someone blocked, so none is offered.
  testWidgets('in a 1:1 with someone blocked, a message\'s sheet offers Report and no reactions', (tester) async {
    await withPhoneApp(
      tester,
      identities,
      location: _chat,
      attention: const ChatAttention(peerBlocked: true),
      body: (world) async {
        await tester.longPress(find.text(latestChatLine));
        await pumpFrames(tester, frames: 4);
        expect(find.byKey(const ValueKey('message-report')), findsOneWidget);
        expect(find.byType(ReactionPickerWidget), findsNothing);
      },
    );
  });

  testWidgets('a group message is reported as its writer\'s, with no offer to block', (tester) async {
    await withPhoneApp(tester, identities, withGroup: true, location: '/chat/$groupConversationId', body: (world) async {
      await tester.longPress(find.text('14th works for me'));
      await pumpFrames(tester, frames: 4);
      await tester.tap(find.byKey(const ValueKey('message-report')));
      await pumpFrames(tester, frames: 4);
      expect(find.text(en.reportTitle('priya')), findsOneWidget);

      await tester.tap(find.text(en.reportReasonOther));
      await pumpFrames(tester, frames: 4);
      expect(find.byKey(const ValueKey('report-also-block')), findsNothing);
      await pumpFrames(tester, frames: 2);
      await tester.tap(find.byKey(const ValueKey('report-confirm')));
      await pumpFrames(tester, frames: 6);
      final fields = world.relay.reports.single.fields;
      expect(fields['reportedUserId'], 'user-priya');
      expect(fields['conversationId'], groupConversationId);
      expect(fields.keys.toSet(), {'reportedUserId', 'reason', 'conversationId', 'messageId'});

      // The group's menu mutes it; reporting and blocking are per person.
      await tester.tap(find.byTooltip(en.chatMenuTooltip));
      await pumpFrames(tester, frames: 3);
      expect(find.byKey(const ValueKey('chat-menu-mute')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-menu-report')), findsNothing);
      expect(find.byKey(const ValueKey('chat-menu-block')), findsNothing);
    });
  });

  testWidgets('a report the server refuses says so with Retry, which sends it', (tester) async {
    await withPhoneApp(tester, identities, location: _chat, body: (world) async {
      world.relay.refuseReports = 1;
      await openMenu(tester, 'report');
      await tester.tap(find.text(en.reportReasonSpam));
      await pumpFrames(tester, frames: 4);
      await tester.tap(find.byKey(const ValueKey('report-also-block')));
      await pumpFrames(tester, frames: 2);
      await tester.tap(find.byKey(const ValueKey('report-confirm')));
      await pumpFrames(tester, frames: 6);
      expect(findCopy(en.reportFailed), findsOneWidget);
      expect(world.relay.reports, isEmpty);

      await tester.tap(find.widgetWithText(SnackBarAction, en.commonRetry));
      await pumpFrames(tester, frames: 6);
      expect(world.relay.reports.single.fields['reason'], 'spam');
      expect(findCopy(en.reportSent), findsOneWidget);
    });
  });

  // A toast lives above every screen. One with Retry used to stay until it
  // was tapped, follow the user to other screens, and do nothing there.
  testWidgets('a failed report\'s line closes by itself, and its Retry still sends the report from Chats',
      (tester) async {
    await withAppRouter(tester, (world, router) async {
      world.relay.refuseReports = 1;
      await reportSpam(tester);
      expect(findCopy(en.reportFailed), findsOneWidget);
      await tester.pump(const Duration(seconds: 9));
      await pumpFrames(tester);
      expect(find.byType(SnackBar), findsNothing, reason: 'the line stayed up');
      expect(world.relay.reports, isEmpty);

      world.relay.refuseReports = 1;
      await reportSpam(tester);
      expect(findCopy(en.reportFailed), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await pumpFrames(tester);
      expect(find.byType(ConversationListScreen), findsOneWidget);
      expect(find.byType(ChatRoomScreen), findsNothing);

      await tester.tap(find.widgetWithText(SnackBarAction, en.commonRetry));
      await pumpFrames(tester, frames: 6);
      expect(world.relay.reports.single.fields, {
        'reportedUserId': 'user-$peerHandle',
        'reason': 'spam',
        'conversationId': chatConversationId,
      });
      expect(findCopy(en.reportSent), findsOneWidget);
    });
  });

  testWidgets('locking takes a toast down: nothing of it shows on the lock screen or after the unlock',
      (tester) async {
    await withAppRouter(tester, (world, router) async {
      world.relay.refuseReports = 1;
      await reportSpam(tester);
      expect(findCopy(en.reportFailed), findsOneWidget);

      final session = world.container.read(appSessionProvider.notifier);
      session.lock();
      await pumpFrames(tester, frames: 6);
      expect(find.byType(AppLockScreen), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing, reason: 'the toast showed on the lock screen');

      session.unlock();
      await pumpFrames(tester, frames: 6);
      expect(find.byType(ChatRoomScreen), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(world.relay.reports, isEmpty);
    });
  });

  testWidgets('a report the server answers while the app is locked says nothing on the lock screen', (tester) async {
    await withAppRouter(tester, (world, router) async {
      final gate = world.relay.reportGate = Completer<void>();
      await reportSpam(tester);
      final session = world.container.read(appSessionProvider.notifier);
      session.lock();
      await pumpFrames(tester, frames: 6);

      gate.complete();
      await pumpFrames(tester, frames: 6);
      expect(world.relay.reports, hasLength(1));
      expect(find.byType(AppLockScreen), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing, reason: 'the outcome showed on the lock screen');
    });
  });

  testWidgets('muting from the chat tells the server, marks the row, and Unmute undoes it', (tester) async {
    await withPhoneApp(tester, identities, location: _chat, body: (world) async {
      await openMenu(tester, 'mute');
      expect(find.text(en.muteTitle), findsWidgets);
      await tester.tap(find.text(en.muteEightHours));
      await pumpFrames(tester, frames: 4);
      expect(world.relay.mutes['user-$selfHandle'], {chatConversationId: 8 * 3600});
      expect(findCopy(en.muteDoneFor(en.muteEightHours)), findsOneWidget);
      // With the success glyph, as '@x blocked' and 'Report sent' are.
      expect(toastGlyph(tester), VeilNotice.iconFor(VeilTone.good));
      final kept = await tester.runAsync(() => MuteStore(world.storage.scoped(SecureScope.notifications)).read());
      expect(kept!.keys, [chatConversationId], reason: 'the mute is kept on this phone');

      // Muted for good from the list's row is shown there.
      await openMenu(tester, 'unmute');
      expect(world.relay.mutes['user-$selfHandle'], isEmpty);
      expect(findCopy(en.muteUndone), findsOneWidget);
      expect(toastGlyph(tester), VeilNotice.iconFor(VeilTone.good));
      await openMenu(tester, 'mute');
      await tester.tap(find.text(en.muteAlways));
      await pumpFrames(tester, frames: 4);
      expect(world.relay.mutes['user-$selfHandle'], {chatConversationId: null});

      await tester.tap(find.byTooltip('Back'));
      await pumpFrames(tester);
      final row = find.ancestor(of: find.text('Sam Rivera'), matching: find.byType(ConversationRow));
      expect(tester.widget<ConversationRow>(row).muted, isTrue);
      expect(find.descendant(of: row, matching: find.byIcon(Icons.notifications_off_outlined)), findsOneWidget);
      final other = find.ancestor(of: find.text('Priya Nair'), matching: find.byType(ConversationRow));
      expect(tester.widget<ConversationRow>(other).muted, isFalse);
    });
  });

  testWidgets('the blocked accounts list shows each with Unblock, and is empty once all are unblocked',
      (tester) async {
    await withPhoneApp(
      tester,
      identities,
      location: '/settings',
      attention: const ChatAttention(peerBlocked: true),
      body: (world) async {
        final row = find.byKey(const ValueKey('settings-blocked-accounts'));
        expect(find.descendant(of: row, matching: find.text('2')), findsOneWidget, reason: 'the row counts them');
        await tester.tap(row);
        await pumpFrames(tester);
        expect(find.byType(BlockedAccountsScreen), findsOneWidget);
        expect(find.byType(BlockedAccountRow), findsNWidgets(2));
        // A name and the @handle where this phone knows a name; the @handle
        // alone where not, never a bare handle.
        expect(find.text('Sam Rivera'), findsOneWidget);
        expect(find.text('@$peerHandle'), findsOneWidget);
        expect(find.text('@tom_walsh'), findsOneWidget);
        expect(find.text('tom_walsh'), findsNothing);

        Finder unblockOf(String handle) => find.descendant(
              of: find.byKey(ValueKey('blocked-$handle')),
              matching: find.widgetWithText(TextButton, en.unblockAction),
            );
        await tester.tap(unblockOf(peerHandle));
        await pumpFrames(tester, frames: 4);
        expect(world.relay.blocks['user-$selfHandle']?.keys, ['user-tom_walsh']);
        expect(find.byType(BlockedAccountRow), findsOneWidget);

        await tester.tap(unblockOf('tom_walsh'));
        await pumpFrames(tester, frames: 4);
        expect(world.relay.blocks['user-$selfHandle'], isEmpty);
        // One quiet line, nothing under it.
        expect(find.text(en.blockedAccountsEmptyTitle), findsOneWidget);
        expect(find.byType(VeilEmptyState), findsNothing);

        await tester.tap(find.byTooltip('Back'));
        await pumpFrames(tester);
        expect(find.descendant(of: row, matching: find.text('2')), findsNothing);
      },
    );
  });

  testWidgets('a contact is blocked from their sheet, which then offers Unblock', (tester) async {
    await withPhoneApp(tester, identities, location: '/contacts', body: (world) async {
      await tester.tap(find.text('Mia Chen'));
      await pumpFrames(tester, frames: 4);
      await tester.tap(find.byKey(const ValueKey('contact-block')));
      await pumpFrames(tester, frames: 4);
      expect(find.text(en.blockConfirmTitle('mia')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('block-confirm')));
      await pumpFrames(tester, frames: 6);
      expect(world.relay.blocks['user-$selfHandle']?.keys, ['user-mia']);
      expect(findCopy(en.blockDone('mia')), findsOneWidget);

      await tester.tap(find.text('Mia Chen'));
      await pumpFrames(tester, frames: 4);
      expect(find.byKey(const ValueKey('contact-block')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('contact-unblock')));
      await pumpFrames(tester, frames: 6);
      expect(world.relay.blocks['user-$selfHandle'], isEmpty);
      expect(findCopy(en.unblockDone('mia')), findsOneWidget);
    });
  });

  // A contact with no chat yet is found through the server's lookup.
  testWidgets('a contact with no chat is reported by the account the server names', (tester) async {
    await withPhoneApp(
      tester,
      identities,
      location: '/contacts',
      prepare: (world) async {
        world.relay.conversations.remove('conv-mia');
        return null;
      },
      body: (world) async {
        await tester.tap(find.text('Mia Chen'));
        await pumpFrames(tester, frames: 4);
        await tester.tap(find.byKey(const ValueKey('contact-report')));
        await pumpFrames(tester, frames: 6);
        await tester.tap(find.text(en.reportReasonImpersonation));
        await pumpFrames(tester, frames: 4);
        expect(find.text(en.reportFooterAccount), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('report-also-block')));
        await pumpFrames(tester, frames: 2);
        await tester.tap(find.byKey(const ValueKey('report-confirm')));
        await pumpFrames(tester, frames: 6);
        expect(world.relay.reports.single.fields, {'reportedUserId': 'user-mia', 'reason': 'impersonation'});
      },
    );
  });

  testWidgets('a muted chat\'s unread count is grey, and a screen reader hears it is muted', (tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
        body: ConversationRow(
          title: 'Sam Rivera',
          seed: peerHandle,
          snippet: 'See you',
          timestamp: '09:45',
          semanticLabel: 'Chat with Sam Rivera',
          unreadCount: 3,
          muted: true,
          mutedLabel: en.conversationsMutedSemantics,
        ),
      ),
    ));
    final badge = tester.widget<UnreadBadge>(find.byType(UnreadBadge));
    expect(badge.muted, isTrue);
    expect(find.byIcon(Icons.notifications_off_outlined), findsOneWidget);
    expect(
      find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == 'Chat with Sam Rivera, Muted'),
      findsOneWidget,
    );
  });
}
