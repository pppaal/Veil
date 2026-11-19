import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/shared/presentation/veil_ui.dart';

import '../support/copy_finder.dart';
import 'phone_app.dart';

// The profile on a phone: the avatar, the name and the handle (a tap copies
// it), then the name in one field row with the one line on who sees it, all
// on the first screenful; the name is edited in place and saved from the
// bar.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LayoutIdentities identities;
  final en = lookupAppLocalizations(const Locale('en'));

  setUpAll(() async {
    await loadBundledFonts();
    identities = await LayoutIdentities.generate();
  });

  Finder field() => find.byKey(const ValueKey('profile-nickname'), skipOffstage: false);

  testWidgets('opens on the avatar, the name and the handle, with the nickname field under them', (tester) async {
    await withPhoneApp(tester, identities, location: '/profile', body: (world) async {
      final avatar = tester.getRect(find.byType(VeilAvatar));
      final name = tester.getRect(find.text(selfDisplayName).first);
      final handle = tester.getRect(find.text('@$selfHandle'));
      final nickname = tester.getRect(field());
      expect(avatar.size, const Size(72, 72));
      expect(avatar.bottom, lessThan(name.top));
      expect(name.bottom, lessThan(handle.top));
      expect(handle.bottom, lessThan(nickname.top));
      expect(nickname.bottom, lessThanOrEqualTo(640 * 0.75), reason: 'editing is on the first screenful');
      expect(tester.getSize(find.ancestor(of: field(), matching: find.byType(ConstrainedBox)).first).height,
          greaterThanOrEqualTo(44));
      expect(tester.widget<TextField>(field()).controller!.text, selfDisplayName);
      // Said once, under the field; nothing is a notice.
      expect(findCopy(en.profileNicknameFooter), findsOneWidget);
      expect(find.byType(VeilNotice), findsNothing);
      // Nothing to save until the nickname changes.
      expect(find.widgetWithText(TextButton, en.profileSaveNickname), findsNothing);
      // The header names the field on screen; a screen reader hears the
      // name on the field itself.
      final semantics = tester.ensureSemantics();
      await tester.pump();
      expect(tester.getSemantics(field()).label, contains(en.profileNicknameHeader));
      semantics.dispose();
    });
  });

  testWidgets('the name is edited in place and saved from the bar; an empty one clears it', (tester) async {
    await withPhoneApp(tester, identities, location: '/profile', keyboardHeight: 300, body: (world) async {
      String? nickname() => world.container.read(appSessionProvider).displayName;
      final save = find.byKey(const ValueKey('profile-save'), skipOffstage: false);

      await tester.enterText(field(), 'Someone else');
      await pumpFrames(tester, frames: 2);
      expect(nickname(), selfDisplayName, reason: 'typing alone saves nothing');
      expect(save, findsOneWidget);
      // "Save" is in the bar, above the keyboard whatever is scrolled.
      expect(tester.getRect(save).bottom, lessThanOrEqualTo(640 - 300));
      expect(tester.getRect(save).bottom, lessThan(tester.getRect(field()).top));

      await tester.tap(save);
      await pumpFrames(tester, frames: 3);
      expect(nickname(), 'Someone else');
      expect(save, findsNothing, reason: 'nothing left to save');
      expect(findCopy(en.profileNicknameSaved), findsOneWidget);
      expect(find.text('Someone else', skipOffstage: false), findsWidgets);

      // An empty one, sent from the keyboard, clears it: the handle stands
      // for the user again.
      await tester.enterText(field(), '  ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await pumpFrames(tester, frames: 3);
      expect(nickname(), isNull);
      expect(find.text('@$selfHandle', skipOffstage: false), findsOneWidget);
    });
  });

  testWidgets('a tap on the handle copies it', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await withPhoneApp(tester, identities, location: '/profile', body: (world) async {
      await tester.tap(find.byKey(const ValueKey('profile-handle')));
      await pumpFrames(tester, frames: 2);
      expect(copied, ['@$selfHandle']);
      expect(findCopy(en.profileHandleCopied), findsOneWidget);
    });
  });
}
