import 'dart:async';
import 'package:flutter_app/app/models/livekit_events.dart';
import 'package:flutter_app/app/services/livekit_service.dart';

/// Service to manage the minimized call banner state
class CallOverlayService {
  static final CallOverlayService _instance = CallOverlayService._internal();
  factory CallOverlayService() => _instance;
  CallOverlayService._internal();

  final StreamController<CallOverlayState?> _overlayController =
      StreamController<CallOverlayState?>.broadcast();

  Stream<CallOverlayState?> get overlayStream => _overlayController.stream;
  CallOverlayState? _currentState;
  Timer? _updateTimer;
  final LiveKitService _liveKitService = LiveKitService();

  CallOverlayState? get currentState => _currentState;

  /// Show the minimized call banner
  void showCallBanner({
    required String name,
    required String? image,
    required CallType callType,
    required int chatId,
    required String duration,
    required bool isMuted,
  }) {
    print("🎯 CallOverlayService.showCallBanner called");
    print("   Name: $name");
    print("   ChatId: $chatId");
    print("   Duration: $duration");
    print("   Call Type: $callType");
    
    _currentState = CallOverlayState(
      name: name,
      image: image,
      callType: callType,
      chatId: chatId,
      duration: duration,
      isMuted: isMuted,
    );
    
    print("   Current state created, adding to stream...");
    _overlayController.add(_currentState);
    print("   State added to stream. Has listeners: ${_overlayController.hasListener}");
    
    // Start timer to update duration from LiveKitService
    _updateTimer?.cancel();
    _updateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_currentState != null && _liveKitService.isConnected) {
        final duration = _liveKitService.callDuration;
        final minutes = (duration / 60).floor();
        final seconds = duration % 60;
        final formattedDuration = '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
        
        _currentState = CallOverlayState(
          name: _currentState!.name,
          image: _currentState!.image,
          callType: _currentState!.callType,
          chatId: _currentState!.chatId,
          duration: formattedDuration,
          isMuted: !_liveKitService.isMicrophoneEnabled,
        );
        _overlayController.add(_currentState);
      }
    });
    
    print("   Timer started for updates");
  }

  /// Update the call duration
  void updateDuration(String duration) {
    if (_currentState != null) {
      _currentState = CallOverlayState(
        name: _currentState!.name,
        image: _currentState!.image,
        callType: _currentState!.callType,
        chatId: _currentState!.chatId,
        duration: duration,
        isMuted: _currentState!.isMuted,
      );
      _overlayController.add(_currentState);
    }
  }

  /// Update mute state
  void updateMuteState(bool isMuted) {
    if (_currentState != null) {
      _currentState = CallOverlayState(
        name: _currentState!.name,
        image: _currentState!.image,
        callType: _currentState!.callType,
        chatId: _currentState!.chatId,
        duration: _currentState!.duration,
        isMuted: isMuted,
      );
      _overlayController.add(_currentState);
    }
  }

  /// Hide the minimized call banner
  void hideCallBanner() {
    _updateTimer?.cancel();
    _updateTimer = null;
    _currentState = null;
    _overlayController.add(null);
  }

  void dispose() {
    _updateTimer?.cancel();
    _overlayController.close();
  }
}

/// State model for the call overlay
class CallOverlayState {
  final String name;
  final String? image;
  final CallType callType;
  final int chatId;
  final String duration;
  final bool isMuted;

  CallOverlayState({
    required this.name,
    required this.image,
    required this.callType,
    required this.chatId,
    required this.duration,
    required this.isMuted,
  });
}
