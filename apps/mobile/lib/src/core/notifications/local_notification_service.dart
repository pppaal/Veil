import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalNotificationService {
  static final LocalNotificationService _instance =
      LocalNotificationService._();
  factory LocalNotificationService() => _instance;
  LocalNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  void Function(String? conversationId)? onNotificationTapped;

  /// How a message notification shows. Nothing counts on the app icon or
  /// the launcher (design system section 8): the Android channel asks for
  /// no badge, so launchers that count notifications (Samsung's, Pixel's
  /// dot) leave Veil's icon alone, and no badge number is ever set.
  /// Android fixes a channel's settings when it is first created, so this
  /// holds for installs that create the channel from here on.
  static const messageDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'veil_messages',
      'Messages',
      channelDescription: 'New message notifications',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      channelShowBadge: false,
    ),
    iOS: _darwinDetails,
    macOS: _darwinDetails,
  );

  static const _darwinDetails = DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: true,
  );

  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _onTap,
    );

    _initialized = true;
  }

  Future<bool> requestPermission() async {
    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? false;
    }
    if (Platform.isIOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      return await ios?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
    return true;
  }

  Future<void> showMessageNotification({
    required String conversationId,
    required String title,
    required String body,
  }) async {
    if (!_initialized) return;

    await _plugin.show(
      id: conversationId.hashCode,
      title: title,
      body: body,
      notificationDetails: messageDetails,
      payload: conversationId,
    );
  }

  /// Takes back the notification [conversationId] raised, if it still
  /// shows: the chat was read on this phone.
  Future<void> cancelConversation(String conversationId) async {
    if (!_initialized) return;
    await _plugin.cancel(id: conversationId.hashCode);
  }

  void _onTap(NotificationResponse response) {
    onNotificationTapped?.call(response.payload);
  }
}
