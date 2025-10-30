import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/app/networking/chat_api_service.dart';
import 'package:flutter_app/app/networking/websocket_service.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:nylo_framework/nylo_framework.dart';
import 'dart:async';
import 'package:permission_handler/permission_handler.dart';
import 'package:camera/camera.dart';
import 'package:audioplayers/audioplayers.dart';

enum CallType { single, group }

enum CallState { requesting, ringing, connected }

class VideoCallPage extends NyStatefulWidget {
  static RouteView path = ("/video-call", (_) => VideoCallPage());

  VideoCallPage({super.key}) : super(child: () => _VideoCallPageState());
}

class _VideoCallPageState extends NyPage<VideoCallPage>
    with TickerProviderStateMixin {
  void routeToAuthenticatedRoute() {
    Navigator.of(context).pushReplacementNamed('/auth');
  }

  bool _isMuted = false;
  bool _isVideoOn = true;
  AudioPlayer? _audioPlayer;
  // LIVEKIT ROOM
  Room? _room;
  List<RemoteParticipant> _remoteParticipants = [];
  bool _isConnecting = false; // Prevent simultaneous connection attempts
  bool _isEndingCall = false; // Flag to prevent duplicate end call processing
  EventsListener<RoomEvent>? _listener;
  // Remove unused _isCameraOn since we're using _isVideoOn for video state
  List<Map<String, dynamic>> _participantHistory =
      []; // Track all participants who joined

  // Call timer
  Timer? _timer;
  int _seconds = 45; // Start with some time for demo
  CallType _callType = CallType.single;
  int? _chatId; // Example chat ID
  String _groupName = "Our Loving Pets";
  String _groupImage = "image9.png";
  String _contactName = "Layla B";
  String _contactImage = "image2.png";
  bool _isJoining = false;
  CallState _callState = CallState.requesting;
  // Call participants - modify this list to test different layouts
  List<VideoParticipant> _participants = [
    VideoParticipant(
      name: "Fenta",
      image: "female.jpg",
      isSelf: false,
      isMuted: false,
    ),
    VideoParticipant(
      name: "You",
      image: "male.jpg",
      isSelf: true,
      isMuted: false,
    ),
     
  ];

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  StreamSubscription<Map<String, dynamic>>? _notificationSubscription;

  @override
  get init => () {
        _fadeController = AnimationController(
          duration: const Duration(milliseconds: 300),
          vsync: this,
        );

        _fadeAnimation = Tween<double>(
          begin: 0.0,
          end: 1.0,
        ).animate(CurvedAnimation(
          parent: _fadeController,
          curve: Curves.easeInOut,
        ));

        _fadeController.forward();
        _startTimer();
        _extractCallData(); // Extract call data on initialization
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
      await _audioPlayer!.play(AssetSource('audio/iphone_ringing_tone.mp3'));
    }else{
      await _audioPlayer!.play(AssetSource('audio/ringing_initiated.mp3'));
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
        _contactImage = partner['avatar'] ?? _contactImage;
        _chatId = navigationData['chatId'];
        _isJoining = navigationData['isJoining'] ??
            false; // Check if joining incoming call
        final bool initiateCall = navigationData['initiateCall'] ?? false;
        await _ensurePermissions(); // Ensure permissions are handled
        if (_isJoining) {
          // For incoming calls, start directly in ringing state
          print("Is   JOINING");
          setState(() {
            _callState = CallState.requesting;
          });
          _startRingingAnimations();

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
        notificationType == 'video') {
      print("📞 Processing call $action notification for chat $_chatId");
      
      // Don't send decline notification since we received one
      // _endCall will set _isEndingCall flag and cancel subscription
      await _endCall(sendDeclineNotification: false);
    }
  }

  @override
  void dispose() {
    print("🧹 Disposing video call page...");
    
    // Set ending flag to prevent further processing
    _isEndingCall = true;
    
    // Cancel notification subscription first
    _notificationSubscription?.cancel();
    _notificationSubscription = null;
    
    _timer?.cancel();
    _fadeController.dispose();
    _audioPlayer?.dispose();

    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if(!mounted){
        timer.cancel();
        return;
      }

      if(mounted){
        setState(() {
        _seconds++;
      });
      }
      
    });
  }

  String _formatDuration() {
    int minutes = _seconds ~/ 60;
    int secs = _seconds % 60;
    return "${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}";
  }

  void _startRingingAnimations() {
    // Add any ringing animations here
    // For example, vibration pattern or UI animations
    HapticFeedback.heavyImpact();
    _playRingtone();
  }

    Future<void> _ensurePermissions() async {
      final cameraStatus = await Permission.camera.request();
      final microphoneStatus = await Permission.microphone.request();
      print("Camera permission: $cameraStatus");
      print("Microphone permission: $microphoneStatus");

    }

  Future<void> _joinCall() async {
    try {
      await _ensurePermissions(); // <-- Add this line
      ChatApiService chatApiService = ChatApiService();
      final response = await chatApiService.joinVideoCall(_chatId!);
      if (response == null || response.callToken.isEmpty) {
        print("❌ Failed to get call token. Please try again.");
        // _showErrorDialog("Failed to get call token. Please try again.");
        return;
      }
      final url = 'ws://217.77.4.167:7880';
      await _initializeLiveKitRoom(response.callToken, url);

      setState(() {
        _callState = CallState.connected;
      });
      // Add your call joining logic here
      // For example, connecting to WebRTC or your video call service
    } catch (e) {
      print('Error joining call: $e');
      Navigator.pop(context);
    }
  }

  Future<void> _startCall() async {
    try {
      print("starting call...");
      await _ensurePermissions(); // <-- Add this line
      ChatApiService chatApiService = ChatApiService();
      final response = await chatApiService.initiateVideoCall(_chatId!);
      if (response == null || response.callToken.isEmpty) {
        print("❌ Failed to get call token. Please try again.");
        // _showErrorDialog("Failed to get call token. Please try again.");
        return;
      }

      setState(() {
        _callState = CallState.ringing;
      });
      _startRingingAnimations();

      final url = 'ws://217.77.4.167:7880';
      print("Call token: ${response.callToken}");
      await _initializeLiveKitRoom(response.callToken, url);

      // // Simulate connection delay
      // await Future.delayed(const Duration(seconds: 2));

      // if (mounted) {
      //   setState(() {
      //     _callState = CallState.connected;
      //   });
      // }
    } catch (e) {
      print('Error starting call: $e');
      Navigator.pop(context);
    }
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
      final cameras = await availableCameras();
      print("Available cameras: $cameras");
      // Create fresh room instance
      final roomOptions = RoomOptions(
        adaptiveStream: true,
        dynacast: true,
        // ... your room options
      );
      _room = Room(roomOptions: roomOptions);

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
      await _room!.localParticipant?.setCameraEnabled(_isVideoOn);
    } catch (e) {
      print("❌ Error setting up LiveKit room: $e");
      // _showErrorDialog("Failed to setup call room: $e");
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

  /// ✅ Setup LiveKit room event listeners
  void _setupRoomListeners() {
    _listener = _room!.createListener();

    _listener!
      ..on<RoomConnectedEvent>((event) {
        print('✅ Connected to LiveKit room');

        // Capture room information when connected
        // _captureRoomInfo();

        // Check if there are already participants in the room (for joiners)
        if (_room != null && _room!.remoteParticipants.isNotEmpty) {
          print('👥 Found existing participants, joining active call');
          if (mounted) {
            setState(() {
              _callState = CallState.connected;
              _remoteParticipants.addAll(_room!.remoteParticipants.values);
            });
            _stopAllAnimations();
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
        // _captureDisconnectionInfo(event.reason?.toString() ?? 'Unknown');

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
          // _stopAllAnimations();
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
            // Update state based on actual LiveKit participant state
            _isMuted = !_room!.localParticipant!.isMicrophoneEnabled();
            _isVideoOn = _room!.localParticipant!.isCameraEnabled();
          });
        }
      })
      ..on<TrackUnmutedEvent>((event) {
        print('🔊 Track unmuted: ${event.publication.kind}');
        if (mounted && event.participant is LocalParticipant) {
          setState(() {
            // Update state based on actual LiveKit participant state
            _isMuted = !_room!.localParticipant!.isMicrophoneEnabled();
            _isVideoOn = _room!.localParticipant!.isCameraEnabled();
          });
        }
      });
  }

  /// ✅ Stop all animations when connected
  void _stopAllAnimations() {
    _fadeController.stop();
    _fadeController.reset();
    _audioPlayer?.dispose();
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

  /// ✅ End the call and navigate back
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
      
      _stopAllAnimations();
      _timer?.cancel();

      // Capture final room state before cleanup
      if (_room != null) {
        // _captureDisconnectionInfo('User ended call');
      }

      // Use our comprehensive cleanup method
      await _ensureRoomCleanup();

      // Example: Show call summary before leaving
      // _showCallSummary();

      // Send decline notification only if this user initiated the end
      // Don't send if we're ending because we received a decline notification
      if (_chatId != null && sendDeclineNotification) {
        print("📞 Sending decline notification to other party");
        WebSocketService().sendDeclineCall(_chatId!, "video");
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

  /// ✅ Build local video track widget
  Widget _buildLocalVideoTrack(LocalParticipant participant) {
    final videoTrack = participant.videoTrackPublications.isNotEmpty
        ? participant.videoTrackPublications.first.track as VideoTrack?
        : null;

    if (videoTrack != null && !videoTrack.muted) {
      return VideoTrackRenderer(
        videoTrack,
        fit: VideoViewFit.cover,
      );
    }

    // Fallback to placeholder if no video track or muted
    return Container(
      color: Colors.black54,
      child: const Center(
        child: Icon(
          Icons.videocam_off,
          color: Colors.white,
          size: 32,
        ),
      ),
    );
  }

  /// ✅ Build remote video track widget
  Widget _buildRemoteVideoTrack(RemoteParticipant participant) {
    final videoTrack = participant.videoTrackPublications.isNotEmpty
        ? participant.videoTrackPublications.first.track as VideoTrack?
        : null;

    if (videoTrack != null && !videoTrack.muted) {
      return VideoTrackRenderer(
        videoTrack,
        fit: VideoViewFit.cover,
      );
    }

    // Fallback to placeholder if no video track or muted
    return Container(
      color: Colors.black54,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.videocam_off,
              color: Colors.white,
              size: 48,
            ),
            SizedBox(height: 8),
            Text(
              participant.name.isEmpty ? 'Remote User' : participant.name,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget view(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Stack(
            children: [
              // Video content
              _buildVideoContent(),

              // Top header
              _buildTopHeader(),

              // Bottom controls
              _buildBottomControls(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopHeader() {
    String statusText = '';
    switch (_callState) {
      case CallState.requesting:
        statusText = 'Requesting...';
        break;
      case CallState.ringing:
        statusText = 'Ringing...';
        break;
      case CallState.connected:
        statusText = _formatDuration();
        break;
    }

    String headerTitle =
        _callType == CallType.group ? _groupName : _contactName;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withOpacity(0.7),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          children: [
            // Minimize button
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Color(0xFF1C212C).withOpacity(0.8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.remove,
                color: Color(0xFFE8E7EA),
                size: 20,
              ),
            ),

            Expanded(
              child: Column(
                children: [
                  Text(
                    headerTitle,
                    style: const TextStyle(
                      color: Color(0xFFE8E7EA),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    statusText,
                    style: const TextStyle(
                      color: Color(0xFFE8E7EA),
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            // Participants count (for group calls)
            if (_participants.length > 2)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Color(0xFF1C212C).withOpacity(0.8),
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
                      "${_participants.length}",
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
      ),
    );
  }

  Widget _buildVideoContent() {
    // Determine total participants (local + remote)
    final totalParticipants =
        (_room?.localParticipant != null ? 1 : 0) + _remoteParticipants.length;
    print("PARTICIPANTS COUNT: $totalParticipants");
    print(_room?.localParticipant);
    print(_room?.remoteParticipants);
    if (totalParticipants == 0) {
      // No LiveKit connection, fall back to demo participants
      if (_participants.length == 1) {
        return _buildSingleVideoView();
      } else if (_participants.length == 2) {
        return _buildDualVideoView();
      } else {
        return _buildGroupVideoView();
      }
    } else if (totalParticipants == 1) {
      // Only local participant (self only)
      return _buildSingleVideoView();
    } else if (totalParticipants == 2) {
      // Two participants - main video with picture-in-picture
      return _buildDualVideoView();
    } else {
      // Group call (3+ participants)
      return _buildGroupVideoView();
    }
  }

  Widget _buildSingleVideoView() {
    final localParticipant = _room?.localParticipant;
    final mainParticipant = _participants.first;

    return Stack(
      children: [
        // Main video feed - show local camera if available
        Container(
          width: double.infinity,
          height: double.infinity,
          child: ClipRRect(
            child: _isVideoOn && localParticipant != null
                ? _buildLocalVideoTrack(localParticipant)
                : Image.asset(
                    mainParticipant.image,
                    fit: BoxFit.cover,
                  ).localAsset(),
          ),
        ),

        // Self preview (small window in corner) - only show if main is not self
        if (!mainParticipant.isSelf)
          Positioned(
            top: 80,
            right: 16,
            child: Container(
              width: 120,
              height: 160,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Color(0xFFE8E7EA), width: 2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: _isVideoOn && localParticipant != null
                    ? _buildLocalVideoTrack(localParticipant)
                    : Image.asset(
                        "image6.png", // Self image
                        fit: BoxFit.cover,
                      ).localAsset(),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDualVideoView() {
    // Use LiveKit participants if available, otherwise fall back to demo participants
    final hasRemoteParticipant = _remoteParticipants.isNotEmpty;
    final localParticipant = _room?.localParticipant;

    return Stack(
      children: [
        // Main video feed (remote participant or demo)
        Container(
          width: double.infinity,
          height: double.infinity,
          child: ClipRRect(
            child: hasRemoteParticipant
                ? _buildRemoteVideoTrack(_remoteParticipants.first)
                : Image.asset(
                    _participants.firstWhere((p) => !p.isSelf).image,
                    fit: BoxFit.cover,
                  ).localAsset(),
          ),
        ),

        // Picture-in-picture for self (bottom right corner)
        Positioned(
          bottom: 120, // Above the control buttons
          right: 16,
          child: Container(
            width: 120,
            height: 160,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Color(0xFF3498DB), width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 8,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: _isVideoOn && localParticipant != null
                  ? _buildLocalVideoTrack(localParticipant)
                  : _isVideoOn
                      ? Image.asset(
                          _participants.firstWhere((p) => p.isSelf).image,
                          fit: BoxFit.cover,
                        ).localAsset()
                      : Container(
                          color: Colors.black54,
                          child: const Center(
                            child: Icon(
                              Icons.videocam_off,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                        ),
            ),
          ),
        ),

        // Participant name overlay for main video
        Positioned(
          top: 80,
          left: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Color(0xFF1C212C).withOpacity(0.8),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              hasRemoteParticipant
                  ? (_remoteParticipants.first.name.isEmpty
                      ? 'Remote User'
                      : _remoteParticipants.first.name)
                  : _participants.firstWhere((p) => !p.isSelf).name,
              style: const TextStyle(
                color: Color(0xFFE8E7EA),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),

        // Self label on picture-in-picture
        Positioned(
          bottom: 125,
          right: 21,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Color(0xFF3498DB),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              "You",
              style: TextStyle(
                color: Color(0xFFE8E7EA),
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGroupVideoView() {
    // Combine LiveKit participants with demo participants for display
    List<Widget> participantWidgets = [];

    // Add local participant
    if (_room?.localParticipant != null) {
      participantWidgets.add(_buildLiveKitParticipantVideo(
          _room!.localParticipant!,
          isLocal: true));
    }

    // Add remote participants
    for (var remoteParticipant in _remoteParticipants) {
      participantWidgets.add(
          _buildLiveKitParticipantVideo(remoteParticipant, isLocal: false));
    }

    // If no LiveKit participants, fall back to demo participants
    if (participantWidgets.isEmpty) {
      for (int i = 0; i < _participants.length; i++) {
        participantWidgets.add(_buildParticipantVideo(_participants[i]));
      }
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(8, 80, 8, 120),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
        childAspectRatio: 0.75,
      ),
      itemCount: participantWidgets.length,
      itemBuilder: (context, index) {
        return participantWidgets[index];
      },
    );
  }

  /// ✅ Build LiveKit participant video widget
  Widget _buildLiveKitParticipantVideo(Participant participant,
      {required bool isLocal}) {
    final videoTrack = participant.videoTrackPublications.isNotEmpty
        ? participant.videoTrackPublications.first.track as VideoTrack?
        : null;

    final isMuted = participant.audioTrackPublications.isEmpty ||
        participant.audioTrackPublications.first.muted;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: isLocal
            ? Border.all(color: const Color(0xFF3498DB), width: 2)
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          children: [
            // Video feed
            Container(
              width: double.infinity,
              height: double.infinity,
              child: videoTrack != null &&
                      !videoTrack.muted &&
                      (isLocal ? _isVideoOn : true)
                  ? VideoTrackRenderer(
                      videoTrack,
                      fit: VideoViewFit.cover,
                    )
                  : Container(
                      color: Colors.black54,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.videocam_off,
                              color: Colors.white,
                              size: 32,
                            ),
                            SizedBox(height: 8),
                            Text(
                              isLocal
                                  ? 'You'
                                  : (participant.name.isEmpty
                                      ? 'Remote User'
                                      : participant.name),
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),

            // Participant info overlay
            Positioned(
              bottom: 8,
              left: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Color(0xFF1C212C).withOpacity(0.8),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        isLocal
                            ? 'You'
                            : (participant.name.isEmpty
                                ? 'Remote User'
                                : participant.name),
                        style: const TextStyle(
                          color: Color(0xFFE8E7EA),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (isMuted)
                      const Icon(
                        Icons.mic_off,
                        color: Colors.red,
                        size: 14,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildParticipantVideo(VideoParticipant participant) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: participant.isSelf
            ? Border.all(color: const Color(0xFF3498DB), width: 2)
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          children: [
            // Video feed or placeholder
            Container(
              width: double.infinity,
              height: double.infinity,
              child: participant.isSelf && !_isVideoOn
                  ? Container(
                      color: Colors.black54,
                      child: const Center(
                        child: Icon(
                          Icons.videocam_off,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    )
                  : Image.asset(
                      participant.image,
                      fit: BoxFit.cover,
                    ).localAsset(),
            ),

            // Participant info overlay
            Positioned(
              bottom: 8,
              left: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Color(0xFF1C212C).withOpacity(0.8),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        participant.name,
                        style: const TextStyle(
                          color: Color(0xFFE8E7EA),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (participant.isMuted)
                      const Icon(
                        Icons.mic_off,
                        color: Colors.red,
                        size: 14,
                      ),
                  ],
                ),
              ),
            ),

            // Speaking indicator for main speaker (optional)
            if (participant.name == "Fenta") // Example: highlight main speaker
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Color(0xFF1C212C).withOpacity(0.8),
                    shape: BoxShape.circle,
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      participant.image,
                      fit: BoxFit.cover,
                    ).localAsset(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withOpacity(0.8),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Camera switch button
            _buildControlButton(
              icon: Icons.flip_camera_ios,
              label: "Camera",
              isActive: false,
              onTap: () {
                HapticFeedback.lightImpact();
              },
            ),

            // Video toggle button
            _buildControlButton(
              icon: _isVideoOn ? Icons.videocam : Icons.videocam_off,
              label: "Video",
              isActive: !_isVideoOn,
              onTap: () async {
                setState(() {
                  _isVideoOn = !_isVideoOn;
                });

                // Control LiveKit camera if connected
                if (_room?.localParticipant != null) {
                  await _room!.localParticipant!.setCameraEnabled(_isVideoOn);
                }

                HapticFeedback.lightImpact();
              },
            ),

            // Mute button
            _buildControlButton(
              icon: _isMuted ? Icons.mic_off : Icons.mic,
              label: "Mute",
              isActive: _isMuted,
              onTap: () async {
                setState(() {
                  _isMuted = !_isMuted;
                });

                // Control LiveKit microphone if connected
                if (_room?.localParticipant != null) {
                  await _room!.localParticipant!
                      .setMicrophoneEnabled(!_isMuted);
                }

                HapticFeedback.lightImpact();
              },
            ),

            // End call button
            _buildControlButton(
              icon: Icons.call_end,
              label: "End Call",
              isActive: false,
              isEndCall: true,
              onTap: () {
                HapticFeedback.lightImpact();
                _endCall();
              },
            ),
          ],
        ),
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
                      : Color(0xFF1C212C).withOpacity(0.6),
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

class VideoParticipant {
  final String name;
  final String image;
  final bool isSelf;
  final bool isMuted;

  VideoParticipant({
    required this.name,
    required this.image,
    this.isSelf = false,
    this.isMuted = false,
  });
}
