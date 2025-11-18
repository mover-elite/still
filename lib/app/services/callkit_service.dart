import 'dart:async';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:uuid/uuid.dart';


class CallKitService {
  static final CallKitService _instance = CallKitService._internal();

  factory CallKitService() {
    return _instance;
  }

  CallKitService._internal() {
    _setupEventListeners();
  }

  // Event stream controllers for broadcasting CallKit events
  final _callAcceptedController = StreamController<CallEvent?>.broadcast();
  final _callDeclinedController = StreamController<CallEvent?>.broadcast();
  final _callEndedController = StreamController<CallEvent?>.broadcast();
  final _callTimeoutController = StreamController<CallEvent?>.broadcast();
  final _callStartedController = StreamController<CallEvent?>.broadcast();
  final _callMuteToggledController = StreamController<CallEvent?>.broadcast();

  // Public streams for external listeners
  Stream<CallEvent?> get onCallAccepted => _callAcceptedController.stream;
  Stream<CallEvent?> get onCallDeclined => _callDeclinedController.stream;
  Stream<CallEvent?> get onCallEnded => _callEndedController.stream;
  Stream<CallEvent?> get onCallTimeout => _callTimeoutController.stream;
  Stream<CallEvent?> get onCallStarted => _callStartedController.stream;
  Stream<CallEvent?> get onCallMuteToggled => _callMuteToggledController.stream;

  /// Setup CallKit event listeners
  void _setupEventListeners() {
    print('🔵 Setting up CallKit event listeners...');
    
    FlutterCallkitIncoming.onEvent.listen((event) {
      if (event == null) return;
      
      print('🔵 📞 CallKit Event: ${event.event.name}');
      
      switch (event.event) {
        case Event.actionCallAccept:
          print('🟢 📞 Call ACCEPTED by user');
          _handleCallAccept(event);
          break;
        case Event.actionCallDecline:
          print('🔴 📞 Call DECLINED by user');
          _handleCallDecline(event);
          break;
        case Event.actionCallEnded:
          print('🔵 📞 Call ENDED');
          _handleCallEnded(event);
          break;
        case Event.actionCallTimeout:
          print('🟡 📞 Call TIMEOUT');
          _handleCallTimeout(event);
          break;
        case Event.actionCallStart:
          print('🟢 📞 Call STARTED');
          _handleCallStart(event);
          break;
        case Event.actionCallToggleMute:
          print('🔵 📞 Mute TOGGLED');
          _handleMuteToggled(event);
          break;
        case Event.actionCallIncoming:
          print('🔵 📞 Incoming call notification');
          break;
        case Event.actionCallToggleHold:
          print('🔵 📞 Hold TOGGLED');
          break;
        case Event.actionCallCallback:
          print('🔵 📞 Callback triggered');
          break;
        case Event.actionDidUpdateDevicePushTokenVoip:
          print('🔵 📞 VoIP push token updated');
          break;
        default:
          print('🟡 📞 Unhandled event: ${event.event.name}');
      }
    }).onError((error) {
      print('🔴 ❌ CallKit event stream error: $error');
    });
    
    print('🟢 ✅ CallKit event listeners setup complete');
  }

  /// Handle call accept event
  void _handleCallAccept(CallEvent? event) {
    try {
      final body = event?.body;
      if (body == null) {
        print('🔴 ❌ Call accept event has no body');
        return;
      }

      final callUUID = body['id'] as String?;
      // final extra = body['extra'] as Map<String, dynamic>?;
      
      print('🟢 📞 Processing call accept - UUID: $callUUID');
      
      // if (extra != null) {
      //   final chatId = int.tryParse(extra['chatId']?.toString() ?? '0') ?? 0;
      //   final callType = extra['callType']?.toString() ?? 'audio';
      //   final isGroup = extra['isGroup'] == true || extra['isGroup'] == 'true';
        
      //   print('🟢 📞 Accept details - chatId: $chatId, type: $callType, isGroup: $isGroup');
      // }
      
      // Broadcast to listeners
      _callAcceptedController.add(event);
    } catch (e) {
      print('🔴 ❌ Error handling call accept: $e');
    }
  }

  /// Handle call decline event
  void _handleCallDecline(CallEvent? event) {
    try {
      final body = event?.body;
      if (body == null) {
        print('🔴 ❌ Call decline event has no body');
        return;
      }

      final callUUID = body['id'] as String?;
      // final extra = body['extra'] as Map<String, dynamic>?;
      
      print('🔴 📞 Processing call decline - UUID: $callUUID');
      
      // if (extra != null) {
      //   final chatId = int.tryParse(extra['chatId']?.toString() ?? '0') ?? 0;
      //   final callType = extra['callType']?.toString() ?? 'audio';
        
      //   print('🔴 📞 Decline details - chatId: $chatId, type: $callType');
      // }
      
      // Broadcast to listeners
      _callDeclinedController.add(event);
    } catch (e) {
      print('🔴 ❌ Error handling call decline: $e');
    }
  }

  /// Handle call ended event
  void _handleCallEnded(CallEvent? event) {
    try {
      final body = event?.body;
      final callUUID = body?['id'] as String?;
      
      print('🔵 📞 Processing call ended - UUID: $callUUID');
      
      // Broadcast to listeners
      _callEndedController.add(event);
    } catch (e) {
      print('🔴 ❌ Error handling call ended: $e');
    }
  }

  /// Handle call timeout event
  void _handleCallTimeout(CallEvent? event) {
    try {
      final body = event?.body;
      final callUUID = body?['id'] as String?;
      
      print('🟡 📞 Processing call timeout - UUID: $callUUID');
      
      // Broadcast to listeners
      _callTimeoutController.add(event);
    } catch (e) {
      print('🔴 ❌ Error handling call timeout: $e');
    }
  }

  /// Handle call start event
  void _handleCallStart(CallEvent? event) {
    try {
      final body = event?.body;
      final callUUID = body?['id'] as String?;
      
      print('🟢 📞 Processing call start - UUID: $callUUID');
      
      // Broadcast to listeners
      _callStartedController.add(event);
    } catch (e) {
      print('🔴 ❌ Error handling call start: $e');
    }
  }

  /// Handle mute toggle event
  void _handleMuteToggled(CallEvent? event) {
    try {
      final body = event?.body;
      final callUUID = body?['id'] as String?;
      final isMuted = body?['isMuted'] as bool? ?? false;
      
      print('🔵 📞 Processing mute toggle - UUID: $callUUID, muted: $isMuted');
      
      // Broadcast to listeners
      _callMuteToggledController.add(event);
    } catch (e) {
      print('🔴 ❌ Error handling mute toggle: $e');
    }
  }

  /// Show incoming call in CallKit
  /// 
  /// Displays a native incoming call UI on iOS/Android with proper CallKit integration.
  /// 
  /// Parameters:
  /// - [callUUID]: Unique identifier for the call
  /// - [callerName]: Name to display on call screen
  /// - [handle]: Phone number or identifier
  /// - [avatar]: Avatar URL (defaults to placeholder)
  /// - [callType]: 'audio' or 'video' (defaults to 'audio')
  /// - [chatId]: Chat ID for WebSocket communication
  /// - [callerId]: Caller user ID
  /// - [isGroup]: Whether this is a group call
  /// 
  Future<void> showIncomingCall({
    required String callUUID,
    required String callerName,
    required String handle,
    String avatar = 'https://i.pravatar.cc/100',
    String callType = 'audio',
    int chatId = 0,
    int callerId = 0,
    bool isGroup = false,
  }) async {
    try {
      print('🔵 📞 Showing incoming call - UUID: $callUUID, caller: $callerName');

      final displayName = isGroup 
          ? '$callerName (Group)' 
          : callerName;

      final callKitParams = CallKitParams(
        id: callUUID,
        nameCaller: displayName,
        appName: 'Stillur',
        avatar: avatar,
        handle: handle,
        type: callType == 'video' ? 1 : 0, // 1 = video, 0 = audio
        textAccept: 'Accept',
        textDecline: 'Decline',
        missedCallNotification: NotificationParams(
          showNotification: true,
          isShowCallback: true,
          subtitle: isGroup ? 'Missed group call' : 'Missed call',
          callbackText: 'Call back',
        ),
        duration: 30000,
        extra: <String, dynamic>{
          'callUUID': callUUID,
          'userId': callerId.toString(),
          'chatId': chatId.toString(),
          'callType': callType,
          'isGroup': isGroup,
        },
        headers: <String, dynamic>{'platform': 'flutter'},
        android: const AndroidParams(
          isCustomNotification: true,
          isShowLogo: false,
          ringtonePath: 'system_ringtone_default',
          backgroundColor: '#0955fa',
          backgroundUrl: 'https://i.pravatar.cc/500',
          actionColor: '#4CAF50',
          textColor: '#ffffff',
          incomingCallNotificationChannelName: 'Incoming Call',
          missedCallNotificationChannelName: 'Missed Call',
          isShowCallID: false,
        ),
        ios: IOSParams(
          handleType: 'generic',
          supportsVideo: callType == 'video',
          maximumCallGroups: 2,
          maximumCallsPerCallGroup: isGroup ? 99 : 1,
          audioSessionMode: 'default',
          audioSessionActive: true,
          audioSessionPreferredSampleRate: 44100.0,
          audioSessionPreferredIOBufferDuration: 0.005,
          supportsDTMF: true,
          supportsHolding: true,
          supportsGrouping: isGroup,
          supportsUngrouping: isGroup,
        ),
      );

      await FlutterCallkitIncoming.showCallkitIncoming(callKitParams);
      print('🟢 ✅ CallKit incoming call displayed successfully');
    } catch (e) {
      print('🔴 ❌ Error showing incoming call: $e');
      rethrow;
    }
  }

  /// Start outgoing call in CallKit
  /// 
  /// Initiates a native outgoing call UI on iOS/Android.
  /// 
  /// Parameters:
  /// - [callUUID]: Unique identifier for the call
  /// - [recipientName]: Name of the call recipient
  /// - [handle]: Phone number or identifier
  /// - [avatar]: Avatar URL (defaults to placeholder)
  /// - [callType]: 'audio' or 'video' (defaults to 'audio')
  /// - [chatId]: Chat ID for WebSocket communication
  /// - [recipientId]: Recipient user ID
  /// - [isGroup]: Whether this is a group call
  Future<void> startOutgoingCall({
    required String callUUID,
    required String recipientName,
    required String handle,
    String avatar = 'https://i.pravatar.cc/100',
    String callType = 'audio',
    int chatId = 0,
    int recipientId = 0,
    bool isGroup = false,
  }) async {
    try {
      print('🔵 📞 Starting outgoing call - UUID: $callUUID, recipient: $recipientName');

      final displayName = isGroup 
          ? '$recipientName (Group)' 
          : recipientName;

      CallKitParams params = CallKitParams(
  id: callUUID,
  nameCaller: displayName,
  handle: handle,
  type: callType == 'video' ? 1 : 0,
  extra: <String, dynamic>{
    'callUUID': callUUID,
    'recipientId': recipientId.toString(),
    'chatId': chatId.toString(),
    'callType': callType,
    'isGroup': isGroup,
    'isOutgoing': true,
  },
  ios: IOSParams(handleType: 'generic'),
  callingNotification: const NotificationParams(
    showNotification: true,
    isShowCallback: true,
    subtitle: 'Calling...',
    callbackText: 'Hang Up',
  ),
  android: const AndroidParams(
    isCustomNotification: true,
    isShowCallID: true,
  )
);
      await FlutterCallkitIncoming.startCall(params);
      await FlutterCallkitIncoming.setCallConnected(callUUID);
      // FlutterCallkitIncoming.startCall(params);
      print('🟢 ✅ CallKit outgoing call started successfully');
    } catch (e) {
      print('🔴 ❌ Error starting outgoing call: $e');
      rethrow;
    }
  }

  /// End an active call
  /// 
  /// Terminates the CallKit UI for the specified call UUID.
  /// 
  /// Parameters:
  /// - [callUUID]: UUID of the call to end
  Future<void> endCall({required String callUUID}) async {
    try {
      print('🔵 📞 Ending call - UUID: $callUUID');
      await FlutterCallkitIncoming.endCall(callUUID);
      print('🟢 ✅ CallKit call ended successfully');
    } catch (e) {
      print('🔴 ❌ Error ending call: $e');
    }
  }

  /// Get list of active calls
  /// 
  /// Returns a list of all currently active CallKit calls.
  /// Useful for managing multiple simultaneous calls.
  /// 
  /// Returns: List of active call objects
  Future<List<dynamic>> getActiveCalls() async {
    try {
      final activeCalls = await FlutterCallkitIncoming.activeCalls();
      print('🔵 📞 Active calls: ${activeCalls.length} call(s)');
      return activeCalls;
    } catch (e) {
      print('🔴 ❌ Error getting active calls: $e');
      return [];
    }
  }

  /// Generate a unique call UUID
  /// 
  /// Creates a universally unique identifier (v4) for call tracking.
  /// This is used to uniquely identify each call session.
  /// 
  /// Returns: A UUID string in standard format (e.g., "123e4567-e89b-12d3-a456-426614174000")
  static String generateCallUUID() {
    const uuid = Uuid();
    return uuid.v4();
  }

  /// Dispose resources and close stream controllers
  void dispose() {
    print('🧹 Disposing CallKit service...');
    _callAcceptedController.close();
    _callDeclinedController.close();
    _callEndedController.close();
    _callTimeoutController.close();
    _callStartedController.close();
    _callMuteToggledController.close();
    print('🟢 ✅ CallKit service disposed');
  }
}
