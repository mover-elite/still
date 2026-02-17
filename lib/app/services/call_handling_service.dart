import 'dart:async';
import 'package:flutter_app/app/services/chat_service.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_app/app/networking/websocket_service.dart';
import 'package:flutter_app/app/models/livekit_events.dart';
import 'package:nylo_framework/nylo_framework.dart';
import 'callkit_service.dart';
import 'livekit_service.dart';
import '/resources/pages/video_call_page.dart';
import '/resources/pages/voice_call_page.dart';

/// CallHandlingService manages the complete lifecycle of calls
/// Coordinates between CallKit UI, LiveKit connections, and app routing
class CallHandlingService {
  static final CallHandlingService _instance = CallHandlingService._internal();

  factory CallHandlingService() {
    return _instance;
  }

  CallHandlingService._internal();

  final _callKitService = CallKitService();
  final _liveKitService = LiveKitService();
  final _webSocketService = WebSocketService();

  StreamSubscription<CallEvent?>? _callAcceptedSubscription;
  StreamSubscription<CallEvent?>? _callDeclinedSubscription;
  StreamSubscription<CallEvent?>? _callEndedSubscription;
  StreamSubscription<CallEvent?>? _callMuteToggledSubscription;
  StreamSubscription<CallStatus>? _callStatusSubscription;

  bool _isInitialized = false;

  /// Initialize the call handling service
  Future<void> initialize() async {
    if (_isInitialized) {
      print('⚠️ CallHandlingService already initialized');
      return;
    }

    try {
      print('🔵 Initializing CallHandlingService...');

      // Setup CallKit event listeners
      _setupCallKitListeners();

      // Setup LiveKit status listeners
      _setupLiveKitListeners();

      _isInitialized = true;
      print('🟢 ✅ CallHandlingService initialized successfully');
    } catch (e) {
      print('🔴 ❌ Error initializing CallHandlingService: $e');
      rethrow;
    }
  }

  /// Setup CallKit event listeners
  void _setupCallKitListeners() {
    print('🔵 Setting up CallKit event listeners');

    // Listen for call acceptance
    _callAcceptedSubscription = _callKitService.onCallAccepted.listen(
      (event) {
        print('🟢 📞 Call accepted event received');
        _handleCallAccepted(event);
      },
      onError: (error) {
        print('🔴 ❌ Error in call accepted stream: $error');
      },
    );

    // Listen for call decline
    _callDeclinedSubscription = _callKitService.onCallDeclined.listen(
      (event) {
        print('🔴 📞 Call declined event received');
        _handleCallDeclined(event);
      },
      onError: (error) {
        print('🔴 ❌ Error in call declined stream: $error');
      },
    );

    // Listen for call end
    _callEndedSubscription = _callKitService.onCallEnded.listen(
      (event) {
        print('🔵 📞 Call ended event received');
        _handleCallEnded(event);
      },
      onError: (error) {
        print('🔴 ❌ Error in call ended stream: $error');
      },
    );

    // Listen for mute toggle
    _callMuteToggledSubscription = _callKitService.onCallMuteToggled.listen(
      (event) {
        print('🔵 📞 Mute toggled event received');
        _handleMuteToggled(event);
      },
      onError: (error) {
        print('🔴 ❌ Error in mute toggled stream: $error');
      },
    );

    print('🟢 ✅ CallKit event listeners setup complete');
  }

  /// Setup LiveKit status listeners
  void _setupLiveKitListeners() {
    print('🔵 Setting up LiveKit status listeners');

    _callStatusSubscription = _liveKitService.callStatusStream.listen(
      (status) {
        print('📞 LiveKit status changed: $status');
        _handleLiveKitStatusChange(status);
      },
      onError: (error) {
        print('🔴 ❌ Error in call status stream: $error');
      },
    );

    print('🟢 ✅ LiveKit status listeners setup complete');
  }

  /// Handle call accepted
  Future<void> _handleCallAccepted(CallEvent? event) async {
    try {
      print('🟢 📞 Processing call acceptance...');

      final body = event?.body;
      if (body == null) {
        print('🔴 ❌ Call accepted event has no body');
        return;
      }

      final callUUID = body['id'] as String?;
      
      // Safely extract extra map - handle generic Map<Object?, Object?> type
      Map<String, dynamic>? extra;
      final extraRaw = body['extra'];
      if (extraRaw != null && extraRaw is Map) {
        extra = Map<String, dynamic>.from(extraRaw);
      }

      if (callUUID == null || extra == null) {
        print('🔴 ❌ Missing required call data');
        return;
      }

      final chatId = int.tryParse(extra['chatId']?.toString() ?? '0') ?? 0;
      final callerId = int.tryParse(extra['userId']?.toString() ?? '0') ?? 0;
      final callType = extra['callType']?.toString() ?? 'audio';
      

      print('📞 Call accepted details:');
      print('   UUID: $callUUID');
      print('   Chat ID: $chatId');
      print('   Caller ID: $callerId');
      print('   Call Type: $callType');
      

      if (chatId == 0) {
        print('🔴 ❌ Invalid chat ID');
        return;
      }

      

      // Connect to LiveKit
      final chat = await ChatService().getChatDetails(chatId);
      if(chat == null){
        print('🔴 ❌ Failed to get chat details for chat ID: $chatId');
        return;
      }
 

      // Navigate to call screen based on call type
      print('🔵 Navigating to call screen...');
      final callData = {
          'isGroup': chat.isGroup,
          'partner': {
            'username': chat.partner?.username ?? 'Unknown',
            'avatar': chat.partner?.avatar ?? 'default_avatar.png',
          },
          "avatar": chat.avatar,
          "name": chat.name,
          "groupName": chat.name,
          'chatId': chatId,
          'callerId': callerId,
          'callId': callUUID,
          'initiateCall': false, // This indicates joining, not initiating
          'isJoining': true, // Flag to indicate this is an incoming call
          
        };
      
      if (callType == 'video') {
        await routeTo(VideoCallPage.path, data: callData, navigationType: NavigationType.pushReplace);
      } else {
        await routeTo(VoiceCallPage.path, data: callData, navigationType: NavigationType.pushReplace);
      }

      print('🟢 ✅ Navigated to call screen');
    } catch (e) {
      print('🔴 ❌ Error handling call acceptance: $e');
      // Decline the call if connection fails
      if (event?.body != null) {
        final callUUID = event?.body?['id'] as String?;
        if (callUUID != null) {
          await _handleCallDeclined(event);
        }
      }
    }
  }

  /// Handle call declined
  Future<void> _handleCallDeclined(CallEvent? event) async {
    try {
      print('🔴 📞 Processing call decline...');

      final body = event?.body;
      if (body == null) {
        print('🔴 ❌ Call declined event has no body');
        return;
      }

      final callUUID = body['id'] as String?;
      
      // Safely extract extra map - handle generic Map<Object?, Object?> type
      Map<String, dynamic>? extra;
      final extraRaw = body['extra'];
      if (extraRaw != null && extraRaw is Map) {
        extra = Map<String, dynamic>.from(extraRaw);
      }

      if (callUUID == null || extra == null) {
        print('🔴 ❌ Missing required call data');
        return;
      }

      final chatId = int.tryParse(extra['chatId']?.toString() ?? '0') ?? 0;

      print('🔴 📞 Decline details:');
      print('   UUID: $callUUID');
      print('   Chat ID: $chatId');

      // End CallKit call
      print('🔵 Ending CallKit call...');
      await _callKitService.endCall(callUUID: callUUID);
      print('🟢 ✅ CallKit call ended');
      WebSocketService().sendDeclineCall(chatId, "audio", callUUID);
      // Disconnect from LiveKit if connected
      if (_liveKitService.isConnected) {
        print('🔵 Disconnecting from LiveKit... $callUUID');
        await _liveKitService.disconnect(
          reason: 'Call declined',
          sendDeclineNotification: false,
            callId: callUUID
          );
        print('🟢 ✅ Disconnected from LiveKit');
      }

      // Send decline notification to server
      // if (chatId != 0) {
      //   print('🔵 Sending decline notification to server...');
      //   try {
      //     _webSocketService.sendDeclineCall(
      //       chatId,
      //       'audio', // TODO: Get actual call type
      //       callUUID,
      //     );
      //     print('🟢 ✅ Decline notification sent');
      //   } catch (e) {
      //     print('⚠️ Error sending decline notification: $e');
      //   }
      // }
    } catch (e) {
      print('🔴 ❌ Error handling call decline: $e');
    }
  }

  /// Handle call ended
  Future<void> _handleCallEnded(CallEvent? event) async {
    try {
      print('🔵 📞 Processing call end...');

      final body = event?.body;
      if (body == null) {
        print('🔴 ❌ Call ended event has no body');
        return;
      }

      final callUUID = body['id'] as String?;

      print('📞 Call ended:');
      print('   UUID: $callUUID');

      // Disconnect from LiveKit
      if (_liveKitService.isConnected) {
        print('🔵 Disconnecting from LiveKit...');
        await _liveKitService.disconnect(reason: 'Call ended');
        print('🟢 ✅ Disconnected from LiveKit');
      }

      print('🟢 ✅ Call ended - navigator should close call screen');
    } catch (e) {
      print('🔴 ❌ Error handling call end: $e');
    }
  }

  /// Handle mute toggle
  Future<void> _handleMuteToggled(CallEvent? event) async {
    try {
      print('🔵 📞 Processing mute toggle...');

      final body = event?.body;
      if (body == null) {
        print('🔴 ❌ Mute toggle event has no body');
        return;
      }

      final callUUID = body['id'] as String?;
      
      // Safely extract isMuted - handle type conversion
      final isMutedRaw = body['isMuted'];
      final isMuted = isMutedRaw is bool ? isMutedRaw : (isMutedRaw == 'true' || isMutedRaw == true);

      print('🔵 Mute toggle:');
      print('   UUID: $callUUID');
      print('   Muted: $isMuted');

      // Toggle microphone in LiveKit
      if (_liveKitService.isConnected) {
        print('🔵 Updating microphone state...');
        await _liveKitService.setMicrophoneEnabled(!isMuted);
        print('🟢 ✅ Microphone ${isMuted ? 'muted' : 'unmuted'}');
      }
    } catch (e) {
      print('🔴 ❌ Error handling mute toggle: $e');
    }
  }

  /// Handle LiveKit status changes
  void _handleLiveKitStatusChange(CallStatus status) {
    print('📊 LiveKit status changed: $status');

    switch (status) {
      case CallStatus.idle:
        print('📞 Call: Idle');
        break;
      case CallStatus.requesting:
        print('📞 Call: Requesting token');
        break;
      case CallStatus.connecting:
        print('📞 Call: Connecting to room');
        break;
      case CallStatus.ringing:
        print('📞 Call: Ringing - waiting for participants');
        break;
      case CallStatus.connected:
        print('📞 Call: Connected - active call');
        break;
      case CallStatus.ended:
        // endActiveCall(callUUID: _liveKitService.currentCallUUID ?? '');
        print('📞 Call: Ended');
        break;
    }
  }

  /// Initiate an outgoing call
  Future<void> initiateOutgoingCall({
    required int chatId,
    required int recipientId,
    required String recipientName,
    required String callType, // 'audio' or 'video'
    required String token, // LiveKit token from server
    bool isGroupCall = false, // New parameter for group calls
  }) async {
    try {
      print('🟢 📞 Initiating outgoing call...');
      print('   Is Group Call: $isGroupCall');

      // Generate call UUID
      final callUUID = CallKitService.generateCallUUID();
      print('📞 Generated call UUID: $callUUID');

      // Show outgoing call in CallKit
      print('🔵 Showing outgoing call UI...');
      await _callKitService.startOutgoingCall(
        callUUID: callUUID,
        recipientName: recipientName,
        handle: recipientId.toString(),
        callType: callType,
        chatId: chatId,
        recipientId: recipientId,
      );
      print('🟢 ✅ Outgoing call UI shown');

      // Connect to LiveKit
      print('🔵 Connecting to LiveKit room...');
      await _liveKitService.connect(
        token: token,
        callType: isGroupCall ? CallType.group : CallType.single,
        callId: callUUID,
        chatId: chatId,
        enableAudio: true,
        enableVideo: callType == 'video',
      );
      print('🟢 ✅ Connected to LiveKit');

      // Navigate to call screen
      print('🔵 Navigating to call screen...');
      if (callType == 'video') {
        await routeTo(VideoCallPage.path, data: {
          'chatId': chatId,
          'callId': callUUID,
          'callType': 'video',
          'isIncoming': false,
          'isGroup': isGroupCall,
          'initiateCall': true,
        });
      } else {
        await routeTo(VoiceCallPage.path, data: {
          'chatId': chatId,
          'callId': callUUID,
          'callType': 'audio',
          'isIncoming': false,
          'isGroup': isGroupCall,
          'initiateCall': true,
        });
      }
      print('🟢 ✅ Navigated to call screen');
    } catch (e) {
      print('🔴 ❌ Error initiating outgoing call: $e');
      rethrow;
    }
  }

  /// End active call
  Future<void> endActiveCall({required String callUUID}) async {
    try {
      print('🔵 📞 Ending active call in call handling service: $callUUID');

      // End CallKit call
      await _callKitService.endCall(callUUID: callUUID);

      // Disconnect from LiveKit
      // if (_liveKitService.isConnected) {
      //   print("Ending call in call handling service");
      //   await _liveKitService.disconnect(reason: 'User ended call');
      // }

      print('🟢 ✅ Call ended successfully');
    } catch (e) {
      print('🔴 ❌ Error ending call: $e');
      rethrow;
    }
  }

  /// Toggle microphone during call
  Future<void> toggleMicrophone() async {
    try {
      if (_liveKitService.isConnected) {
        await _liveKitService.toggleMicrophone();
        print('🎤 Microphone toggled');
      }
    } catch (e) {
      print('🔴 ❌ Error toggling microphone: $e');
      rethrow;
    }
  }

  /// Toggle camera during call
  Future<void> toggleCamera() async {
    try {
      if (_liveKitService.isConnected) {
        await _liveKitService.toggleCamera();
        print('📹 Camera toggled');
      }
    } catch (e) {
      print('🔴 ❌ Error toggling camera: $e');
      rethrow;
    }
  }

  /// Get call status stream
  Stream<CallStatus> get callStatusStream => _liveKitService.callStatusStream;

  /// Get current call status
  CallStatus get callStatus => _liveKitService.callStatus;

  /// Check if there's an active call
  bool get hasActiveCall => _liveKitService.hasActiveCall;

  /// Dispose resources
  void dispose() {
    print('🧹 Disposing CallHandlingService...');
    _callAcceptedSubscription?.cancel();
    _callDeclinedSubscription?.cancel();
    _callEndedSubscription?.cancel();
    _callMuteToggledSubscription?.cancel();
    _callStatusSubscription?.cancel();
    _callKitService.dispose();
    _liveKitService.dispose();
    print('🟢 ✅ CallHandlingService disposed');
  }
}
