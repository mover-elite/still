import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_app/app/services/call_handling_service.dart';
import 'package:flutter_app/firebase_options.dart';
import 'package:nylo_framework/nylo_framework.dart';
import 'bootstrap/boot.dart';
import '/app/services/notification_service.dart';
import '/app/services/chat_service.dart';
import '/resources/pages/chat_screen_page.dart';
import 'package:firebase_core/firebase_core.dart';
/// Nylo - Framework for Flutter Developers
/// Docs: https://nylo.dev/docs/6.x

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // print("")
  print('🔄 Background message handler called');
  print('   Title: ${message.notification?.title}');
  print('   Body: ${message.notification?.body}');
  print('   Data: ${message.data}');
  final data = message.data;
  // Initialize Firebase if needed
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
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
    

  } catch (e) {
    // Firebase already initialized
    print('Firebase already initialized: $e');
  }
  
  print('✅ Background message processing complete');
}

/// Main entry point for the application.
void main() async {
  // Fix: ensure binary messenger is initialized before plugins
  
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize local notifications
  print("Initializing Firebase...");
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );


  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  await Nylo.init(
    setup: Boot.nylo,
    setupFinished: Boot.finished,

    // showSplashScreen: true,
    // Uncomment showSplashScreen to show the splash screen
    // File: lib/resources/widgets/splash_screen.dart
  );

  
  
  await NotificationService.instance.init();
  
  print("Initializing Notification Service...");
  
  // Initialize Call Handling Service - coordinates all call events
  print("Initializing Call Handling Service...");
  await CallHandlingService().initialize();
  
  // Handle notification taps to open chat
  NotificationService.instance.onNotificationTap.listen((chatId) async {
    final chat = await ChatService().getChatDetails(chatId);
    final name = chat?.name ?? 'Chat';
    final image = chat?.avatar;
    await routeTo(ChatScreenPage.path, data: {
      'chatId': chatId,
      'userName': name,
      'userImage': image,
      'isOnline': false,
      'description': chat?.description ?? '',
    });
  });

  
}


