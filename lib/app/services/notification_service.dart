import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService with WidgetsBindingObserver {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _fln = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;
  bool _isForeground = true;

  final _tapController = StreamController<int>.broadcast();
  Stream<int> get onNotificationTap => _tapController.stream;

  bool get isAppInForeground => _isForeground;

  Future<void> init() async {
    if (_isInitialized) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _fln.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (resp) {
        final payload = resp.payload;
        if (payload != null) {
          final id = int.tryParse(payload);
          if (id != null) _tapController.add(id);
        }
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    if (Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        'messages',
        'Messages',
        description: 'Message notifications',
        importance: Importance.high,
      );
      await _fln
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }

    WidgetsBinding.instance.addObserver(this);
    _isInitialized = true;
  }

  Future<void> showChatMessageNotification({
    required int chatId,
    required String title,
    required String body,
  }) async {
    const android = AndroidNotificationDetails(
      'messages',
      'Messages',
      channelDescription: 'Message notifications',
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: true,
      playSound: true,
      styleInformation: BigTextStyleInformation(''),
      category: AndroidNotificationCategory.message,
    );
    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final id = DateTime.now().millisecondsSinceEpoch.remainder(1 << 31);
    await _fln.show(
      id,
      title,
      body,
      const NotificationDetails(android: android, iOS: ios),
      payload: chatId.toString(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isForeground = state == AppLifecycleState.resumed;
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tapController.close();
  }
}

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  // No-op. onDidReceiveNotificationResponse will handle routing when app resumes.
}
