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
  StreamSubscription<CallStatus>? _callStatusSubscription;
  final LiveKitService _liveKitService = LiveKitService();

  CallOverlayState? get currentState => _currentState;
  
  /// Get call data from LiveKitService for returning to call
  Map<String, dynamic>? getCallDataFromLiveKit() {
    print('🔍 getCallDataFromLiveKit called');
    print('   Has active call: ${_liveKitService.hasActiveCall}');
    print('   Is connected: ${_liveKitService.isConnected}');
    print('   Chat ID: ${_liveKitService.currentChatId}');
    print('   Call Type: ${_liveKitService.currentCallType}');
    print('   Call Data: ${_liveKitService.currentCallData}');
    
    if (!_liveKitService.hasActiveCall) {
      print('❌ No active call - returning null');
      return null;
    }
    
    final data = {
      'chatId': _liveKitService.currentChatId,
      'callType': _liveKitService.currentCallType,
      'callData': _liveKitService.currentCallData,
    };
    
    print('✅ Returning call data: $data');
    return data;
  }

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
      callStatus: _liveKitService.callStatus,
    );
    
    print("   Current state created, adding to stream...");
    _overlayController.add(_currentState);
    print("   State added to stream. Has listeners: ${_overlayController.hasListener}");
    
    // Listen to call status changes to auto-hide on call end
    _callStatusSubscription?.cancel();
    _callStatusSubscription = _liveKitService.callStatusStream.listen((status) {
      print("📞 CallOverlayService received status update: $status");
      
      // Auto-hide banner when call ends or goes idle
      if (status == CallStatus.ended || status == CallStatus.idle) {
        print("📞 Call ended/idle - hiding banner");
        hideCallBanner();
        
      } else if (_currentState != null) {
        // Update status in the current state
        _currentState = CallOverlayState(
          name: _currentState!.name,
          image: _currentState!.image,
          callType: _currentState!.callType,
          chatId: _currentState!.chatId,
          duration: _currentState!.duration,
          isMuted: _currentState!.isMuted,
          callStatus: status,
        );
        _overlayController.add(_currentState);
      }
    });
    
    // Start timer to update duration and status from LiveKitService
    _updateTimer?.cancel();
    _updateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_currentState != null && _liveKitService.isConnected) {
        // Get updated duration and status from LiveKitService
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
          callStatus: _liveKitService.callStatus,
        );
        _overlayController.add(_currentState);
      }
    });
    
    print("   Timer started for updates from LiveKitService");
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
        callStatus: _liveKitService.callStatus,
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
        callStatus: _liveKitService.callStatus,
      );
      _overlayController.add(_currentState);
    }
  }

  /// Hide the minimized call banner
  void hideCallBanner() {
    print("🎯 CallOverlayService.hideCallBanner called");
    _updateTimer?.cancel();
    _updateTimer = null;
    _callStatusSubscription?.cancel();
    _callStatusSubscription = null;
    _currentState = null;
    _overlayController.add(null);
  }

  void dispose() {
    _updateTimer?.cancel();
    _callStatusSubscription?.cancel();
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
  final CallStatus callStatus;

  CallOverlayState({
    required this.name,
    required this.image,
    required this.callType,
    required this.chatId,
    required this.duration,
    required this.isMuted,
    required this.callStatus,
  });
}
