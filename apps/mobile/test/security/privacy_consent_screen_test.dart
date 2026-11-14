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
    return tester.widgetList<Text>(find.byType(Text)).map((text) => text.data ?? '').join('\n');
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

  testWidgets('says the same in Korean', (tester) async {
    final shown = await consentText(tester, const Locale('ko'));

    expect(shown, contains('앱 내 연락처 목록'));
    expect(shown, contains('통화 기록: '));
    expect(shown, contains('그룹·채널 이름과 설명'));
    expect(shown, isNot(contains('연락처, 통화 기록 등 디바이스 개인정보')));
    expect(shown, contains('휴대폰 주소록'));
  });

  testWidgets('states the agreement once, in the screen language', (tester) async {
    // The agreement sits under the lists, past the first screenful.
    Future<String> agreement(Locale locale) async {
      await consentText(tester, locale);
      await tester.scrollUntilVisible(find.byType(Checkbox), 300, scrollable: find.byType(Scrollable).first);
      return tester.widgetList<Text>(find.byType(Text)).map((text) => text.data ?? '').join('\n');
    }

    final english = await agreement(const Locale('en'));
    expect('I agree to the collection and use'.allMatches(english), hasLength(1));

    final korean = await agreement(const Locale('ko'));
    expect('위 개인정보 수집·이용에 동의합니다.'.allMatches(korean), hasLength(1));
    expect(korean, isNot(contains('I agree')));
  });
}
