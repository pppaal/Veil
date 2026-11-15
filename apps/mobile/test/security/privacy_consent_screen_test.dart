import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/onboarding/presentation/privacy_consent_screen.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';

// The consent the user must accept (PIPA Art. 15(2)) names what the server
// keeps about them, as docs/server-data-inventory.md lists it.
void main() {
  Future<String> consentText(WidgetTester tester, Locale locale) async {
    tester.view.physicalSize = const Size(1200, 6000);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: VeilTheme.dark(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const PrivacyConsentScreen(),
      ),
    ));
    await tester.pumpAndSettle();
    return _shown(tester);
  }

  testWidgets('lists the contact list, delivery metadata, call records and readable group names', (tester) async {
    final shown = await consentText(tester, const Locale('en'));

    expect(shown, contains('in-app contact list'));
    expect(shown, contains('read-receipt times'));
    expect(shown, contains('Call records'));
    expect(shown, contains('Group and channel names and descriptions (stored readable)'));
    expect(shown, contains('push token'));
    expect(shown, contains('device record within about 30 days'));
    // Only the phone's own address book and call log stay off the server.
    expect(shown, isNot(contains('Contacts, call logs')));
    expect(shown, contains("Your phone's address book, its call log"));
  });

  testWidgets('states the agreement once', (tester) async {
    // The agreement sits under the notice, on screen from the start.
    final english = await consentText(tester, const Locale('en'));
    expect('I agree to the collection and use'.allMatches(english), hasLength(1));
  });
}

// What the screen says, top to bottom.
String _shown(WidgetTester tester) => tester.widgetList<Text>(find.byType(Text)).map((text) => text.data ?? '').join('\n');
