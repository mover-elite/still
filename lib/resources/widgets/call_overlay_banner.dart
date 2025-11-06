import 'package:flutter/material.dart';
import 'package:flutter_app/app/services/call_overlay_service.dart';
import 'package:flutter_app/app/services/livekit_service.dart';
import 'package:flutter_app/app/models/livekit_events.dart';
import 'package:flutter_app/resources/pages/voice_call_page.dart';
import 'package:nylo_framework/nylo_framework.dart';

/// Widget that shows a minimized call banner at the top of the app
class CallOverlayBanner extends StatelessWidget {
  final CallOverlayState callState;

  const CallOverlayBanner({Key? key, required this.callState}) : super(key: key);

  String _getStatusText(CallStatus status) {
    switch (status) {
      case CallStatus.idle:
        return 'Voice call';
      case CallStatus.requesting:
        return 'Voice call · Requesting...';
      case CallStatus.connecting:
        return 'Voice call · Connecting...';
      case CallStatus.ringing:
        return 'Voice call · Ringing...';
      case CallStatus.connected:
        return 'Voice call · In call';
      case CallStatus.ended:
        return 'Voice call · Ended';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onTap: () {
          // Get call data from LiveKitService
          final callData = CallOverlayService().getCallDataFromLiveKit();
          
          if (callData == null) {
            print('❌ No active call data found in LiveKitService');
            return;
          }
          
          // Hide the banner and navigate back to the call page
          CallOverlayService().hideCallBanner();
          
          // Prepare navigation data from LiveKitService
          final Map<String, dynamic> navigationData = {
            'chatId': callData['chatId'],
            'isJoining': false,
            'initiateCall': false, // Don't initiate new call
            'isReturningFromMinimize': true, // Flag to indicate we're returning
            'isGroup': callData['callType'] == CallType.group,
          };
          
          // Add any additional call data from LiveKitService
          if (callData['callData'] != null) {
            navigationData.addAll(callData['callData'] as Map<String, dynamic>);
          }
          
          routeTo(VoiceCallPage.path, 
            navigationType: NavigationType.push,
            data: navigationData,
          );
        },
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFF00A884),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
            children: [
              // Mute icon
              Icon(
                callState.isMuted ? Icons.mic_off : Icons.mic,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 8),
              
              // Call info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      callState.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _getStatusText(callState.callStatus),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              // Duration (only show if connected)
              if (callState.callStatus == CallStatus.connected)
                Text(
                  callState.duration,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              
              const SizedBox(width: 8),
              
              // End call button
              GestureDetector(
                onTap: () {
                  // Get the navigator context
                  final navigatorContext = NyNavigator.instance.router.navigatorKey?.currentContext;
                  if (navigatorContext == null) return;
                  
                  // Show confirmation dialog
                  showDialog(
                    context: navigatorContext,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('End Call'),
                      content: const Text('Are you sure you want to end this call?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            CallOverlayService().hideCallBanner();
                            // The call page will handle actual disconnection
                          },
                          child: const Text(
                            'End',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.red.shade700,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.call_end,
                    color: Colors.white,
                    size: 14,
                  ),
                ),
              ),
            ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
