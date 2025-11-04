import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/app/networking/chat_api_service.dart';
import 'package:flutter_app/app/services/chat_service.dart';
import 'package:flutter_app/app/services/livekit_service.dart';
import 'package:flutter_app/app/models/livekit_events.dart';
import 'package:nylo_framework/nylo_framework.dart';
import 'dart:async';
import 'package:audioplayers/audioplayers.dart';

// ✅ Call states for tracking call progress
enum CallState { requesting, ringing, connected }

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
  // LiveKitService instance
  final LiveKitService _liveKitService = LiveKitService();
  
  CallState _callState = CallState.requesting;
  bool _isMuted = false;
  bool _isSpeaker = false;
  bool _isVideoOn = false;
  int _callDuration = 0;
  AudioPlayer? _audioPlayer;
  
  CallType _callType = CallType.single;
  bool _isEndingCall = false;
  
  // Call data
  String _contactName = "Layla B";
  String? _contactImage;
  String defaultImage = "image2.png";
  int? _chatId;
  int? _callerId;
  bool _isJoining = false;
  String _groupName = "";
  String _groupImage = "image9.png";

  List<CallParticipant> _participants = [];

  // Event subscriptions from LiveKitService
  StreamSubscription<ConnectionStateEvent>? _connectionSubscription;
  StreamSubscription<ParticipantChangeEvent>? _participantSubscription;
  Timer? _durationUpdateTimer;

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

        // Setup LiveKitService event listeners
        _setupLiveKitListeners();

        // Then extract call data and potentially start the call
        _extractCallData();
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

  /// Setup LiveKitService event listeners
  void _setupLiveKitListeners() {
    // Listen to connection events
    _connectionSubscription = _liveKitService.connectionEvents.listen((event) {
      if (!mounted) return;

      switch (event.type) {
        case ConnectionStateType.connected:
          print('✅ Connected to LiveKit room');
          // Check if there are already participants
          if (_liveKitService.remoteParticipants.isNotEmpty) {
            print('👥 Found existing participants, joining active call');
            setState(() {
              _callState = CallState.connected;
            });
            _syncParticipants();
            _stopAllAnimations();
            _stopRingtone();
          } else {
            print('📞 Room connected, waiting for other participants...');
            setState(() {
              _callState = CallState.ringing;
            });
            _startRingingAnimations();
          }
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
          setState(() {
            _callState = CallState.connected;
          });
          _syncParticipants();
          _stopAllAnimations();
          _stopRingtone();
          break;

        case ParticipantChangeType.disconnected:
          print('👤 Participant disconnected: ${event.participant.name}');
          _syncParticipants();
          
          // If no remote participants, end the call
          if (_liveKitService.remoteParticipants.isEmpty && _callState == CallState.connected) {
            _endCall();
          }
          break;
      }
    });

    // Update call duration periodically
    _durationUpdateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _liveKitService.isConnected) {
        setState(() {
          _callDuration = _liveKitService.callDuration;
          _isMuted = !_liveKitService.isMicrophoneEnabled;
        });
      }
    });
  }

  void _extractCallData() async {
    final navigationData = data();
    print(navigationData);

    if (navigationData != null) {
      _isJoining = navigationData['isJoining'] ??
            false; // Check if joining incoming call
        final bool initiateCall = navigationData['initiateCall'] ?? false;
      _chatId = navigationData['chatId'];

      if (navigationData['isGroup'] == true) {
        _callType = CallType.group;
        
        

        
        final groupInfo = await ChatService().getChatDetails(_chatId!);
        if(groupInfo != null){
          // _groupImage = groupInfo.avatar ?? "image9.png";
          _groupName = groupInfo.name;
      }
        
        _groupImage = navigationData['avatar'] ?? _groupImage;
        
        print("_groupName: $_groupName, _groupImage: $_groupImage");
        _callerId =
            navigationData['callerId']; // Get caller ID for incoming calls
          print("Navigation Data: $navigationData");
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
        image: user['avatar'] ?? "image6.png",
        isSelf: true,
      ));
    }

    // Add all remote participants from LiveKitService
    for (var remoteParticipant in _liveKitService.remoteParticipants) {
      newParticipants.add(CallParticipant(
        name: remoteParticipant.name,
        image: "default_avatar.png",
        isSelf: false,
      ));
    }

    if (mounted) {
      setState(() {
        _participants = newParticipants;
      });
    }

    print("👥 Synced participants: ${_participants.length} total");
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

      await _liveKitService.connect(        
        token: response.callToken,
        callType: _callType,
        chatId: _chatId!,
        enableAudio: true,
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
      print("🔄 Joining call for chat ID: $_chatId from caller: $_callerId");

      ChatApiService chatApiService = ChatApiService();
      final response = await chatApiService.joinVoiceCall(_chatId!);

      if (response == null || response.callToken.isEmpty) {
        print("❌ Failed to get call token for joining. Please try again.");
        _showErrorDialog("Failed to join call. Please try again.");
        return;
      }

      await _liveKitService.connect(        
        token: response.callToken,
        callType: _callType,
        chatId: _chatId!,
        enableAudio: true,
      );
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





  /// ✅ Format call duration for display
  String _formatDuration(int seconds) {
    final minutes = (seconds / 60).floor();
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  /// ✅ Mute/unmute microphone
  Future<void> _toggleMute() async {
    await _liveKitService.toggleMicrophone();
    if (mounted) {
      setState(() {
        _isMuted = !_liveKitService.isMicrophoneEnabled;
      });
    }
  }

  /// ✅ End the call and navigate back
  Future<void> _endCall() async {
    // Guard: Prevent duplicate end call processing
    if (_isEndingCall) {
      print("⚠️ _endCall already in progress, skipping duplicate call");
      return;
    }
    
    _isEndingCall = true;
    print("📞 Starting call end process...");
    
    try {
      _stopAllAnimations();

      // Disconnect via LiveKitService
      await _liveKitService.disconnect(reason: 'User ended call');
      
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
  @override
  void dispose() {
    print("🧹 Disposing voice call page...");
    
    // Set ending flag to prevent further processing
    _isEndingCall = true;
    
    // Cancel LiveKitService event subscriptions
    _connectionSubscription?.cancel();
    _participantSubscription?.cancel();
    _durationUpdateTimer?.cancel();
    
    // Cleanup animations and audio
    _stopAllAnimations();
    _audioPlayer?.dispose();
    
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
      // Show group name and image during ringing state
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Group name
          Text(
            _groupName,
            style: const TextStyle(
              color: Color(0xFFE8E7EA),
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 8),

          // Call status
          Text(
            _getCallStatusText(),
            style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 14,
            ),
          ),

          const SizedBox(height: 60),

          // Group image with pulsating animation
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
                    child: Image.network(
                      _groupImage,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 20),

          // Participant count
          if (_participants.isNotEmpty)
            Text(
              "${_participants.length} ${_participants.length == 1 ? 'participant' : 'participants'}",
              style: const TextStyle(
                color: Color(0xFFE8E7EA),
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),

          const SizedBox(height: 8),

          AnimatedBuilder(
            animation: _fadeAnimation,
            builder: (context, child) {
              return Opacity(
                opacity: _fadeAnimation.value,
                child: Text(
                  _isJoining ? "Joining..." : "Ringing...",
                  style: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 16,
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 40),

          // Show participant avatars if available
          if (_participants.isNotEmpty && _participants.length <= 4)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: _participants.take(4).map((participant) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: _buildSmallAvatar(
                    participant.image,
                    participant.name,
                    isSelf: participant.isSelf,
                  ),
                );
              }).toList(),
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
