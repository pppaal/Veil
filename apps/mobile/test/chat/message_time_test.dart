import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:veil_mobile/src/features/chat/presentation/message_time.dart';
import 'package:veil_mobile/src/features/device_transfer/presentation/device_transfer_code.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';

// When a message was sent, as Signal, WhatsApp and the web app say it: the
// time for today, "Yesterday", the short weekday for the six days before,
// then the short date (the web's listDate in apps/web-demo/lib/format.js,
// with these cases in its __tests__/format.test.js). The time of day
// follows the phone's 24-hour setting.

final _en = lookupAppLocalizations(const Locale('en'));
late final MessageTimeFormat _twelveHour;
late final MessageTimeFormat _twentyFourHour;

// Tuesday, April 7, 2026, 10:20 in the morning.
final _now = DateTime(2026, 4, 7, 10, 20);

void main() {
  // The app's localizations load the date names; a bare test loads them.
  setUpAll(() async {
    await initializeDateFormatting('en');
    _twelveHour = MessageTimeFormat(_en, use24HourFormat: false);
    _twentyFourHour = MessageTimeFormat(_en, use24HourFormat: true);
  });

  group('the time of day', () {
    test('follows the 24-hour setting', () {
      expect(_twentyFourHour.timeOfDay(DateTime(2026, 4, 7, 9, 5)), '09:05');
      expect(_twentyFourHour.timeOfDay(DateTime(2026, 4, 7, 13, 45)), '13:45');
      expect(_twelveHour.timeOfDay(DateTime(2026, 4, 7, 9, 5)), '9:05 AM');
      expect(_twelveHour.timeOfDay(DateTime(2026, 4, 7, 13, 45)), '1:45 PM');
      expect(_twelveHour.timeOfDay(DateTime(2026, 4, 7, 0, 10)), '12:10 AM');
    });

    // The locale's own pattern has a narrow no-break space before "AM",
    // which a font without it (the store art's Roboto) draws as a box.
    test('keeps "AM" with the time by a no-break space every font has', () {
      final text = _twelveHour.timeOfDay(DateTime(2026, 4, 7, 9, 5));
      expect(text, isNot(contains(' ')));
      expect(text, isNot(contains(' ')), reason: 'a plain space could wrap "AM" onto a line of its own');
    });

    test('is the phone\'s local time, also for a time the server sent in UTC', () {
      final utc = DateTime.utc(2026, 4, 7, 9, 5);
      expect(_twentyFourHour.timeOfDay(utc), _twentyFourHour.timeOfDay(utc.toLocal()));
    });

    // A one-time link's and a move's expiry say the hour as the chats do.
    test('with a day, as an expiry says it, follows the 24-hour setting too', () {
      expect(_twelveHour.dayAndTime(DateTime(2026, 4, 8, 14, 5)), 'Apr 8 2:05\u00a0PM');
      expect(_twentyFourHour.dayAndTime(DateTime(2026, 4, 8, 14, 5)), 'Apr 8 14:05');
      expect(
        formatTransferExpiry(DateTime(2026, 4, 8, 14, 5), DateTime(2026, 4, 7, 10, 20), _en, timeFormat: _twelveHour),
        _en.deviceTransferExpiryAt('Apr 8 2:05\u00a0PM'),
      );
    });
  });

  group('a chat row and a search hit', () {
    String row(DateTime at, {MessageTimeFormat? format}) => (format ?? _twelveHour).listDate(at, now: _now);

    test('show the time for a message sent today', () {
      expect(row(DateTime(2026, 4, 7, 9, 45)), '9:45 AM');
      expect(row(DateTime(2026, 4, 7, 9, 45), format: _twentyFourHour), '09:45');
      expect(row(DateTime(2026, 4, 7, 0, 1)), '12:01 AM', reason: 'just after midnight is today');
    });

    test('say "Yesterday" for the day before, whatever the hour', () {
      expect(row(DateTime(2026, 4, 6, 23, 59)), 'Yesterday');
      expect(row(DateTime(2026, 4, 6, 0, 1)), 'Yesterday');
      expect(row(DateTime(2026, 4, 6, 20, 15), format: _twentyFourHour), 'Yesterday');
    });

    test('show the short weekday for the six days before that', () {
      expect(row(DateTime(2026, 4, 5, 12)), 'Sun');
      expect(row(DateTime(2026, 4, 4, 18, 40)), 'Sat');
      expect(row(DateTime(2026, 4, 1, 8)), 'Wed', reason: 'six days ago');
    });

    test('show the short date from a week back', () {
      expect(row(DateTime(2026, 3, 31, 23, 59)), 'Mar 31', reason: 'seven days ago, the same weekday as today');
      expect(row(DateTime(2026, 1, 2, 9)), 'Jan 2');
    });

    test('add the year to a date in another year', () {
      expect(row(DateTime(2025, 12, 31, 9)), 'Dec 31, 2025');
      expect(row(DateTime(2025, 4, 7, 9)), 'Apr 7, 2025');
    });

    // A phone whose clock is behind the server's sees a message from
    // "later": it is shown by its time, not as a day.
    test('show the time for a message stamped after now', () {
      expect(row(DateTime(2026, 4, 7, 10, 25)), '10:25 AM');
      expect(row(DateTime(2026, 4, 8, 0, 5)), '12:05 AM');
    });

    test('count calendar days across a clock change', () {
      expect(calendarDaysBetween(DateTime(2026, 3, 28, 23), DateTime(2026, 3, 29, 1)), 1);
      expect(calendarDaysBetween(DateTime(2026, 3, 25, 12), DateTime(2026, 4, 1, 12)), 7);
      expect(calendarDaysBetween(DateTime(2026, 10, 24, 12), DateTime(2026, 10, 26, 0, 30)), 2);
    });
  });

  testWidgets('reads the 24-hour setting from the phone', (tester) async {
    Future<String> timeWith({required bool use24Hour}) async {
      late String shown;
      await tester.pumpWidget(MediaQuery(
        data: MediaQueryData(alwaysUse24HourFormat: use24Hour),
        child: Localizations(
          locale: const Locale('en'),
          delegates: AppLocalizations.localizationsDelegates,
          child: Builder(builder: (context) {
            shown = MessageTimeFormat.of(context).timeOfDay(DateTime(2026, 4, 7, 21, 5));
            return const SizedBox.shrink();
          }),
        ),
      ));
      return shown;
    }

    expect(await timeWith(use24Hour: true), '21:05');
    expect(await timeWith(use24Hour: false), '9:05 PM');
  });
}
