import 'dart:async';
import 'package:flutter_app/app/networking/websocket_service.dart';
import 'package:flutter_app/app/models/livekit_events.dart';
import 'package:flutter_app/app/services/call_handling_service.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:audioplayers/audioplayers.dart';

final url = 'ws://217.77.4.167:7880';

// Call status enum
enum CallStatus {
  idle,        // No call
  requesting,  // Getting token from API
  connecting,  // Connecting to LiveKit room
  ringing,     // Connected but waiting for other party
  connected,   // Active call with participants
  ended,      // Call has ended
}

class LiveKitService {
  static final LiveKitService _instance = LiveKitService._internal();

  factory LiveKitService() {
    return _instance;
  }

  LiveKitService._internal();

  // Room instance
  Room? _room;
  EventsListener<RoomEvent>? _listener;
  bool _isConnecting = false;
  
  // Track enable preferences (set before connecting, used after RoomConnectedEvent)
  bool _enableAudio = true;
  bool _enableVideo = true;
  
  // Current call metadata (persists beyond UI lifecycle)
  
  String? _currentCallId;
  int? _currentChatId;
  CallType? _currentCallType;
  Map<String, dynamic>? _currentCallData;
  CallStatus _callStatus = CallStatus.idle;
  bool _isJoining = false; // Track if joining incoming call
  
  // Ringtone management
  AudioPlayer? _audioPlayer;

  // Participants tracking
  final List<RemoteParticipant> _remoteParticipants = [];
  final List<Map<String, dynamic>> _participantHistory = [];

  // Room analytics
  final Map<String, dynamic> _roomInfo = {};
  int _callDuration = 0;
  Timer? _durationTimer;
  int? _startTime;
  // Grouped event stream controllers
  final _connectionEventController = StreamController<ConnectionStateEvent>.broadcast();
  final _participantEventController = StreamController<ParticipantChangeEvent>.broadcast();
  final _trackEventController = StreamController<TrackStateEvent>.broadcast();
  final _callStatusController = StreamController<CallStatus>.broadcast();

  // Public streams for external listeners
  Stream<ConnectionStateEvent> get connectionEvents => _connectionEventController.stream;
  Stream<ParticipantChangeEvent> get participantEvents => _participantEventController.stream;
  Stream<TrackStateEvent> get trackEvents => _trackEventController.stream;
  Stream<CallStatus> get callStatusStream => _callStatusController.stream;

  
  Room? get room => _room;
  List<RemoteParticipant> get remoteParticipants => List.unmodifiable(_remoteParticipants);
  bool get isConnected => _room?.connectionState == ConnectionState.connected;
  bool get isConnecting => _isConnecting;
  int get callDuration => _callDuration;
  CallStatus get callStatus => _callStatus;
  
  Map<String, dynamic> get roomInfo => Map.from(_roomInfo);
  List<Map<String, dynamic>> get participantHistory => List.from(_participantHistory);
  LocalParticipant? get localParticipant => _room?.localParticipant;
  bool get isMicrophoneEnabled => _room?.localParticipant?.isMicrophoneEnabled() ?? false;
  bool get isCameraEnabled => _room?.localParticipant?.isCameraEnabled() ?? false;
  
  // Current call getters
  String? get currentCallUUID => _currentCallId;
  int? get currentChatId => _chatId;
  CallType? get currentCallType => _currentCallType;
  Map<String, dynamic>? get currentCallData => _currentCallData != null ? Map.from(_currentCallData!) : null;
  bool get hasActiveCall => _chatId != null && isConnected;
  int? _chatId;


  StreamSubscription<Map<String, dynamic>>? _notificationSubscription;

  /// Play ringtone
  Future<void> _playRingtone() async {
    try {
      print('🔔 _playRingtone called, _isJoining: $_isJoining');
      await _audioPlayer?.stop();
      _audioPlayer = AudioPlayer();
      await _audioPlayer!.setReleaseMode(ReleaseMode.loop);
      
      print('🔔 AudioPlayer created and set to loop mode');
      
      if (_isJoining) {
        // For incoming calls, you can use a different ringtone
        print('🔔 Playing ringtone for INCOMING call');
        await _audioPlayer!.play(AssetSource('audio/ringing_initiated.mp3'));
      } else {
        // For outgoing calls
        print('🔔 Playing ringtone for OUTGOING call');
        await _audioPlayer!.play(AssetSource('audio/ringing_initiated.mp3'));
      }
      
      print('🔔 Ringtone started playing successfully');
    } catch (e) {
      print('❌ Error playing ringtone: $e');
      print('❌ Error stack trace: ${StackTrace.current}');
    }
  }

  /// Stop ringtone
  Future<void> _stopRingtone() async {
    try {
      await _audioPlayer?.stop();
      await _audioPlayer?.dispose();
      _audioPlayer = null;
      print('🔕 Ringtone stopped');
    } catch (e) {
      print('❌ Error stopping ringtone: $e');
    }
  }

  /// Update call status and notify listeners
  void _updateCallStatus(CallStatus newStatus) {
    if (_callStatus != newStatus) {
      final oldStatus = _callStatus;
      _callStatus = newStatus;
      _callStatusController.add(newStatus);
      print('📞 Call status changed from $oldStatus to: $newStatus');
      
      // Handle ringtone based on status changes
      if (newStatus == CallStatus.ringing && oldStatus != CallStatus.ringing) {
        print('🔔 Triggering ringtone playback...');
        _playRingtone();
      } else if (newStatus == CallStatus.connected && oldStatus == CallStatus.ringing) {
        print('🔕 Stopping ringtone...');
        _stopRingtone();
      }
    } else {
      print('⚠️ Status unchanged, still: $_callStatus');
    }
  }

  /// Public method to update call status (can be called from voice_call_page)
  void updateCallStatus(CallStatus newStatus, {bool isJoining = false}) {
    print('📞 [PUBLIC API] updateCallStatus called with: $newStatus, isJoining: $isJoining');
    _isJoining = isJoining;
    _updateCallStatus(newStatus);
  }

  Future<void> connect({
    required String token,
    required CallType callType,
    required String callId,
    bool autoSubscribe = true,
    bool enableAudio = true,
    bool enableVideo = true,
    
    int? chatId,
    
    Map<String, dynamic>? callData,
  }) async {
    if (_isConnecting) {
      print('⚠️ Connection attempt already in progress, skipping...');
      return;
    }
    // _playRingtone();
    try {
      _isConnecting = true;
      print('📞 [STATUS CHANGE] Setting status to CONNECTING');
      _updateCallStatus(CallStatus.connecting);
      
      print('🔄 Connecting to LiveKit room...');
      print('📍 URL: $url');

      // Cleanup any existing connection
      await _ensureRoomCleanup();

      // Create fresh room instance
      _room = Room(roomOptions: RoomOptions(
        adaptiveStream: true,
        dynacast: true,
      ));


      if (enableAudio) {
        await _room!.localParticipant?.setMicrophoneEnabled(true);
        print('🎤 Microphone enabled before connection');
      }
      if (enableVideo) {
        await _room!.localParticipant?.setCameraEnabled(true);
        print('📹 Camera enabled before connection');
      }

      // Setup event listeners
      _setupRoomListeners();

      // Setup WebSocket notification listener
      _notificationSubscription =
          WebSocketService().notificationStream.listen((notificationData) {
        _handleIncomingNotification(notificationData);
      });

      // Connect to room
      await _room!.connect(
        url,
        token,
        connectOptions: ConnectOptions(
          autoSubscribe: autoSubscribe,
          
        ),
        
      );

      print('✅ Connected to LiveKit room');

      // Store call metadata
      
      _currentChatId = chatId;
      _chatId = chatId;
      _currentCallType = callType;
      _currentCallData = callData;
      _currentCallId = callId;
      
      // Set status to ringing after connection (unless already connected via call:start notification)
      // Status should be 'connecting' at this point
      // print("📞 Call status before post-connection check: $_callStatus");
      // if (_callStatus == CallStatus.connecting) {
      //   print('📞 [STATUS CHANGE] Setting status to RINGING (post-connection)');
      //   _updateCallStatus(CallStatus.ringing);
      //   print("📞 Status set to ringing - ringtone should play");
      // } else if (_callStatus == CallStatus.connected) {
      //   print("📞 Status already connected (call:start notification received early)");
      // }

      
      print("Video enabled on connect: $enableVideo");
      // Store track preferences for use in room listeners
      _enableAudio = enableAudio;
      _enableVideo = enableVideo;

      // Start tracking call duration
      _startDurationTimer();

      // Capture initial room info
      _captureRoomInfo();
    } catch (e) {
      print('❌ Error connecting to LiveKit room: $e');
      _isConnecting = false;
      rethrow;
    } finally {
      _isConnecting = false;
    }
  }

  /// Disconnect from the current room
  /// 
  /// Parameters:
  /// - [reason]: Optional reason for disconnection (for analytics)
  Future<void> disconnect({
    String reason = 'User ended call', 
    bool sendDeclineNotification = false,
    String? callId,

    }) async {
    if (_room == null) {
      print('⚠️ No active room to disconnect from');
      return;
    }

    try {
      print('🔌 Disconnecting from LiveKit room...');

      // Capture disconnection info before cleanup
      _captureDisconnectionInfo(reason);

      if(_currentCallId != null){
        CallHandlingService().endActiveCall(callUUID:   _currentCallId ?? '');
      }
      if(callId != null){
        CallHandlingService().endActiveCall(callUUID: callId);
      }
      
      if(sendDeclineNotification && _currentChatId != null){
        WebSocketService().sendDeclineCall(_currentChatId!, "audio", _currentCallId!);
      }
      if(sendDeclineNotification && callId != null){
        WebSocketService().sendDeclineCall(_currentChatId!, "audio", callId);
      }

      // Cleanup room
      await _ensureRoomCleanup();
      print('✅ Disconnected from LiveKit room');
    } catch (e) {
      print('❌ Error disconnecting from room: $e');
    }
  }

  /// Ensure complete cleanup of room connection
  Future<void> _ensureRoomCleanup() async {
    if (_room != null) {
      print('🧹 Cleaning up LiveKit room...');

      try {
        // Stop ringtone if playing
        await _stopRingtone();
        
        // Stop duration timer
        _stopDurationTimer();

        // Cancel notification subscription
        _notificationSubscription?.cancel();
        _notificationSubscription = null;

        // Stop listening to events
        _listener?.cancelAll();
        _listener?.dispose();
        _listener = null;

        // Disconnect and dispose room
        await _room!.disconnect();
        await _room!.dispose();

        // Clear references
        _room = null;
        _remoteParticipants.clear();
        
        // Clear call metadata
        _currentCallId = null;
        _currentChatId = null;
        _chatId = null;
        _currentCallType = null;
        _currentCallData = null;
        _isJoining = false;
        _callDuration = 0;
        _startTime = null;
        _participantHistory.clear();
        _enableAudio = true;
        _enableVideo = false;
        // Reset call status
        print('📞 [STATUS CHANGE] Setting status to IDLE (cleanup)');
        _updateCallStatus(CallStatus.ended);
      } catch (e) {
        print('⚠️ Error during room cleanup: $e');
        // Force clear references even if cleanup fails
        await _stopRingtone();
        _notificationSubscription?.cancel();
        _notificationSubscription = null;
        _room = null;
        _listener = null;
        _remoteParticipants.clear();
        _currentCallId = null;
        _currentChatId = null;
        _chatId = null;
        _currentCallType = null;
        _currentCallData = null;
        _isJoining = false;
        _enableAudio = true;
        _enableVideo = false;
        
        _startTime = null;
        
        // Reset call status
        print('📞 [STATUS CHANGE] Setting status to IDLE (error cleanup)');
        _updateCallStatus(CallStatus.idle);
      }
    }

    _isConnecting = false;
  }

  /// Setup LiveKit room event listeners
  void _setupRoomListeners() {
    if (_room == null) return;

    _listener = _room!.createListener();

    _listener!
      ..on<RoomConnectedEvent>((event) {
        print('✅ Room connected event');
        _captureRoomInfo();
        
        // Enable audio/video now that room is connected
        if (_enableAudio) {
          _room?.localParticipant?.setMicrophoneEnabled(true);
        }
        if (_enableVideo) {
          _room?.localParticipant?.setCameraEnabled(true);
        }
        
        // Sync existing participants if any
        if (_room != null && _room!.remoteParticipants.isNotEmpty) {
          _remoteParticipants.addAll(_room!.remoteParticipants.values);
          for (var participant in _room!.remoteParticipants.values) {
            _addParticipantToHistory(participant, 'existing');
          }
          
          // Don't update status here - wait for call:start notification
          print('👥 Joined room with ${_room!.remoteParticipants.length} existing participants');
        }
        // Status remains as ringing until call:start notification is received
        
        
        if(_isJoining){
            _connectionEventController.add(ConnectionStateEvent(ConnectionStateType.connected));
            updateCallStatus(CallStatus.connecting);
        }else{
          _connectionEventController.add(ConnectionStateEvent(ConnectionStateType.ringing));
          updateCallStatus(CallStatus.ringing);
        }
        

      })
      ..on<RoomDisconnectedEvent>((event) {
        print('❌ Room disconnected: ${event.reason}');
        _connectionEventController.add(ConnectionStateEvent(
          ConnectionStateType.disconnected,
          disconnectReason: event.reason,
        ));
      })
      ..on<ParticipantConnectedEvent>((event) {
        print('👤 Participant connected: ${event.participant.name}');
        _remoteParticipants.add(event.participant);
        _addParticipantToHistory(event.participant, 'joined');
        
        // Don't update status to connected here - wait for call:start notification
        print('👤 Participant joined, waiting for call:start notification');
        
        _participantEventController.add(ParticipantChangeEvent(
          ParticipantChangeType.connected,
          event.participant,
        ));
      })
      ..on<ParticipantDisconnectedEvent>((event) {
        print('👤 Participant disconnected: ${event.participant.name}');
        _remoteParticipants.removeWhere((p) => p.sid == event.participant.sid);
        _addParticipantToHistory(event.participant, 'left');
        _participantEventController.add(ParticipantChangeEvent(
          ParticipantChangeType.disconnected,
          event.participant,
        ));
      })
      ..on<TrackMutedEvent>((event) {
        print('🔇 Track muted: ${event.publication.kind}');
        _trackEventController.add(TrackStateEvent(
          TrackStateType.muted,
          event.publication,
        ));
      })
      ..on<TrackUnmutedEvent>((event) {
        print('🔊 Track unmuted: ${event.publication.kind}');
        _trackEventController.add(TrackStateEvent(
          TrackStateType.unmuted,
          event.publication,
        ));
      })
      ..on<RoomReconnectingEvent>((event) {
        print('🔄 Room reconnecting...');
        _connectionEventController.add(ConnectionStateEvent(ConnectionStateType.reconnecting));
      })
      ..on<RoomReconnectedEvent>((event) {
        print('✅ Room reconnected');
        _connectionEventController.add(ConnectionStateEvent(ConnectionStateType.reconnected));
      });
  }

  /// Toggle microphone on/off
  Future<bool> toggleMicrophone() async {
    if (_room?.localParticipant == null) {
      print('⚠️ No local participant to toggle microphone');
      return false;
    }

    final isEnabled = _room!.localParticipant!.isMicrophoneEnabled();
    await _room!.localParticipant!.setMicrophoneEnabled(!isEnabled);
    print('🎤 Microphone ${!isEnabled ? "enabled" : "disabled"}');
    return !isEnabled;
  }

  /// Set microphone enabled state
  Future<void> setMicrophoneEnabled(bool enabled) async {
    if (_room?.localParticipant == null) {
      print('⚠️ No local participant to set microphone');
      return;
    }

    await _room!.localParticipant!.setMicrophoneEnabled(enabled);
    print('🎤 Microphone ${enabled ? "enabled" : "disabled"}');
  }

  /// Toggle camera on/off
  Future<bool> toggleCamera() async {
    if (_room?.localParticipant == null) {
      print('⚠️ No local participant to toggle camera');
      return false;
    }

    final isEnabled = _room!.localParticipant!.isCameraEnabled();
    await _room!.localParticipant!.setCameraEnabled(!isEnabled);
    print('📹 Camera ${!isEnabled ? "enabled" : "disabled"}');
    return !isEnabled;
  }

  /// Set camera enabled state
  Future<void> setCameraEnabled(bool enabled) async {
    if (_room?.localParticipant == null) {
      print('⚠️ No local participant to set camera');
      return;
    }

    await _room!.localParticipant!.setCameraEnabled(enabled);
    print('📹 Camera ${enabled ? "enabled" : "disabled"}');
  }

  /// Switch camera (front/back)
  Future<void> switchCamera() async {
    if (_room?.localParticipant == null) {
      print('⚠️ No local participant to switch camera');
      return;
    }

    try {
      final videoTrack = _room!.localParticipant!.videoTrackPublications.firstOrNull?.track;
      if (videoTrack is LocalVideoTrack) {
        // Toggle between front and back camera
        await videoTrack.setCameraPosition(CameraPosition.front);
        print('📹 Camera switched');
      } else {
        print('⚠️ No video track to switch camera');
      }
    } catch (e) {
      print('❌ Error switching camera: $e');
    }
  }

  /// Enable speaker output
  Future<void> setSpeakerEnabled(bool enabled) async {
    try {
      await Hardware.instance.setSpeakerphoneOn(enabled);
      print('🔊 Speaker ${enabled ? "enabled" : "disabled"}');
    } catch (e) {
      print('❌ Error setting speaker: $e');
    }
  }

  /// Start call duration timer
  void _startDurationTimer() {
    if (_durationTimer != null) return;

    _callDuration = 0;
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_startTime != null) {
        // Calculate duration based on server start time (epoch in seconds)
        final currentEpochSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        _callDuration = currentEpochSeconds - _startTime!;
      } else {
        // Fallback to simple counter if no start time available
        _callDuration++;
      }
    });
  }

  /// Stop call duration timer
  void _stopDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = null;
  }

  /// Format duration for display
  String formatDuration([int? seconds]) {
    final duration = seconds ?? _callDuration;
    final minutes = (duration / 60).floor();
    final remainingSeconds = duration % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  /// Capture room information
  void _captureRoomInfo() {
    if (_room == null) return;

    _roomInfo.clear();
    _roomInfo.addAll({
      'roomName': _room!.name ?? 'Unknown',
      'connectedAt': DateTime.now().toIso8601String(),
      'localParticipant': {
        'name': _room!.localParticipant?.name ?? 'Unknown',
        'sid': _room!.localParticipant?.sid ?? 'Unknown',
        'identity': _room!.localParticipant?.identity ?? 'Unknown',
      },
      'remoteParticipantCount': _room!.remoteParticipants.length,
    });

    print('📊 Room info captured: $_roomInfo');
  }

  /// Capture disconnection information
  void _captureDisconnectionInfo(String reason) {
    _roomInfo['disconnectedAt'] = DateTime.now().toIso8601String();
    _roomInfo['disconnectionReason'] = reason;
    _roomInfo['callDuration'] = _callDuration;
    _roomInfo['formattedDuration'] = formatDuration();
    _roomInfo['participantHistory'] = List.from(_participantHistory);

    print('📊 Final room info: $_roomInfo');
  }

  /// Add participant to history tracking
  void _addParticipantToHistory(Participant participant, String action) {
    final participantInfo = {
      'name': participant.name.isEmpty ? 'Unknown' : participant.name,
      'sid': participant.sid,
      'identity': participant.identity,
      'action': action, // 'joined', 'left', 'existing'
      'timestamp': DateTime.now().toIso8601String(),
    };

    _participantHistory.add(participantInfo);
    print('👤 Participant $action: ${participant.name}');
  }

  /// Get call summary
  Map<String, dynamic> getCallSummary() {
    return {
      ...roomInfo,
      'totalParticipants': _participantHistory.length,
      'callDuration': _callDuration,
      'formattedDuration': formatDuration(),
    };
  }

 

  Future<void> _handleIncomingNotification(
      Map<String, dynamic> notificationData) async {
    

    // // Guard: Don't process if call is already ending
    // if (_isEndingCall) {
    //   print("⚠️ Notification received but call already ending, ignoring");
    //   return;
    // }

    // Guard: Don't process if room is already null
    if (_room == null) {
      print("⚠️ Notification received but room already disposed, ignoring");
      return;
    }

    print("Received notification: $notificationData");
    final action = notificationData['action'];
    final notificationChatId = notificationData['chatId'];
    final notificationCallId = notificationData['callId'];
    
    
    // Only process if it's for THIS call and matches the call type
    if ((action == 'call:declined' || action == 'call:ended') && 
        _currentCallType == CallType.single && 
        notificationChatId == _chatId
        ) {
      print("📞 Processing call $action notification for chat $_chatId");
      await disconnect(sendDeclineNotification: false);
    }
    
    // Handle call:start notification
    print("Current call id : $_currentCallId, notification call id: $notificationCallId");
    if (action == "call:start" && 
        notificationCallId == _currentCallId) {
      print("📞 Processing call:start notification for call $_currentCallId");
      
      final startsAt = notificationData['startsAt'];
      
      if (startsAt != null) {
        _startTime = startsAt as int?;
        print("⏰ Call start time set to: $_startTime");
      }
      print('📞 [STATUS CHANGE] Setting status to CONNECTED (call:start notification)');
      updateCallStatus(CallStatus.connected);
    }
  }



 
  /// Dispose resources and close stream controllers
  void dispose() {
    print('🧹 Disposing LiveKit service...');
    
    // Cancel notification subscription
    _notificationSubscription?.cancel();
    _notificationSubscription = null;
    
    // Cleanup room
    _ensureRoomCleanup();
    
    // Close grouped stream controllers
    _connectionEventController.close();
    _participantEventController.close();
    _trackEventController.close();
    
    print('🟢 ✅ LiveKit service disposed');
  }
}
