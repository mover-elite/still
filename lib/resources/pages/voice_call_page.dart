import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/app/networking/chat_api_service.dart';
import 'package:flutter_app/app/networking/websocket_service.dart';
import 'package:nylo_framework/nylo_framework.dart';
import 'dart:async';
import 'package:livekit_client/livekit_client.dart';
import 'package:audioplayers/audioplayers.dart';

// ✅ Call states for tracking call progress
enum CallState { requesting, ringing, connected }

// ✅ Call types supported
enum CallType { single, group }

// ✅ Participant data model
class CallParticipant {
  final String name;
  final String image;
  final bool isSelf;

  CallParticipant({
    required this.name,
    required this.image,
    this.isSelf = false,
  });
}

class VoiceCallPage extends NyStatefulWidget {
  static RouteView path = ("/voice-call", (_) => VoiceCallPage());

  VoiceCallPage({super.key}) : super(child: () => _VoiceCallPageState());
}

class _VoiceCallPageState extends NyPage<VoiceCallPage>
    with TickerProviderStateMixin {
  CallState _callState = CallState.requesting; // ✅ Start with requesting state
  bool _isMuted = false;
  bool _isSpeaker = false;
  bool _isVideoOn = false;
  int _callDuration = 0; // ✅ Track call duration in seconds
  AudioPlayer? _audioPlayer;
  // Call data - you can pass this as parameters
  CallType _callType =
      CallType.single; // Change to CallType.group for group calls

  StreamSubscription<Map<String, dynamic>>? _notificationSubscription;
  bool _isEndingCall = false; // Flag to prevent duplicate end call processing
  // Single call data
  String _contactName = "Layla B";
  String? _contactImage;
  String defaultImage = "image2.png";
  int? _chatId; // Example chat ID
  int? _callerId; // ID of the caller (for incoming calls)
  bool _isJoining = false; // Flag to indicate if joining an incoming call
  // Group call data
  String _groupName = "Our Loving Pets";
  String _groupImage = "image9.png";

  List<CallParticipant> _participants = [
    CallParticipant(name: "You", image: "image6.png", isSelf: true),
    CallParticipant(name: "Layla B", image: "image2.png"),
    CallParticipant(name: "Layla B", image: "image2.png"),
    CallParticipant(name: "Layla B", image: "image2.png"),
    CallParticipant(name: "Layla B", image: "image2.png"),
    CallParticipant(name: "Layla B", image: "image2.png"),
  ];

  // Call timer
  Timer? _timer;

  // ✅ LiveKit integration
  Room? _room;
  List<RemoteParticipant> _remoteParticipants = [];
  EventsListener<RoomEvent>? _listener;
  bool _isConnecting = false; // Prevent simultaneous connection attempts

  // ✅ Room information preservation
  Map<String, dynamic> _roomInfo = {}; // Store room info for post-call access
  List<Map<String, dynamic>> _participantHistory =
      []; // Track all participants who joined

  // Animation controllers
  late AnimationController _pulseController;
  late AnimationController _fadeController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _fadeAnimation;

  @override
  get init => () {
        // Initialize animations first
        _pulseController = AnimationController(
          duration: const Duration(milliseconds: 1000),
          vsync: this,
        );

        _fadeController = AnimationController(
          duration: const Duration(milliseconds: 800),
          vsync: this,
        );

        _pulseAnimation = Tween<double>(
          begin: 1.0,
          end: 1.2,
        ).animate(CurvedAnimation(
          parent: _pulseController,
          curve: Curves.easeInOut,
        ));

        _fadeAnimation = Tween<double>(
          begin: 0.5,
          end: 1.0,
        ).animate(CurvedAnimation(
          parent: _fadeController,
          curve: Curves.easeInOut,
        ));

        // Start animations for requesting/ringing states
        if (_callState == CallState.requesting ||
            _callState == CallState.ringing) {
          _pulseController.repeat(reverse: true);
          _fadeController.repeat(reverse: true);
        }

        // Then extract call data and potentially start the call
        _extractCallData();

        _notificationSubscription =
            WebSocketService().notificationStream.listen((notificationData) {
          _handleIncomingNotification(notificationData);
        });
      };

    Future<void> _playRingtone() async {
    _audioPlayer?.stop();
    _audioPlayer = AudioPlayer();
    await _audioPlayer!.setReleaseMode(ReleaseMode.loop);
    
    if(_isJoining){
    //   await _audioPlayer!.play(AssetSource('audio/iphone_ringing_tone.mp3'));
    }else{
      await _audioPlayer!.play(AssetSource('audio/ringing_initiated.mp3'));
    }
  }

  Future<void> _stopRingtone() async {
    try{
      await _audioPlayer?.stop();
      await _audioPlayer?.dispose();
      _audioPlayer = null;
    }catch(e){

    }
    
  }

  Future<void> _handleIncomingNotification(
      Map<String, dynamic> notificationData) async {
    // Guard: Don't process if already disposed or not mounted
    if (!mounted) {
      print("⚠️ Notification received but widget not mounted, ignoring");
      return;
    }

    // Guard: Don't process if call is already ending
    if (_isEndingCall) {
      print("⚠️ Notification received but call already ending, ignoring");
      return;
    }

    // Guard: Don't process if room is already null
    if (_room == null) {
      print("⚠️ Notification received but room already disposed, ignoring");
      return;
    }

    print("Received notification: $notificationData");
    final action = notificationData['action'];
    final notificationChatId = notificationData['chatId'];
    final notificationType = notificationData['type'];
    
    // Only process if it's for THIS call and matches the call type
    if ((action == 'call:declined' || action == 'call:ended') && 
        _callType == CallType.single && 
        notificationChatId == _chatId &&
        notificationType == 'audio') {
      print("📞 Processing call $action notification for chat $_chatId");
      
      // Don't send decline notification since we received one
      // _endCall will set _isEndingCall flag and cancel subscription
      await _endCall(sendDeclineNotification: false);
    }
  }

  void _extractCallData() async {
    final navigationData = data();
    print(navigationData);

    if (navigationData != null) {
      if (navigationData['isGroup'] == true) {
        _callType = CallType.group;
        _groupName = navigationData['groupName'] ?? _groupName;
        _groupImage = navigationData['groupImage'] ?? _groupImage;
        // _participants = (navigationData['participants'] as List)
        //     .map((p) => CallParticipant.fromJson(p))
        //     .toList();
      } else {
        _callType = CallType.single;
        final partner = navigationData['partner'];
        _contactName = partner['username'] ?? _contactName;
        _contactImage = partner['avatar'];
        
        
        _chatId = navigationData['chatId'];
        _callerId =
            navigationData['callerId']; // Get caller ID for incoming calls
        _isJoining = navigationData['isJoining'] ??
            false; // Check if joining incoming call
        final bool initiateCall = navigationData['initiateCall'] ?? false;

        if (_isJoining) {
          // For incoming calls, start directly in requesting state
          setState(() {
            _callState = CallState.requesting;

          });
          _startRequestingAnimations();

          // Delay joining the existing call
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _joinCall();
            }
          });
        } else if (initiateCall) {
          // Delay call initiation until widget is fully mounted
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _startCall();
            }
          });
        }
      }
    } else {
      // Delay navigation until after the build is complete
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          routeToAuthenticatedRoute();
        }
      });
    }
  }

  /// ✅ Start call with proper state flow: requesting → ringing → connected
  void _startCall() async {
    if (_chatId == null) {
      print("❌ Chat ID is required to initiate a call.");
      _showErrorDialog("Chat ID is required to initiate a call.");
      return;
    }

    try {
      // ✅ State 1: Requesting - Getting token from API
      setState(() {
        _callState = CallState.requesting;
      });
      _startRequestingAnimations();

      print("🔄 Requesting call token for chat ID: $_chatId");

      ChatApiService chatApiService = ChatApiService();
      final response = await chatApiService.initiateVoiceCall(_chatId!);

      if (response == null || response.callToken.isEmpty) {
        print("❌ Failed to get call token. Please try again.");
        _showErrorDialog("Failed to get call token. Please try again.");
        return;
      }

      print("✅ Call token received: ${response.callToken}");

      // ✅ State 2: Ringing - Room setup completed, waiting for other party
      setState(() {
        _callState = CallState.ringing;
      });
      _startRingingAnimations();

      // Initialize LiveKit room
      final url = 'ws://217.77.4.167:7880';
      await _initializeLiveKitRoom(response.callToken, url);
    } catch (e) {
      print("❌ Error starting call: $e");
      _showErrorDialog("Failed to start call: $e");
    }
  }

  /// ✅ Join an existing call (for incoming calls)
  void _joinCall() async {
    if (_chatId == null) {
      print("❌ Chat ID is required to join a call.");
      _showErrorDialog("Chat ID is required to join a call.");
      return;
    }

    try {
      print("🔄 Joining call for chat ID: $_chatId from caller: $_callerId");

      ChatApiService chatApiService = ChatApiService();
      final response = await chatApiService.joinVoiceCall(_chatId!);

      if (response == null || response.callToken.isEmpty) {
        print("❌ Failed to get call token for joining. Please try again.");
        _showErrorDialog("Failed to join call. Please try again.");
        return;
      }

      print("✅ Join call token received: ${response.callToken}");

      // Initialize LiveKit room for joining
      final url = 'ws://217.77.4.167:7880';
      await _initializeLiveKitRoom(response.callToken, url);
    } catch (e) {
      print("❌ Error joining call: $e");
      _showErrorDialog("Failed to join call: $e");
    }
  }

  /// ✅ Start animations for requesting state
  void _startRequestingAnimations() {
    _pulseController.repeat(reverse: true);
    _fadeController.repeat(reverse: true);
  }

  /// ✅ Start animations for ringing state
  void _startRingingAnimations() {
    // Animations continue from requesting state
    _playRingtone();
    if (!_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
      _fadeController.repeat(reverse: true);
    }
  }

  /// ✅ Stop all animations when connected
  void _stopAllAnimations() {
    _pulseController.stop();
    _fadeController.stop();
    _pulseController.reset();
    _fadeController.reset();
   
  }

  Future<void> _initializeLiveKitRoom(String token, String url) async {
    // Prevent simultaneous connection attempts
    if (_isConnecting) {
      print("⚠️ Connection attempt already in progress, skipping...");
      return;
    }

    try {
      _isConnecting = true;
      print("🔄 Setting up LiveKit room...");
      print("Current room  ${_room}");
      print("Current room remote: ${_room?.remoteParticipants}");
      print("Current room local: ${_room?.localParticipant}");
      // Ensure complete cleanup of any existing room connection
      await _ensureRoomCleanup();

      // Create fresh room instance
      _room = Room();

      // Setup event listeners
      _setupRoomListeners();

      // Connect to room
      await _room!.connect(
        url,
        token,
        connectOptions: const ConnectOptions(
          autoSubscribe: true,
        ),
      );

      print("✅ LiveKit room setup completed, waiting for participants...");

      // Enable audio by default
      await _room!.localParticipant?.setMicrophoneEnabled(true);
    } catch (e) {
      print("❌ Error setting up LiveKit room: $e");
      _showErrorDialog("Failed to setup call room: $e");
    } finally {
      _isConnecting = false;
    }
  }

  /// ✅ Ensure complete cleanup of any existing room connection
  Future<void> _ensureRoomCleanup() async {
    if (_room != null) {
      print("🧹 Cleaning up existing room connection...");

      try {
        // Stop listening to events first
        _listener?.cancelAll();
        _listener?.dispose();

        _listener = null;

        // Disconnect and dispose room
        await _room!.disconnect();
        await _room!.dispose();

        // Clear references
        _room = null;
        _remoteParticipants.clear();

        print("✅ Room cleanup completed");
      } catch (e) {
        print("⚠️ Error during room cleanup: $e");
        // Force clear references even if cleanup fails
        _room = null;
        _listener = null;
        _remoteParticipants.clear();
      }
    }

    // Reset connection flag
    _isConnecting = false;
  }

  /// ✅ Capture room information when connected
  void _captureRoomInfo() {
    if (_room != null) {
      _roomInfo = {
        'roomName': _room!.name,
        'connectedAt': DateTime.now().toIso8601String(),
        'localParticipant': {
          'name': _room!.localParticipant?.name ?? 'Unknown',
          'sid': _room!.localParticipant?.sid ?? 'Unknown',
          'identity': _room!.localParticipant?.identity ?? 'Unknown',
        },
        'remoteParticipantCount': _room!.remoteParticipants.length,
        'chatId': _chatId,
        'callerId': _callerId,
        'isJoining': _isJoining,
      };

      print('📊 Room info captured: $_roomInfo');
    }
  }

  /// ✅ Capture disconnection information
  void _captureDisconnectionInfo(String reason) {
    _roomInfo['disconnectedAt'] = DateTime.now().toIso8601String();
    _roomInfo['disconnectionReason'] = reason;
    _roomInfo['callDuration'] = _callDuration;
    _roomInfo['participantHistory'] = List.from(_participantHistory);

    print('📊 Final room info: $_roomInfo');

    // You can save this to local storage, send to analytics, etc.
    _saveRoomInfoToAnalytics();
  }

  /// ✅ Add participant to history tracking
  void _addParticipantToHistory(Participant participant, String action) {
    final participantInfo = {
      'name': participant.name.isEmpty ? 'Unknown' : participant.name,
      'sid': participant.sid,
      'identity': participant.identity,
      'action': action, // 'joined' or 'left'
      'timestamp': DateTime.now().toIso8601String(),
    };

    _participantHistory.add(participantInfo);
    print('👤 Participant $action: ${participant.name}');
  }

  /// ✅ Save room information for analytics or debugging
  void _saveRoomInfoToAnalytics() {
    // Example: Save to local storage, send to server, etc.
    print('💾 Saving room analytics data...');
    print('Call Summary:');
    print('  Duration: ${_formatDuration(_callDuration)}');
    print('  Participants: ${_participantHistory.length}');
    print('  Disconnection reason: ${_roomInfo['disconnectionReason']}');

    // You could implement:
    // - Local storage save
    // - API call to save call history
    // - Analytics tracking
  }

  /// ✅ Get room information (accessible even after call ends)
  Map<String, dynamic> getRoomInfo() {
    return Map.from(_roomInfo);
  }

  /// ✅ Get participant history (accessible even after call ends)
  List<Map<String, dynamic>> getParticipantHistory() {
    return List.from(_participantHistory);
  }

  /// ✅ Setup LiveKit room event listeners
  void _setupRoomListeners() {
    _listener = _room!.createListener();

    _listener!
      ..on<RoomConnectedEvent>((event) {
        print('✅ Connected to LiveKit room');

        // Capture room information when connected
        _captureRoomInfo();

        // Check if there are already participants in the room (for joiners)
        if (_room != null && _room!.remoteParticipants.isNotEmpty) {
          print('👥 Found existing participants, joining active call');
          if (mounted) {
            setState(() {
              _callState = CallState.connected;
              _remoteParticipants.addAll(_room!.remoteParticipants.values);
            });
            _stopAllAnimations();
            _stopRingtone();
            _startTimer();
          }
        } else {
          print('📞 Room connected, waiting for other participants...');
          // Stay in ringing state until another participant joins
        }
      })
      ..on<RoomDisconnectedEvent>((event) {
        print('❌ Disconnected from room: ${event.reason}');

        // Capture final room state before cleanup
        _captureDisconnectionInfo(event.reason?.toString() ?? 'Unknown');

        if (mounted) {
          Navigator.pop(context);
        }
      })
      ..on<ParticipantConnectedEvent>((event) {
        print('👤 Participant connected: ${event.participant.name}');

        // Track participant joining
        _addParticipantToHistory(event.participant, 'joined');

        // ✅ State 3: Connected - Other party joined the call
        if (mounted) {
          setState(() {
            _callState = CallState.connected;
            _remoteParticipants.add(event.participant);
          });
          _stopAllAnimations();
          _stopRingtone();
          // Only start timer if not already started
          if (_timer == null) {
            _startTimer();
          }
        }
      })
      ..on<ParticipantDisconnectedEvent>((event) {
        print('👤 Participant disconnected: ${event.participant.name}');

        // Track participant leaving
        _addParticipantToHistory(event.participant, 'left');

        if (mounted) {
          setState(() {
            _remoteParticipants
                .removeWhere((p) => p.sid == event.participant.sid);
          });

          // If no remote participants, end the call
          if (_remoteParticipants.isEmpty &&
              _callState == CallState.connected) {
            _endCall();
          }
        }
      })
      ..on<TrackMutedEvent>((event) {
        print('🔇 Track muted: ${event.publication.kind}');
        if (mounted && event.participant is LocalParticipant) {
          setState(() {
            _isMuted = !_room!.localParticipant!.isMicrophoneEnabled();
          });
        }
      })
      ..on<TrackUnmutedEvent>((event) {
        print('🔊 Track unmuted: ${event.publication.kind}');
        if (mounted && event.participant is LocalParticipant) {
          setState(() {
            _isMuted = !_room!.localParticipant!.isMicrophoneEnabled();
          });
        }
      });
  }

  /// ✅ Start call duration timer
  void _startTimer() {
    // Prevent starting multiple timers
    if (_timer != null) {
      return;
    }

    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _callDuration++;
        });
      }
    });
  }

  /// ✅ Stop and cleanup timer
  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// ✅ Format call duration for display
  String _formatDuration(int seconds) {
    final minutes = (seconds / 60).floor();
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  /// ✅ Mute/unmute microphone
  Future<void> _toggleMute() async {
    if (_room?.localParticipant != null) {
      final enabled = _room!.localParticipant!.isMicrophoneEnabled();
      await _room!.localParticipant!.setMicrophoneEnabled(!enabled);
      if (mounted) {
        setState(() {
          _isMuted = !enabled;
        });
      }
    }
  }

  /// ✅ End the call and navigate back
  /// [sendDeclineNotification] - if true, sends decline notification to other party
  /// Set to false when ending due to receiving a decline notification
  Future<void> _endCall({bool sendDeclineNotification = true}) async {
    // Guard: Prevent duplicate end call processing
    if (_isEndingCall) {
      print("⚠️ _endCall already in progress, skipping duplicate call");
      return;
    }
    
    _isEndingCall = true;
    print("📞 Starting call end process...");
    
    try {
      // Cancel notification subscription immediately
      await _notificationSubscription?.cancel();
      _notificationSubscription = null;
      
      _stopTimer();
      _stopAllAnimations();

      // Capture final room state before cleanup
      if (_room != null) {
        _captureDisconnectionInfo('User ended call');
      }

      // Use our comprehensive cleanup method
      await _ensureRoomCleanup();

      // Example: Show call summary before leaving
      _showCallSummary();

      // Send decline notification only if this user initiated the end
      // Don't send if we're ending because we received a decline notification
      if (_chatId != null && sendDeclineNotification) {
        print("📞 Sending decline notification to other party");
        WebSocketService().sendDeclineCall(_chatId!, "audio");
      } else if (!sendDeclineNotification) {
        print("📞 Not sending decline notification (received from other party)");
      }
      
      // Safely pop the navigator
      if (mounted && Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      print("❌ Error ending call: $e");
      // Try to pop even on error, but check if possible
      if (mounted && Navigator.canPop(context)) {
        try {
          Navigator.of(context).pop();
        } catch (navError) {
          print("Could not pop navigator: $navError");
        }
      }
    }
  }

  /// ✅ Show call summary with preserved room information
  void _showCallSummary() {
    final duration = _formatDuration(_callDuration);
    final participantCount = _participantHistory.length;

    print('📞 Call Summary:');
    print('   Duration: $duration');
    print('   Participants: $participantCount');
    print('   Room Info: $_roomInfo');
    print('   Participant History: $_participantHistory');

    // You can show this in a dialog, save to database, etc.
  }

  /// ✅ Show error dialog and navigate back
  void _showErrorDialog(String message) {
    // Ensure widget is mounted and context is available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Text('Call Error'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).pop();
                },
                child: Text('OK'),
              ),
            ],
          ),
        );
      }
    });
  }

  /// ✅ Get call status text based on current state
  String _getCallStatusText() {
    switch (_callState) {
      case CallState.requesting:
        return _isJoining ? "Joining call..." : "Requesting call...";
      case CallState.ringing:
        if (_callType == CallType.group) {
          return _isJoining ? "Joining Group..." : "Calling Group...";
        } else {
          return _isJoining ? "Incoming call..." : "Ringing...";
        }
      case CallState.connected:
        return _formatDuration(_callDuration);
    }
  }

  /// ✅ Build animated timer/status text
  Widget _buildAnimatedTimer() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      child: Text(
        _getCallStatusText(),
        key: ValueKey(_callState),
        style: TextStyle(
          color: _callState == CallState.connected
              ? Color(0xFFE8E7EA)
              : Colors.grey.shade400,
          fontSize: 16,
          fontWeight: _callState == CallState.connected
              ? FontWeight.w600
              : FontWeight.normal,
        ),
      ),
    );
  }

  @override
  void dispose() {
    print("🧹 Disposing voice call page...");
    
    // Set ending flag to prevent further processing
    _isEndingCall = true;
    
    // Cancel notification subscription first
    _notificationSubscription?.cancel();
    _notificationSubscription = null;
    
    // Ensure proper cleanup on widget disposal
    _stopTimer();
    _stopAllAnimations();
    _audioPlayer?.dispose();
    
    // Clean up room connection asynchronously
    _ensureRoomCleanup().then((_) {
      print("🧹 Widget disposal cleanup completed");
    }).catchError((e) {
      print("⚠️ Error during widget disposal cleanup: $e");
    });
    
    _pulseController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget view(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF0F131B),
      body: SafeArea(
        child: Column(
          children: [
            // Status bar and header
            _buildHeader(),

            // Main call content
            Expanded(
              child: _callType == CallType.single
                  ? _buildSingleCallContent()
                  : _buildGroupCallContent(),
            ),

            // Control buttons
            _buildControlButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    if (_callType == CallType.group && _callState == CallState.connected) {
      return Container(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
              ),
              child: ClipOval(
                child: Image.asset(
                  _groupImage,
                  fit: BoxFit.cover,
                ).localAsset(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _groupName,
                    style: const TextStyle(
                      color: Color(0xFFE8E7EA),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 500),
                    child: Text(
                      _getCallStatusText(),
                      key: ValueKey(_callState),
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 12,
                        fontWeight: _callState == CallState.connected
                            ? FontWeight.w500
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Color(0xFFE8E7EA).withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.people,
                    color: Color(0xFFE8E7EA),
                    size: 12,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    "${_participants.length} Joined",
                    style: const TextStyle(
                      color: Color(0xFFE8E7EA),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Container();
  }

  Widget _buildSingleCallContent() {

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Profile image with pulsating animation
        AnimatedBuilder(
          animation: _callState == CallState.ringing
              ? _pulseAnimation
              : AlwaysStoppedAnimation(1.0),
          builder: (context, child) {
            return Transform.scale(
              scale: _pulseAnimation.value,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: _callState == CallState.ringing
                      ? [
                          BoxShadow(
                            color: Color(0xFFE8E7EA).withOpacity(0.3),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ]
                      : [],
                ),
                child: ClipOval(
                  child: 
                  (_contactImage != null)
                      ?
                       Image.network(
                            "${getEnv('API_BASE_URL')}$_contactImage",
                          fit: BoxFit.cover,
                          
                        )
                      : Image.asset(
                          defaultImage,
                          fit: BoxFit.cover,
                        ).localAsset()
                ),
                ),
              
            );
          },
        ),
        const SizedBox(height: 32),

        // Contact name
        Text(
          _contactName,
          style: const TextStyle(
            color: Color(0xFFE8E7EA),
            fontSize: 24,
            fontWeight: FontWeight.w600,
          ),
        ),

        const SizedBox(height: 8),

        // Call status with animated timer
        _callState == CallState.ringing
            ? AnimatedBuilder(
                animation: _fadeAnimation,
                builder: (context, child) {
                  return Opacity(
                    opacity: _fadeAnimation.value,
                    child: Text(
                      _getCallStatusText(),
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 16,
                      ),
                    ),
                  );
                },
              )
            : _buildAnimatedTimer(),
      ],
    );
  }

  Widget _buildGroupCallContent() {
    if (_callState == CallState.ringing) {
      // Show main caller during ringing state
      String mainCaller = "Fenta"; // This could be dynamic
      String mainCallerImage = "image8.png";

      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Group info at top
          Text(
            "Fenta, Layla B & Ahmad", // Dynamic group member names
            style: const TextStyle(
              color: Color(0xFFE8E7EA),
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            "02:12:33", // Call duration or time
            style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 14,
            ),
          ),

          const SizedBox(height: 60),

          // Main caller with pulsating animation
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _pulseAnimation.value,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Color(0xFFE8E7EA).withOpacity(0.3),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      mainCallerImage,
                      fit: BoxFit.cover,
                    ).localAsset(),
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 20),

          Text(
            mainCaller,
            style: const TextStyle(
              color: Color(0xFFE8E7EA),
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 8),

          AnimatedBuilder(
            animation: _fadeAnimation,
            builder: (context, child) {
              return Opacity(
                opacity: _fadeAnimation.value,
                child: Text(
                  "Ringing...",
                  style: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 16,
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 60),

          // Small participant avatars
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildSmallAvatar("image2.png", "Layla B"),
              const SizedBox(width: 24),
              _buildSmallAvatar("image6.png", "You", isSelf: true),
            ],
          ),
        ],
      );
    } else {
      // Show participant grid during connected state
      return Column(
        children: [
          const SizedBox(height: 40),

          // Participants grid
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1,
              ),
              itemCount: _participants.length,
              itemBuilder: (context, index) {
                final participant = _participants[index];
                return _buildParticipantCard(participant);
              },
            ),
          ),

          // Page indicators if needed
          if (_participants.length > 6)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (index) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: index == 0 ? Color(0xFFE8E7EA) : Colors.grey,
                    shape: BoxShape.circle,
                  ),
                );
              }),
            ),

          const SizedBox(height: 20),
        ],
      );
    }
  }

  Widget _buildSmallAvatar(String image, String name, {bool isSelf = false}) {
    return Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: isSelf
                ? Border.all(color: const Color(0xFF3498DB), width: 2)
                : null,
          ),
          child: ClipOval(
            child: Image.asset(
              image,
              fit: BoxFit.cover,
            ).localAsset(),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          name,
          style: const TextStyle(
            color: Color(0xFFE8E7EA),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildParticipantCard(CallParticipant participant) {
    return Container(
      decoration: BoxDecoration(
        color: participant.isSelf
            ? const Color(0xFF3498DB).withOpacity(0.3)
            : const Color(0xFF1C212C),
        borderRadius: BorderRadius.circular(12),
        border: participant.isSelf
            ? Border.all(color: const Color(0xFF3498DB), width: 2)
            : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
            ),
            child: ClipOval(
              child: Image.asset(
                participant.image,
                fit: BoxFit.cover,
              ).localAsset(),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            participant.name,
            style: const TextStyle(
              color: Color(0xFFE8E7EA),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButtons() {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Speaker button
          _buildControlButton(
            icon: _isSpeaker ? Icons.volume_up : Icons.volume_down,
            label: "Speaker",
            isActive: _isSpeaker,
            onTap: () {
              setState(() {
                _isSpeaker = !_isSpeaker;
              });
              HapticFeedback.lightImpact();
            },
          ),

          // Video button
          _buildControlButton(
            icon: _isVideoOn ? Icons.videocam : Icons.videocam_off,
            label: "Video",
            isActive: _isVideoOn,
            onTap: () {
              setState(() {
                _isVideoOn = !_isVideoOn;
              });
              HapticFeedback.lightImpact();
            },
          ),

          // Mute button
          _buildControlButton(
            icon: _isMuted ? Icons.mic_off : Icons.mic,
            label: "Mute",
            isActive: _isMuted,
            onTap: () async {
              await _toggleMute();
              HapticFeedback.lightImpact();
            },
          ),

          // End call button
          _buildControlButton(
            icon: Icons.call_end,
            label: "End Call",
            isActive: false,
            isEndCall: true,
            onTap: () async {
              HapticFeedback.lightImpact();
              await _endCall();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    bool isEndCall = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isEndCall
                  ? const Color(0xFFE74C3C)
                  : isActive
                      ? const Color(0xFF3498DB)
                      : Color(0xFFE8E7EA).withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: Color(0xFFE8E7EA),
              size: 24,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFE8E7EA),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
