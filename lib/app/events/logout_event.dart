import 'package:nylo_framework/nylo_framework.dart';
import '/app/networking/auth_api_service.dart';
import '/app/services/chat_service.dart';

class LogoutEvent implements NyEvent {
  @override
  final listeners = {
    DefaultListener: DefaultListener(),
  };
}

class DefaultListener extends NyListener {
  @override
  handle(dynamic event) async {
    print('🔓 Starting logout process...');
    
    // Call API logout endpoint first
    try {
      AuthApiService apiService = AuthApiService();
      await apiService.logoutUser();
      print('✅ API logout successful');
    } catch (e) {
      print('API logout failed: $e');
      // Continue with local logout even if API call fails
    }

    // Clear chat service cache and disconnect websocket before clearing auth
    try {
      await ChatService().logoutCleanup();
      print('✅ ChatService logout cleanup completed');
    } catch (e) {
      print('Error during ChatService logout cleanup: $e');
    }

    // Clear local authentication
    await Auth.logout();
    print('✅ Local authentication cleared');

    // Use Nylo's router to navigate to initial route and clear history
    routeToInitial();
    print('✅ Logout process completed');
  }
}
