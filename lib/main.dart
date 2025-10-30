import 'package:flutter/widgets.dart';
import 'package:nylo_framework/nylo_framework.dart';
import 'bootstrap/boot.dart';
import '/app/services/notification_service.dart';
import '/app/services/chat_service.dart';
import '/resources/pages/chat_screen_page.dart';

/// Nylo - Framework for Flutter Developers
/// Docs: https://nylo.dev/docs/6.x

/// Main entry point for the application.
void main() async {
  // Fix: ensure binary messenger is initialized before plugins
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize local notifications
  await NotificationService.instance.init();

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

  await Nylo.init(
    setup: Boot.nylo,
    setupFinished: Boot.finished,

    // showSplashScreen: true,
    // Uncomment showSplashScreen to show the splash screen
    // File: lib/resources/widgets/splash_screen.dart
  );
}
