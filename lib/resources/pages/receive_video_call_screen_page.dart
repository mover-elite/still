import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_app/app/networking/websocket_service.dart';
import 'package:flutter_app/app/services/callkit_service.dart';
import 'package:flutter_app/app/services/chat_service.dart';
import 'package:flutter_app/app/services/livekit_service.dart';
import 'package:nylo_framework/nylo_framework.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

class ReceiveVideoCallScreenPage extends NyStatefulWidget {
  static RouteView path =
      ("/receive-video-call-screen", (_) => ReceiveVideoCallScreenPage());

  ReceiveVideoCallScreenPage({super.key})
      : super(child: () => _ReceiveVideoCallScreenPageState());
}

class _ReceiveVideoCallScreenPageState
    extends NyPage<ReceiveVideoCallScreenPage> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _dotsController;
  late AnimationController _rotateController;
  late AnimationController _bounceController;
  late AnimationController _glowController;
  late AnimationController _scaleController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _dotsAnimation;
  late Animation<double> _rotateAnimation;
  late Animation<double> _bounceAnimation;
  late Animation<double> _glowAnimation;
  late Animation<double> _scaleAnimation;
  bool _isRingtonePlaying = false;
  StreamSubscription<Map<String, dynamic>>? _notificationSubscription;
  StreamSubscription<CallStatus>? _callStatusSubscription;
  String _callerName = 'Unknown'; // Store caller name

  @override
  get init => () {
        // Extract caller name from navigation data
        final navigationData = data();
        if (navigationData != null) {
          if(navigationData['isGroup'] == true){
            _callerName = navigationData['name'] ?? "Unknown";
          } else{
            _callerName = navigationData['partner']['username'] ?? 'Unknown';
          }

          
        }
        
        // Initialize animation controllers
        _pulseController = AnimationController(
          duration: const Duration(seconds: 2),
          vsync: this,
        );

        _fadeController = AnimationController(
          duration: const Duration(milliseconds: 800),
          vsync: this,
        );

        _slideController = AnimationController(
          duration: const Duration(milliseconds: 600),
          vsync: this,
        );

        _dotsController = AnimationController(
          duration: const Duration(milliseconds: 1500),
          vsync: this,
        );

        _rotateController = AnimationController(
          duration: const Duration(seconds: 3),
          vsync: this,
        );

        _bounceController = AnimationController(
          duration: const Duration(milliseconds: 1200),
          vsync: this,
        );

        _glowController = AnimationController(
          duration: const Duration(seconds: 2),
          vsync: this,
        );

        _scaleController = AnimationController(
          duration: const Duration(milliseconds: 800),
          vsync: this,
        );

        // Create animations
        _pulseAnimation = Tween<double>(
          begin: 0.8,
          end: 1.2,
        ).animate(CurvedAnimation(
          parent: _pulseController,
          curve: Curves.easeInOut,
        ));

        _fadeAnimation = Tween<double>(
          begin: 0.0,
          end: 1.0,
        ).animate(CurvedAnimation(
          parent: _fadeController,
          curve: Curves.easeOut,
        ));

        _slideAnimation = Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: _slideController,
          curve: Curves.elasticOut,
        ));

        _dotsAnimation = Tween<double>(
          begin: 0.0,
          end: 1.0,
        ).animate(CurvedAnimation(
          parent: _dotsController,
          curve: Curves.easeInOut,
        ));

        _rotateAnimation = Tween<double>(
          begin: 0.0,
          end: 2 * 3.14159,
        ).animate(CurvedAnimation(
          parent: _rotateController,
          curve: Curves.linear,
        ));

        _bounceAnimation = Tween<double>(
          begin: 0.0,
          end: 1.0,
        ).animate(CurvedAnimation(
          parent: _bounceController,
          curve: Curves.elasticOut,
        ));

        _glowAnimation = Tween<double>(
          begin: 0.3,
          end: 1.0,
        ).animate(CurvedAnimation(
          parent: _glowController,
          curve: Curves.easeInOut,
        ));

        _scaleAnimation = Tween<double>(
          begin: 0.0,
          end: 1.0,
        ).animate(CurvedAnimation(
          parent: _scaleController,
          curve: Curves.bounceOut,
        ));

        // Start animations
        _pulseController.repeat(reverse: true);
        _fadeController.forward();
        _slideController.forward();
        _dotsController.repeat();
        _rotateController.repeat();
        _bounceController.repeat(reverse: true);
        _glowController.repeat(reverse: true);
        _scaleController.forward();
        _playRingtone();
        
        // Listen for call ended/declined notifications
        _notificationSubscription = WebSocketService().notificationStream.listen((notification) {
          final action = notification['action'];
          print("Received notification in receive call screen: $notification");
          if (action == 'call:declined' || action == 'call:ended') {
            _handleCallEndedNotification(notification);
          }
        });
        
        // ✅ Subscribe to call status changes
        // final liveKitService = LiveKitService();
        // _callStatusSubscription = liveKitService.callStatusStream.listen((status) {
        //   if (!mounted) return;
          
        //   // Close the screen if call status changes while page is mounted
        //   if (status == CallStatus.ended) {
        //     print('📞 Call status changed to $status - closing receive video call screen');
            
        //     // Stop ringtone
        //     if (_isRingtonePlaying) {
        //       FlutterRingtonePlayer().stop();
        //       _isRingtonePlaying = false;
        //     }
            
        //     // Clear call tracking
        //     try {
        //       final navigationData = data();
        //       if (navigationData != null) {
        //         final chatId = navigationData['chatId'];
        //         final callId = navigationData['callId'];
        //         ChatService().clearIncomingCall(chatId, callId);
        //       }
        //     } catch (e) {
        //       print('Could not clear call tracking: $e');
        //     }
            
        //     // Close the screen
        //     if (mounted && Navigator.canPop(context)) {
        //       Navigator.pop(context);
        //     }
        //   }
        // });
      };

  @override
  void dispose() {
    _pulseController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    _dotsController.dispose();
    _rotateController.dispose();
    _bounceController.dispose();
    _glowController.dispose();
    _scaleController.dispose();
    
    // Cancel subscriptions
    _notificationSubscription?.cancel();
    _callStatusSubscription?.cancel();
    
    // Stop ringtone if playing
    if (_isRingtonePlaying) {
      FlutterRingtonePlayer().stop();
      _isRingtonePlaying = false;
    }
    
    // Clear call tracking when screen is disposed (safety net)
    try {
      final navigationData = data();
      if (navigationData != null) {
        final chatId = navigationData['chatId'];
        final callId = navigationData['callId'];
        ChatService().clearIncomingCall(chatId, callId);
      }
    } catch (e) {
      print('Could not clear call tracking in dispose: $e');
    }
    
    super.dispose();
  }

  void handleDeclineCall() {
    // Stop ringtone
    if (_isRingtonePlaying) {
      FlutterRingtonePlayer().stop();
      _isRingtonePlaying = false;
    }
    
    final navigationData = data();
    final chatID = navigationData['chatId'];
    final callerId = navigationData['callerId'];
    final callId = navigationData['callId'];

    // Clear call tracking when declining
    ChatService().clearIncomingCall(chatID, callId);

    WebSocketService().sendDeclineCall(chatID, "video", callId);
    Navigator.pop(context);
  }

  void _handleCallEndedNotification(Map<String, dynamic> notification) {
    try {
      final notificationChatId = notification['chatId'];
      final notificationType = notification['type'] ?? 'video';
      
      // Get current call data
      final navigationData = data();
      if (navigationData == null) return;
      
      final currentChatId = navigationData['chatId'];
      final isGroup = navigationData['isGroup'] ?? false;
      
      // Only handle if it's for this call and it's a single (non-group) call
      print("notification type for call video ended handling: $notificationType");
      if (notificationChatId == currentChatId && 
          !isGroup) {
        print('📞 Call ended/declined notification received for single video call - closing screen');
        
        // Stop ringtone
        if (_isRingtonePlaying) {
          FlutterRingtonePlayer().stop();
          _isRingtonePlaying = false;
        }
        
        // Clear call tracking
        final callerId = navigationData['callerId'];
        final callId = navigationData['callId'];
        ChatService().clearIncomingCall(currentChatId, callId);
        
        // Close the screen
        if (mounted && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      }
    } catch (e) {
      print('❌ Error handling call ended notification: $e');
    }
  }

  void handleAcceptCall() async {
    // Stop ringtone
    if (_isRingtonePlaying) {
      FlutterRingtonePlayer().stop();
      _isRingtonePlaying = false;
    }
    
    final navigationData = data();
    
    // Clear call tracking when accepting
    final chatId = navigationData['chatId'];
    final callerId = navigationData['callerId'];
    final callId = navigationData['callId'];
    ChatService().clearIncomingCall(chatId, callId);
    CallKitService().setCallStarted(callId);
    // Navigate to video call page with proper data
    Navigator.pop(context); // Close the incoming call screen first
    await routeTo(
      "/video-call",
      data: navigationData,
    );
  }

  Future<void> _playRingtone() async {
    try {
      await FlutterRingtonePlayer().play(
        android: AndroidSounds.ringtone,
        ios: IosSounds.glass,
        looping: true,
        volume: 1.0,
        asAlarm: false,
      );
      _isRingtonePlaying = true;
      print('🔔 Ringtone started with looping enabled');
    } catch (e) {
      print('❌ Error playing ringtone: $e');
    }
  }

  Widget _buildAnimatedDots() {
    return AnimatedBuilder(
      animation: _dotsAnimation,
      builder: (context, child) {
        final dots = <Widget>[];
        for (int i = 0; i < 3; i++) {
          final delay = i * 0.2;
          final opacity = (_dotsAnimation.value + delay) % 1.0;
          dots.add(
            AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: opacity > 0.5 ? 1.0 : 0.3,
              child: Text(
                '.',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: dots,
        );
      },
    );
  }

  @override
  Widget view(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF2A3036),
              Color(0xFF020B1D),
            ],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Stack(
              children: [
                // Same background as voice call
                Container(
                  width: double.infinity,
                  height: double.infinity,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xFF2A3036),
                        Color(0xFF020B1D),
                      ],
                    ),
                  ),
                ),

                // UI overlay
                Column(
                  children: [
                    // Top section with Stillur and Demi3d - moved to very top
                    Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Column(
                        children: [
                          // Animated app service indicator
                          TweenAnimationBuilder<double>(
                            tween: Tween<double>(begin: 0, end: 1),
                            duration: const Duration(milliseconds: 800),
                            curve: Curves.easeOut,
                            builder: (context, value, child) {
                              return Transform.translate(
                                offset: Offset(0, 20 * (1 - value)),
                                child: Opacity(
                                  opacity: value,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 8),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Stillur logo with rotation
                                        AnimatedBuilder(
                                          animation: _rotateAnimation,
                                          builder: (context, child) {
                                            return Transform.rotate(
                                              angle: _rotateAnimation.value,
                                              child: Container(
                                                width: 20,
                                                height: 20,
                                                margin: const EdgeInsets.only(
                                                    right: 8),
                                                child: Image.asset(
                                                  'stillur_without_bg.png',
                                                  fit: BoxFit.contain,
                                                ).localAsset(),
                                              ),
                                            );
                                          },
                                        ),
                                        Text(
                                          'Stillur Video',
                                          style: TextStyle(
                                            color:
                                                Colors.white.withOpacity(0.9),
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        _buildAnimatedDots(),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),

                          const SizedBox(height: 32),

                          // Animated caller name with updated styling
                          TweenAnimationBuilder<double>(
                            tween: Tween<double>(begin: 0, end: 1),
                            duration: const Duration(milliseconds: 1000),
                            curve: Curves.easeOut,
                            builder: (context, value, child) {
                              return Transform.translate(
                                offset: Offset(0, 30 * (1 - value)),
                                child: Opacity(
                                  opacity: value,
                                  child: AnimatedBuilder(
                                    animation: _glowAnimation,
                                    builder: (context, child) {
                                      return Text(
                                        _callerName,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 24,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.24, // 1% of 24px
                                          height: 1.0, // 100% line height
                                          shadows: [
                                            Shadow(
                                              color: Colors.blue.withOpacity(
                                                  _glowAnimation.value * 0.6),
                                              blurRadius:
                                                  15 * _glowAnimation.value,
                                              offset: const Offset(0, 2),
                                            ),
                                            Shadow(
                                              color:
                                                  Colors.black.withOpacity(0.5),
                                              blurRadius: 10,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        textAlign: TextAlign.center,
                                      );
                                    },
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),

                    // Spacer to push other content down
                    const Spacer(),

                    // Middle section - animated action buttons
                    SlideTransition(
                      position: _slideAnimation,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Animated Message button
                          _buildAnimatedActionButton(
                            iconPath: 'message.png',
                            label: 'Message',
                            delay: 200,
                            onTap: () {
                              // Handle message action
                            },
                          ),

                          // Horizontal spacing of 182px
                          const SizedBox(width: 182),

                          // Animated Remind Me button
                          _buildAnimatedActionButton(
                            iconPath: 'remind.png',
                            label: 'Remind Me',
                            delay: 300,
                            onTap: () {
                              // Handle remind me action
                            },
                          ),
                        ],
                      ),
                    ),

                    // Vertical spacing of 24px
                    const SizedBox(height: 24),

                    // Bottom section - animated main action buttons with labels
                    Padding(
                      padding: const EdgeInsets.only(bottom: 40),
                      child: SlideTransition(
                        position: _slideAnimation,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Decline button with label
                            Column(
                              children: [
                                _buildMainActionButton(
                                  color: Colors.red,
                                  iconPath: 'reject.png',
                                  delay: 400,
                                  onTap: () {
                                    handleDeclineCall();
                                  },
                                ),
                                const SizedBox(height: 12),
                                TweenAnimationBuilder<double>(
                                  tween: Tween<double>(begin: 0, end: 1),
                                  duration: const Duration(milliseconds: 1200),
                                  curve: Curves.easeOut,
                                  builder: (context, value, child) {
                                    return Opacity(
                                      opacity: value,
                                      child: Text(
                                        'Decline',
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.8),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w400,
                                          letterSpacing: 0.14, // 1% of 14px
                                          height: 1.0, // 100% line height
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),

                            // Horizontal spacing of 182px
                            const SizedBox(width: 182),

                            // Accept button with label
                            Column(
                              children: [
                                _buildMainActionButton(
                                  color: Colors.green,
                                  iconPath: 'accept.png',
                                  delay: 500,
                                  onTap: () {
                                    handleAcceptCall();
                                  },
                                ),
                                const SizedBox(height: 12),
                                TweenAnimationBuilder<double>(
                                  tween: Tween<double>(begin: 0, end: 1),
                                  duration: const Duration(milliseconds: 1200),
                                  curve: Curves.easeOut,
                                  builder: (context, value, child) {
                                    return Opacity(
                                      opacity: value,
                                      child: Text(
                                        'Accept',
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.8),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w400,
                                          letterSpacing: 0.14, // 1% of 14px
                                          height: 1.0, // 100% line height
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedActionButton({
    required String iconPath,
    required String label,
    required int delay,
    required VoidCallback onTap,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 600 + delay),
      curve: Curves.elasticOut,
      builder: (context, value, child) {
        return AnimatedBuilder(
          animation: _bounceAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: value * (0.95 + _bounceAnimation.value * 0.1),
              child: GestureDetector(
                onTap: onTap,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.grey[700],
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 15,
                              spreadRadius: 2,
                            ),
                            BoxShadow(
                              color: Colors.blue
                                  .withOpacity(_bounceAnimation.value * 0.2),
                              blurRadius: 10 * _bounceAnimation.value,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: Image.asset(
                          iconPath,
                          width: 24,
                          height: 24,
                          fit: BoxFit.contain,
                        ).localAsset(),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        label,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 0.14, // 1% of 14px
                          height: 1.0, // 100% line height
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMainActionButton({
    required Color color,
    required String iconPath,
    required int delay,
    required VoidCallback onTap,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 800 + delay),
      curve: Curves.elasticOut,
      builder: (context, value, child) {
        return AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: value * _pulseAnimation.value,
              child: GestureDetector(
                onTapDown: (_) {
                  // Add tap down animation effect here if needed
                },
                onTap: onTap,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                    boxShadow: [
                      BoxShadow(
                        color: color.withOpacity(0.4 * _pulseAnimation.value),
                        blurRadius: 20 * _pulseAnimation.value,
                        spreadRadius: 3 * _pulseAnimation.value,
                      ),
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 15,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Image.asset(
                    iconPath,
                    width: 32,
                    height: 32,
                    fit: BoxFit.contain,
                  ).localAsset(),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
