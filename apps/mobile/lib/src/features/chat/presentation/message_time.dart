import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../../../l10n/generated/app_localizations.dart';

/// How this phone writes when a message was sent, in the phone's own time
/// zone: in a bubble the time of day; on a chat's row and on a message the
/// search found, the time for today and the day for anything older (as
/// Signal and WhatsApp do, and the web app).
///
/// The time of day follows the phone's setting: "14:05" where it is set to
/// 24-hour time, the locale's own form ("2:05 PM") where it is not.
class MessageTimeFormat {
  MessageTimeFormat(this._l10n, {required bool use24HourFormat})
      : _timeOfDay = use24HourFormat ? DateFormat.Hm(_l10n.localeName) : DateFormat.jm(_l10n.localeName);

  /// The format for the phone [context] is drawn on.
  factory MessageTimeFormat.of(BuildContext context) =>
      MessageTimeFormat(AppLocalizations.of(context), use24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context));

  final AppLocalizations _l10n;
  final DateFormat _timeOfDay;

  /// The time of day [at] was, where the phone is: "9:45 AM" or "09:45".
  String timeOfDay(DateTime at) =>
      // The locale's 12-hour form puts a narrow no-break space before "AM",
      // which fonts without that glyph (older Android's Roboto among them)
      // draw as a box. A no-break space keeps the two together as well.
      _timeOfDay.format(at.toLocal()).replaceAll(' ', ' ');

  /// A day and a time of day, as an expiry says it: "Apr 8 at 2:05 PM", or
  /// "Apr 8 at 14:05" on a phone set to 24-hour time.
  String dayAndTime(DateTime at) =>
      _l10n.dayAtTime(DateFormat.MMMd(_l10n.localeName).format(at.toLocal()), timeOfDay(at));

  /// When [at] was, as seen on [now]: the time of day for today,
  /// "Yesterday", the short weekday ("Mon") for the six days before, then
  /// the short date ("Mar 30"), with the year when it was not this year.
  String listDate(DateTime at, {required DateTime now}) {
    final local = at.toLocal();
    final today = now.toLocal();
    final daysAgo = calendarDaysBetween(local, today);
    if (daysAgo <= 0) return timeOfDay(local);
    if (daysAgo == 1) return _l10n.chatDayYesterday;
    if (daysAgo < 7) return DateFormat.E(_l10n.localeName).format(local);
    if (local.year == today.year) return DateFormat.MMMd(_l10n.localeName).format(local);
    return DateFormat.yMMMd(_l10n.localeName).format(local);
  }
}

/// How many calendar days [later] is after [earlier], each on the day it
/// falls on locally: 0 on the same day, 1 for the day before, whatever the
/// hours. A day with a clock change is 23 or 25 hours long, hence the
/// rounding.
int calendarDaysBetween(DateTime earlier, DateTime later) {
  final from = DateTime(earlier.year, earlier.month, earlier.day);
  final to = DateTime(later.year, later.month, later.day);
  return (to.difference(from).inHours / 24).round();
}
