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

  final _callActionController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onCallAction => _callActionController.stream;

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
          // Handle call notifications
          if (payload.startsWith('call:')) {
            final parts = payload.split(':');
            if (parts.length >= 4) {
              final chatId = int.tryParse(parts[1]);
              final callerId = int.tryParse(parts[2]);
              final callType = parts[3];
              
              if (chatId != null && callerId != null) {
                final action = resp.actionId ?? 'open';
                _callActionController.add({
                  'action': action,
                  'chatId': chatId,
                  'callerId': callerId,
                  'callType': callType,
                });
              }
            }
          } else {
            // Handle regular message notifications
            final id = int.tryParse(payload);
            if (id != null) _tapController.add(id);
          }
        }
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    if (Platform.isAndroid) {
      const messageChannel = AndroidNotificationChannel(
        'messages',
        'Messages',
        description: 'Message notifications',
        importance: Importance.high,
      );
      
      const callChannel = AndroidNotificationChannel(
        'calls',
        'Calls',
        description: 'Incoming call notifications',
        importance: Importance.max,
        enableVibration: true,
        playSound: true,
      );
      
      final androidPlugin = _fln
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      
      await androidPlugin?.createNotificationChannel(messageChannel);
      await androidPlugin?.createNotificationChannel(callChannel);
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

  Future<void> showIncomingCallNotification({
    required int chatId,
    required int callerId,
    required String callerName,
    required String callType, // 'audio' or 'video'
  }) async {
    final android = AndroidNotificationDetails(
      'calls',
      'Calls',
      channelDescription: 'Incoming call notifications',
      importance: Importance.max,
      priority: Priority.max,
      enableVibration: true,
      playSound: true,
      category: AndroidNotificationCategory.call,
      fullScreenIntent: true,
      ongoing: true,
      autoCancel: false,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          'decline_$chatId',
          'Decline',
          showsUserInterface: false,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          'accept_$chatId',
          'Accept',
          showsUserInterface: true,
          cancelNotification: true,
        ),
      ],
    );

    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.critical,
      categoryIdentifier: 'call_category',
    );

    final notificationId = chatId; // Use chatId as notification ID for easy tracking
    await _fln.show(
      notificationId,
      callType == 'audio' ? '📞 Incoming Call' : '📹 Incoming Video Call',
      '$callerName is calling...',
      NotificationDetails(android: android, iOS: ios),
      payload: 'call:$chatId:$callerId:$callType',
    );
  }

  Future<void> cancelCallNotification(int chatId) async {
    await _fln.cancel(chatId);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isForeground = state == AppLifecycleState.resumed;
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tapController.close();
    _callActionController.close();
  }
}

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  // No-op. onDidReceiveNotificationResponse will handle routing when app resumes.
}
