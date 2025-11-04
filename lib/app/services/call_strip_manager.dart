import 'package:flutter/material.dart';

/// Global state manager for the minimized call strip
/// Allows showing/hiding the strip from anywhere in the app
class CallStripManager {
  static final CallStripManager _instance = CallStripManager._internal();
  
  factory CallStripManager() => _instance;
  
  CallStripManager._internal();

  final ValueNotifier<CallStripState?> _stateNotifier = ValueNotifier(null);
  
  /// Listen to call strip state changes
  ValueNotifier<CallStripState?> get stateNotifier => _stateNotifier;
  
  /// Get current state
  CallStripState? get currentState => _stateNotifier.value;
  
  /// Check if strip is visible
  bool get isVisible => _stateNotifier.value != null;
  
  /// Show the minimized call strip
  void showStrip({
    required String callerName,
    required int chatId,
    String? callType,
  }) {
    _stateNotifier.value = CallStripState(
      callerName: callerName,
      chatId: chatId,
      callType: callType ?? 'audio',
    );
    print('📱 Call strip shown for $callerName');
  }
  
  /// Hide the minimized call strip
  void hideStrip() {
    _stateNotifier.value = null;
    print('📱 Call strip hidden');
  }
  
  /// Dispose resources
  void dispose() {
    _stateNotifier.dispose();
  }
}

/// State model for the call strip
class CallStripState {
  final String callerName;
  final int chatId;
  final String callType;
  
  CallStripState({
    required this.callerName,
    required this.chatId,
    required this.callType,
  });
}
