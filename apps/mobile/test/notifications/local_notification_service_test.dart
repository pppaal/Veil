import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/notifications/local_notification_service.dart';

void main() {
  // Design system section 8: nothing counts on the app icon or the launcher.
  test('a message notification puts no count on the app icon or the launcher', () {
    const details = LocalNotificationService.messageDetails;
    final android = details.android!;
    expect(android.channelId, 'veil_messages');
    expect(android.channelShowBadge, isFalse, reason: 'launchers that count notifications would badge the icon');
    expect(android.number, isNull, reason: 'no badge number is set');
    expect(details.iOS!.badgeNumber, isNull, reason: 'no badge number is set');
    expect(details.macOS!.badgeNumber, isNull, reason: 'no badge number is set');
  });
}
