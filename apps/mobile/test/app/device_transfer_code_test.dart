import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/device_transfer/presentation/device_transfer_code.dart';
import 'package:veil_mobile/src/features/device_transfer/presentation/device_transfer_new_device_panel.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';

import '../layout/support/phone_layout_probe.dart' show loadTestFonts;

// The codes a move passes between two phones, as the user sees and types
// them.

// The relay's claim id is randomUUID(): 36 characters.
const _claimId = '3f2b9c7e-5a14-4d0b-9e2f-8c61a7d4b250';

void main() {
  group('transfer code', () {
    test('the box shows it without the prefix the copied code starts with', () {
      expect(transferCodeForDisplay('VEIL_TRANSFER::session-1::token-1'), 'session-1::token-1');
      expect(transferCodeForDisplay('session-1::token-1'), 'session-1::token-1');
    });

    test('is read as copied, as the box shows it, or as two labelled lines', () {
      for (final raw in [
        'VEIL_TRANSFER::session-1::token-1',
        'session-1::token-1',
        'session session-1\ntoken token-1',
      ]) {
        final parsed = parseTransferCode(raw);
        expect(parsed, isNotNull, reason: raw);
        expect(parsed!.sessionId, 'session-1', reason: raw);
        expect(parsed.transferToken, 'token-1', reason: raw);
      }
    });

    test('anything else is not a code', () {
      for (final raw in [
        '',
        'session-1',
        'VEIL_TRANSFER::session-1',
        'VEIL_TRANSFER::session-1::',
        '::token-1',
        'a::b::c',
        'session 1::token-1',
      ]) {
        expect(parseTransferCode(raw), isNull, reason: raw);
      }
    });
  });

  group('TransferClaimCode', () {
    // Real glyphs (the probe's Roboto under `monospace`), not the test
    // font's squares, so widths are near a phone's.
    setUpAll(loadTestFonts);

    Future<void> pump(WidgetTester tester, Size size, {required bool light, double textScale = 1}) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: light ? VeilTheme.light() : VeilTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(size: size, textScaler: TextScaler.linear(textScale)),
          child: const Scaffold(
            body: Padding(
              padding: EdgeInsets.symmetric(horizontal: VeilSpace.md),
              child: Center(child: TransferClaimCode(_claimId)),
            ),
          ),
        ),
      ));
    }

    test('is cut only after a hyphen', () {
      expect(TransferClaimCode.groupsOf(_claimId), ['3f2b9c7e-', '5a14-', '4d0b-', '9e2f-', '8c61a7d4b250']);
      expect(TransferClaimCode.groupsOf(_claimId).join(), _claimId);
      expect(TransferClaimCode.groupsOf('claim-7'), ['claim-', '7']);
      expect(TransferClaimCode.groupsOf('abc'), ['abc']);
    });

    // A display style outside the scale (36sp) with letter spacing wrapped
    // the code over three lines, breaking "4d0b" in the middle.
    for (final (size, light, scale) in [
      (const Size(360, 640), false, 1.0),
      (const Size(390, 844), true, 1.0),
      (const Size(360, 640), false, 1.3),
    ]) {
      testWidgets(
          'at ${size.width.toInt()}x${size.height.toInt()} ${light ? 'light' : 'dark'}, text x$scale: '
          'a scale style in monospace with no tracking, no group split, inside the screen', (tester) async {
        await pump(tester, size, light: light, textScale: scale);
        final context = tester.element(find.byType(TransferClaimCode));
        final headline = Theme.of(context).textTheme.headlineMedium!;
        final groups = find.descendant(of: find.byType(TransferClaimCode), matching: find.byType(Text));
        expect(groups, findsNWidgets(5));
        final lineHeight = headline.fontSize! * headline.height! * scale;
        for (final element in groups.evaluate()) {
          final text = element.widget as Text;
          expect(text.style!.fontSize, headline.fontSize);
          expect(text.style!.fontFamily, 'monospace');
          expect(text.style!.letterSpacing, 0);
          final rect = tester.getRect(find.byWidget(text));
          expect(rect.height, lessThan(lineHeight * 1.5), reason: '"${text.data}" wraps inside itself');
          expect(rect.left, greaterThanOrEqualTo(VeilSpace.md - 0.5));
          expect(rect.right, lessThanOrEqualTo(size.width - VeilSpace.md + 0.5));
        }
        // Read whole by a screen reader.
        final handle = tester.ensureSemantics();
        expect(find.bySemanticsLabel(_claimId), findsOneWidget);
        handle.dispose();
      });
    }
  });
}
