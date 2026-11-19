import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:veil_mobile/src/features/attachments/data/image_preparer.dart';
import 'package:veil_mobile/src/features/attachments/presentation/photo_send_screen.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';

// The photo preview leaves nothing of the photo behind once it closes: its
// decoded pixels leave the image cache with it. Its Send is a full-screen
// page's: a 48dp circle at the bottom end, not the composer's 32dp one.

void main() {
  testWidgets('Send is a 48dp circle with a 24dp arrow at the bottom end', (tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: PhotoSendScreen(prepared: Completer<PreparedImage?>().future),
    ));
    await tester.pump();
    final send = find.byKey(const ValueKey('photo-send-send'));
    final circle = tester.getSize(find.descendant(of: send, matching: find.byType(DecoratedBox)));
    expect(circle, const Size.square(48));
    expect(tester.widget<Icon>(find.descendant(of: send, matching: find.byType(Icon))).size, 24);
    final screen = tester.getRect(find.byType(PhotoSendScreen));
    final rect = tester.getRect(send);
    expect(screen.right - rect.right, lessThanOrEqualTo(16));
    expect(screen.bottom - rect.bottom, lessThanOrEqualTo(24));
  });

  testWidgets('the previewed photo leaves the image cache when the preview closes', (tester) async {
    final bytes = Uint8List.fromList(img.encodeJpg(img.Image(width: 8, height: 6), quality: 80));
    final prepared = Completer<PreparedImage?>();
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: PhotoSendScreen(prepared: prepared.future),
    ));
    prepared.complete(PreparedImage(bytes: bytes, contentType: 'image/jpeg', width: 8, height: 6));
    await tester.pump();

    final shown = find.descendant(of: find.byType(PhotoSendScreen), matching: find.byType(Image));
    expect(shown, findsOneWidget);
    final photo = tester.widget<Image>(shown).image;
    await tester.runAsync(() => precacheImage(photo, tester.element(shown)));
    await tester.pump();
    final cache = PaintingBinding.instance.imageCache;
    expect(cache.statusForKey(photo).tracked, isTrue, reason: 'the photo was never decoded');

    await tester.pumpWidget(const SizedBox.shrink());
    expect(cache.statusForKey(photo).untracked, isTrue, reason: 'the photo stayed in the image cache');
  });
}
