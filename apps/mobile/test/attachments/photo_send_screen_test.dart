import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:veil_mobile/src/features/attachments/data/image_preparer.dart';
import 'package:veil_mobile/src/features/attachments/presentation/photo_send_screen.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';

// The photo preview leaves nothing of the photo behind once it closes: its
// decoded pixels leave the image cache with it.

void main() {
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
