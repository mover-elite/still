import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/app/networking/chat_api_service.dart';
import 'package:flutter_app/app/services/call_handling_service.dart';
import 'package:flutter_app/app/services/livekit_service.dart';
import 'package:flutter_app/app/models/livekit_events.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:nylo_framework/nylo_framework.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';

// ✅ Call states for UI tracking
enum CallState { requesting, ringing, connected, ended }

// ✅ Participant data model
class CallParticipant {
  final String name;
  final String image;
  final bool isSelf;
  final bool isMuted;

  CallParticipant({
    required this.name,
    required this.image,
    this.isSelf = false,
    this.isMuted = false,
  });
}

class VideoCallPage extends NyStatefulWidget {
  static RouteView path = ("/video-call", (_) => VideoCallPage());

  VideoCallPage({super.key}) : super(child: () => _VideoCallPageState());
}

class _VideoCallPageState extends NyPage<VideoCallPage>
    with TickerProviderStateMixin {
  // LiveKitService instance
  final LiveKitService _liveKitService = LiveKitService();
  
  // UI state - synced with LiveKitService
  CallState _callState = CallState.requesting;
  int _callDuration = 0;
  bool _isMuted = false;
  bool _remoteParticipantMuted = false; // Track remote participant mute status for single calls
  
  CallType _callType = CallType.single;
  bool _isEndingCall = false;
  
  // Call data
  String _contactName = "Allen Walker";
  String? _contactImage;
  String defaultImage = "image2.png";
  int? _chatId;
  int? _callerId;
  String? _callId;
  bool _isJoining = false;
  String _groupName = "";
  String _groupImage = "image9.png";

  List<CallParticipant> _participants = [];

  // Event subscriptions from LiveKitService
  StreamSubscription<ConnectionStateEvent>? _connectionSubscription;
  StreamSubscription<ParticipantChangeEvent>? _participantSubscription;
  StreamSubscription<CallStatus>? _callStatusSubscription;
  Timer? _durationUpdateTimer;

  // Animation controllers
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  // Helper method to convert CallStatus to CallState
  CallState _getCallState() {
    switch (_liveKitService.callStatus) {
      case CallStatus.idle:
        return CallState.requesting;
      case CallStatus.requesting:
        return CallState.requesting;
      case CallStatus.connecting:
        return CallState.requesting;
      case CallStatus.ringing:
        return CallState.ringing;
      case CallStatus.connected:
        return CallState.connected;
      case CallStatus.ended:
        return CallState.connected;
    }
  }

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

    // Only animate once on entry, not on state changes
    _fadeController.forward();
    
    // Setup LiveKitService event listeners
    _setupLiveKitListeners();

    // Extract call data on initialization
    _extractCallData();
  };

  /// Setup LiveKitService event listeners
  void _setupLiveKitListeners() {
    // Listen to call status changes from LiveKitService
    _callStatusSubscription = _liveKitService.callStatusStream.listen((status) {
      if (!mounted) return;
      
      setState(() {
        // Sync local call state with LiveKitService
        _callState = _getCallState();
      });
      
      print('📞 Call status updated from LiveKitService: $status -> $_callState');
      
      // Handle animations based on status
      if (status == CallStatus.ringing) {
        // _startRingingAnimations();
      } else if (status == CallStatus.connected) {
        _stopAllAnimations();
      } else if (status == CallStatus.ended) {
        print("Ending call in the page due to LiveKitService status ended");
        _endCall(); 
      }
    });
    
    // Listen to connection events
    _connectionSubscription = _liveKitService.connectionEvents.listen((event) {
      if (!mounted) return;

      switch (event.type) {
        case ConnectionStateType.connected:
          print('✅ Connected to LiveKit room');
          _stopAllAnimations();
          break;
        
        case ConnectionStateType.ringing:
          print('📞 Incoming call is ringing...');
          setState(() {
            _callState = CallState.ringing;
          });
          // _startRingingAnimations();
          break;

        case ConnectionStateType.disconnected:
          print('❌ Disconnected from room: ${event.disconnectReason}');
          if (!_isEndingCall && mounted) {
            Navigator.pop(context);
          }
          break;

        case ConnectionStateType.reconnecting:
          print('🔄 Room reconnecting...');
          break;
        case ConnectionStateType.reconnected:
          print('✅ Room reconnected');
          break;
      }
    });

    // Listen to participant events
    _participantSubscription = _liveKitService.participantEvents.listen((event) {
      if (!mounted) return;

      switch (event.type) {
        case ParticipantChangeType.connected:
          print('👤 Participant connected: ${event.participant.name}');
          // ✅ Sync participants when remote participant connects
          if (_callType == CallType.group) {
            _syncParticipants();
          }
          break;

        case ParticipantChangeType.disconnected:
          print('👤 Participant disconnected: ${event.participant.name}');
          _syncParticipants();
          break;
      }
    });

    // Update call duration periodically
    _durationUpdateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _liveKitService.isConnected) {
        print("📞 Updating call duration: ${_liveKitService.callDuration}s");
        setState(() {
          _callDuration = _liveKitService.callDuration;
          // Sync mute state from LiveKitService
          _isMuted = !_liveKitService.isMicrophoneEnabled;
          
          // For single calls, track remote participant mute status
          if (_callType == CallType.single && _liveKitService.remoteParticipants.isNotEmpty) {
            _remoteParticipantMuted = !_liveKitService.remoteParticipants.first.isMicrophoneEnabled();
          }
        });
        
        // ✅ Sync participants to reflect mute status changes
        if (_callType == CallType.group) {
          _syncParticipants();
        }
      }
    });
  
  }

  /// ✅ Sync participants array with LiveKit remote participants
  void _syncParticipants() {
    if (_callType != CallType.group) {
      return; // Only sync for group calls
    }

    List<CallParticipant> newParticipants = [];

    // Add local participant (self)
    final user = Auth.data();
    
    if (user != null) {
      newParticipants.add(CallParticipant(
        name: "You",
        isSelf: true,
        image: getUserAvatar(user['id']!.toString()).toString(),
        isMuted: _isMuted, // Track self mute status
      ));
    }

    // Add all remote participants from LiveKitService
    for (var remoteParticipant in _liveKitService.remoteParticipants) {
      newParticipants.add(CallParticipant(
        name: remoteParticipant.name,
        isSelf: false,
        image: getUserAvatar(remoteParticipant.identity).toString(),
        isMuted: !remoteParticipant.isMicrophoneEnabled(), // Track remote mute status
      ));
    }

    if (mounted) {
      setState(() {
        _participants = newParticipants;
      });
    }

    print("👥 Synced participants: ${_participants.length} total");
  }

  String getUserAvatar(String userId) {
    final baseUrl = getEnv("API_BASE_URL");
    return '$baseUrl/uploads/${userId}';
  }

  void _extractCallData() async {
    final navigationData = data();
    print("Navigational data for call:");
    print(navigationData);

    if (navigationData != null) {
      _isJoining = navigationData['isJoining'] ?? false;
      final bool initiateCall = navigationData['initiateCall'] ?? false;
      
      _chatId = navigationData['chatId'];
      _callId = navigationData['callId'];

      // Normal flow for new calls
      if (navigationData['isGroup'] == true) {
        _callType = CallType.group;
        _groupName = navigationData['name'] ?? "Unknown";
        _contactName = navigationData['name'] ?? "Unknown";
        _groupImage = navigationData['avatar'] ?? _groupImage;
        _callerId = navigationData['callerId'];
        _contactImage = _groupImage;
        print("Group call: $_groupName");
        
        if (_isJoining) {
          _liveKitService.updateCallStatus(CallStatus.requesting, isJoining: true);
          setState(() {
            _callState = CallState.requesting;
          });
          _startRequestingAnimations();

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _joinCall();
            }
          });
        } else if (initiateCall) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _startCall();
            }
          });
        }
      } else {
        _callType = CallType.single;
        final partner = navigationData['partner'];
        _contactName = partner['username'] ?? _contactName;
        _contactImage = partner['avatar'];
        
        _chatId = navigationData['chatId'];
        _callerId = navigationData['callerId'];
        
        if (_isJoining) {
          _liveKitService.updateCallStatus(CallStatus.requesting, isJoining: true);
          setState(() {
            _callState = CallState.requesting;
          });
          _startRequestingAnimations();

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _joinCall();
            }
          });
        } else if (initiateCall) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _startCall();
            }
          });
        }
      }
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          routeToAuthenticatedRoute();
        }
      });
    }
  }

  void routeToAuthenticatedRoute() {
    Navigator.of(context).pushReplacementNamed('/auth');
  }

  /// ✅ Start call with proper state flow: requesting → ringing → connected
  void _startCall() async {
    if (_chatId == null) {
      print("❌ Chat ID is required to initiate a call.");
      _showErrorDialog("Chat ID is required to initiate a call.");
      return;
    }

    try {
      _liveKitService.updateCallStatus(CallStatus.requesting, isJoining: false);
      setState(() {
        _callState = CallState.requesting;
      });
      _startRequestingAnimations();

      print("🔄 Requesting call token for chat ID: $_chatId");

      ChatApiService chatApiService = ChatApiService();
      final response = await chatApiService.initiateVideoCall(_chatId!);

      if (response == null || response.callToken.isEmpty) {
        print("❌ Failed to get call token. Please try again.");
        _showErrorDialog("Failed to get call token. Please try again.");
        return;
      }

      print("✅ Call token received: ${response.callToken}");

      // _startRingingAnimations();

      // Prepare call data to store in LiveKitService
      final callData = <String, dynamic>{};
      if (_callType == CallType.group) {
        callData['groupName'] = _groupName;
        callData['avatar'] = _groupImage;
      } else {
        callData['partner'] = {
          'username': _contactName,
          'avatar': _contactImage,
        };
      }

      await _liveKitService.connect(        
        token: response.callToken,
        callType: _callType,
        chatId: _chatId!,
        enableAudio: true,
        enableVideo: true,
        callData: callData,
        callId: response.callId,
      );
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
      print("🔄 Joining call for chat ID: $_chatId from caller: $_callerId with callId: $_callId");

      ChatApiService chatApiService = ChatApiService();
      final response = await chatApiService.joinVideoCall(_chatId!, _callId!);

      if (response == null || response.callToken.isEmpty) {
        print("❌ Failed to get call token for joining. Please try again.");
        _showErrorDialog("Failed to join call. Please try again.");
        return;
      }

      // Prepare call data to store in LiveKitService
      final callData = <String, dynamic>{};
      if (_callType == CallType.group) {
        callData['groupName'] = _groupName;
        callData['avatar'] = _groupImage;
      } else {
        callData['partner'] = {
          'username': _contactName,
          'avatar': _contactImage,
        };
      }

      await _liveKitService.connect(        
        token: response.callToken,
        callType: _callType,
        chatId: _chatId!,
        enableAudio: true,
        enableVideo: true,
        callData: callData,
        callId: response.callId,
      );
    } catch (e) {
      print("❌ Error joining call: $e");
      _showErrorDialog("Failed to join call: $e");
    }
  }

  /// ✅ Start animations for requesting state
  void _startRequestingAnimations() {
    HapticFeedback.heavyImpact();
  }

  /// ✅ Stop all animations when connected
  void _stopAllAnimations() {
    // Don't reset the fade animation - just stop any repeating animations
    // _fadeController.stop();
    // _fadeController.reset();
  }

  /// ✅ Format call duration for display
  String _formatDuration(int seconds) {
    final minutes = (seconds / 60).floor();
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  Future<void> _toggleCamera() async {
    await _liveKitService.switchCamera();
  }

  /// ✅ Toggle video on/off
  Future<void> _toggleVideo() async {
    try {
      // Check if we're trying to enable the camera
      if (!_liveKitService.isCameraEnabled) {
        // Request camera permission if not already enabled
        final cameraStatus = await Permission.camera.request();
        
        if (!cameraStatus.isGranted) {
          print("❌ Camera permission denied");
          _showErrorDialog("Camera permission is required to enable video");
          return;
        }
        
        print("✅ Camera permission granted");
      }
      
      await _liveKitService.toggleCamera();
      // The control button will rebuild from the service state
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print("❌ Error toggling video: $e");
      _showErrorDialog("Failed to toggle camera: ${e.toString()}");
    }
  }

  /// ✅ Mute/unmute microphone
  Future<void> _toggleMute() async {
    await _liveKitService.toggleMicrophone();
    // The control button will rebuild from the service state
    if (mounted) {
      setState(() {});
    }
  }

  /// ✅ End the call and navigate back
  Future<void> _endCall() async {
    if (_isEndingCall) {
      print("⚠️ _endCall already in progress, skipping duplicate call");
      return;
    }
    
    _isEndingCall = true;
    print("📞 Starting call end process...");
    
    try {
      _stopAllAnimations();

      // Disconnect via LiveKitService
      await _liveKitService.disconnect(reason: 'User ended call', sendDeclineNotification: true);
      // CallHandlingService().endCall();
      // Safely pop the navigator
      print("Can pop navigator: ${Navigator.canPop(context)}");
      if (mounted && Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      print("❌ Error ending call: $e");
      if (mounted && Navigator.canPop(context)) {
        try {
          Navigator.of(context).pop();
        } catch (navError) {
          print("Could not pop navigator: $navError");
        }
      }
    }
  }

  /// ✅ Show error dialog and navigate back
  void _showErrorDialog(String message) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Call Error'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).pop();
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    print("🧹 Disposing video call page...");
    
    // Always cancel subscriptions to prevent memory leaks
    _connectionSubscription?.cancel();
    _participantSubscription?.cancel();
    _callStatusSubscription?.cancel();
    _durationUpdateTimer?.cancel();
    
    // End the call
    _isEndingCall = true;
    _liveKitService.disconnect(reason: 'Page disposed - call ended');
    
    // Cleanup animations
    _fadeController.dispose();
    super.dispose();
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
        statusText = _formatDuration(_callDuration);
        break;
      case CallState.ended:
        statusText = 'Call Ended';
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

            const SizedBox(width: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoContent() {
    final localParticipant = _liveKitService.localParticipant;
    final remoteParticipants = _liveKitService.remoteParticipants;
    final totalParticipants =
        (localParticipant != null ? 1 : 0) + remoteParticipants.length;

    print("PARTICIPANTS COUNT: $totalParticipants");
    print("Local: $localParticipant");
    print("Remote: ${remoteParticipants.length}");

    if (totalParticipants == 0) {
      // No LiveKit connection
      return _buildSingleVideoView(null);
    } else if (totalParticipants == 1) {
      // Only local participant
      return _buildSingleVideoView(localParticipant);
    } else if (totalParticipants == 2) {
      // Two participants - main video with picture-in-picture
      return _buildDualVideoView(localParticipant, remoteParticipants);
    } else {
      // Group call (3+ participants)
      return _buildGroupVideoView(localParticipant, remoteParticipants);
    }
  }

  Widget _buildSingleVideoView(LocalParticipant? localParticipant) {
    return Stack(
      children: [
        // Main video feed - show local camera fullscreen
        Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.black,
          child: localParticipant != null
              ? _buildLocalVideoTrack(localParticipant)
              : Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.videocam_off,
                        color: Colors.white,
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _contactName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildDualVideoView(LocalParticipant? localParticipant,
      List<RemoteParticipant> remoteParticipants) {
    final hasRemoteParticipant = remoteParticipants.isNotEmpty;

    return Stack(
      children: [
        // Main video feed
        Container(
          width: double.infinity,
          height: double.infinity,
          child: ClipRRect(
            child: hasRemoteParticipant
                ? _buildRemoteVideoTrack(remoteParticipants.first)
                : Container(
                    color: Colors.black54,
                    child: const Center(
                      child: Icon(
                        Icons.videocam_off,
                        color: Colors.white,
                        size: 48,
                      ),
                    ),
                  ),
          ),
        ),

        // Picture-in-picture for self
        Positioned(
          bottom: 120,
          right: 16,
          child: Container(
            width: 120,
            height: 160,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF3498DB), width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: localParticipant != null
                  ? _buildLocalVideoTrack(localParticipant)
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

        // Participant name overlay
        Positioned(
          top: 80,
          left: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF1C212C).withOpacity(0.8),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              hasRemoteParticipant
                  ? (remoteParticipants.first.name.isEmpty
                      ? 'Remote User'
                      : remoteParticipants.first.name)
                  : _contactName,
              style: const TextStyle(
                color: Color(0xFFE8E7EA),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),

        // Self label
        Positioned(
          bottom: 125,
          right: 21,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF3498DB),
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

  Widget _buildGroupVideoView(LocalParticipant? localParticipant,
      List<RemoteParticipant> remoteParticipants) {
    List<Widget> participantWidgets = [];

    // Add local participant
    if (localParticipant != null) {
      participantWidgets.add(
          _buildLiveKitParticipantVideo(localParticipant, isLocal: true));
    }

    // Add remote participants
    for (var remoteParticipant in remoteParticipants) {
      participantWidgets
          .add(_buildLiveKitParticipantVideo(remoteParticipant, isLocal: false));
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

  Widget _buildLiveKitParticipantVideo(Participant participant,
      {required bool isLocal}) {
    final videoTrack = participant.videoTrackPublications.isNotEmpty
        ? participant.videoTrackPublications.first.track as VideoTrack?
        : null;

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
            Container(
              width: double.infinity,
              height: double.infinity,
              child: videoTrack != null &&
                      !videoTrack.muted
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
                            const Icon(
                              Icons.videocam_off,
                              color: Colors.white,
                              size: 32,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              isLocal
                                  ? 'You'
                                  : (participant.name.isEmpty
                                      ? 'Remote User'
                                      : participant.name),
                              style: const TextStyle(
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Name
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C212C).withOpacity(0.8),
                      borderRadius: BorderRadius.circular(8),
                    ),
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
                  // Microphone indicator
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isLocal
                          ? (_isMuted ? const Color(0xFFE74C3C) : const Color(0xFF2ECC71))
                          : (!participant.isMicrophoneEnabled() ? const Color(0xFFE74C3C) : const Color(0xFF2ECC71)),
                      border: Border.all(color: const Color(0xFF1C212C), width: 1),
                    ),
                    child: Icon(
                      isLocal
                          ? (_isMuted ? Icons.mic_off : Icons.mic)
                          : (!participant.isMicrophoneEnabled() ? Icons.mic_off : Icons.mic),
                      color: Colors.white,
                      size: 12,
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

    return Container(
      color: Colors.black54,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.videocam_off,
              color: Colors.white,
              size: 48,
            ),
            const SizedBox(height: 8),
            Text(
              participant.name.isEmpty ? 'Remote User' : participant.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
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
              onTap: () async {
                await _toggleCamera();
                HapticFeedback.lightImpact();
              },
            ),

            // Video toggle button
            _buildControlButton(
              icon: _liveKitService.isCameraEnabled ? Icons.videocam : Icons.videocam_off,
              label: "Video",
              isActive: !_liveKitService.isCameraEnabled,
              onTap: () async {
                await _toggleVideo();
                HapticFeedback.lightImpact();
              },
            ),

            // Mute button
            _buildControlButton(
              icon: !_liveKitService.isMicrophoneEnabled ? Icons.mic_off : Icons.mic,
              label: "Mute",
              isActive: !_liveKitService.isMicrophoneEnabled,
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
                      : const Color(0xFF1C212C).withOpacity(0.6),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: const Color(0xFFE8E7EA),
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
