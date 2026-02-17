import 'dart:async';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/app/networking/chat_api_service.dart';
import 'package:flutter_app/app/services/callkit_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';


class NotificationService with WidgetsBindingObserver {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _fln = FlutterLocalNotificationsPlugin();
  final  _firebaseMessaging = FirebaseMessaging.instance;
  
  bool _isInitialized = false;
  bool _isForeground = true;

  final _tapController = StreamController<int>.broadcast();
  Stream<int> get onNotificationTap => _tapController.stream;

  final _callActionController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onCallAction => _callActionController.stream;

  bool get isAppInForeground => _isForeground;
  
  Future <void> initFCM() async {
    print("Initializing FCM...");
    await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      announcement: true,
    );
 
    final apnsToken = await FirebaseMessaging.instance.getAPNSToken();
    print('APNs Token: $apnsToken');
    final fcmToken = await _firebaseMessaging.getToken();
    print('FCM Token $fcmToken',);
    
    if(fcmToken != null){
      ChatApiService().updateFcmToken(fcmToken).then((value) => {
        print('FCM Token sent to server successfully: ${value?.message}'),
      }).catchError((error) {
        print('Error sending FCM Token to server: $error');
      });
    }else{
      // Alert the user that FCM token retrieval failed
      
    }
      
      
    
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      print('FCM Token refreshed: $newToken');
      ChatApiService().updateFcmToken(newToken).then((value) => {
        print('FCM Token sent to server successfully: ${value?.message}'),
      }).catchError((error) {
        print('Error sending FCM Token to server: $error');
      });
    });
    
    // Handle foreground messages, user actively using the app
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print("Received message in the foreground:");
      print('Received foreground message: ${message.messageId}');
      // final notification = message.notification;
      

      // if (notification != null) {
      //   final title = notification.title ?? 'New Message';
      //   final body = notification.body ?? '';
      //   final chatId = int.tryParse(message.data['chatId'] ?? '');
      //   if (chatId != null) {
      //     showChatMessageNotification(
      //       chatId: chatId,
      //       title: title,
      //       body: body,
      //     );
      //   }
      // }
    }, onError: (error) {
      print('Error receiving foreground message: $error');
    });

    // Handle notification taps when app is in background or terminated, user tap the notification and app opens
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print("Received message from notification tap:");
      print('Notification caused app to open: ${message.messageId}');
      print('Message data: ${message.data}');
      final chatId = int.tryParse(message.data['chatId'] ?? '');
      final type = message.data['type'] ?? 'message';
      
      if (chatId != null && type == 'message') {
        print("Routing to chatId: $chatId");
        _tapController.add(chatId);
      }
    }, onError: (error) {
      print('Error handling notification tap: $error');
    });


    // Handle background messages, when the app is terminated 
    FirebaseMessaging.onBackgroundMessage(_backgroundMessageHandler);


  }
  
  Future<void> init() async {
    if (_isInitialized) return;
    await initFCM();
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      
    );

    await _fln.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (resp) {
        print('📲 Notification tapped: ${resp.payload}');
        final payload = resp.payload;
        if (payload != null) {
          // Handle call notifications
          if (payload.startsWith('call:')) {
            final parts = payload.split(':');
            if (parts.length >= 4) {
              final chatId = int.tryParse(parts[1]);
              final callerId = int.tryParse(parts[2]);
              final callType = parts[3];
              final callId = parts[4];
              
              if (chatId != null && callerId != null) {
                final action = resp.actionId ?? 'open';
                _callActionController.add({
                  'action': action,
                  'chatId': chatId,
                  'callerId': callerId,
                  'callType': callType,
                  "callId": callId
                });
              }
            }
          } else {
            // Handle regular message notifications
            print("Notification tapped with payload: $payload");
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
    print("Showing chat message notificaton of : $title"); 
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
    required String callId,
  }) async {
 
 
    
  
    try{
      await CallKitService().showIncomingCall(
        chatId: chatId,
        callerId: callerId,
        callerName: callerName,
        callType: callType,
        callUUID: callId,
        handle: callerName,
      );
    }catch(e){
      print("Error showing CallKit incoming call: $e");
    }
    
    // await _fln.show(
    //   notificationId,
      
    //   callType == 'audio' ? '📞 Incoming Call' : '📹 Incoming Video Call',
    //   '$callerName is calling...',
    //   NotificationDetails(android: android, iOS: ios),
    //   payload: 'call:$chatId:$callerId:$callType:$callerId',
    // );
  }

  Future<void> cancelCallNotification(int chatId, String callId) async {
    await _fln.cancel(chatId, tag: callId);
  }

  Future<void> handleBackgroundNotification(RemoteMessage message) async {
    print('🔄 Background message received: in notification_service.dart ${message.messageId}');
    print('   Title: ${message.notification?.title}');
    print('   Body: ${message.notification?.body}');
    print('   Data: ${message.data}');
    
    try{
      await Firebase.initializeApp();
      final data = message.data;

     if(data['type'] == 'voice-call' || data['type'] == 'video-call') {
      
        print('Handling background call notification');
        print("Call type: ${data['type']}");
        await NotificationService.instance.showIncomingCallNotification(
          chatId: int.parse(data['chatId']),
          callerName: data['callerName'],
          callerId: int.parse(data['callerId']),
          callType: data['type'] == "voice-call" ? "audio" : "video",
          callId: data['callId'],
        );
    }
      print('✅ Background message processing complete');
    }catch(e){
      print('Firebase already initialized: $e');  
    }

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
  print('📲 Background notification tapped: ${response.payload}');
}

@pragma('vm:entry-point')
Future<void> _backgroundMessageHandler(RemoteMessage message) async {
  // await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // await NotificationService.instance.init();
   await Firebase.initializeApp();
  await NotificationService.instance.handleBackgroundNotification(message);
  print('🔄 Background message received: in notification_service.dart ${message.messageId}');
  print('   Title: ${message.notification?.title}');
  print('   Body: ${message.notification?.body}');
  print('   Data: ${message.data}');
}