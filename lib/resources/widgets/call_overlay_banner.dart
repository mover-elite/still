import 'package:flutter/material.dart';
import 'package:flutter_app/app/services/call_overlay_service.dart';
import 'package:flutter_app/app/models/livekit_events.dart';
import 'package:flutter_app/resources/pages/voice_call_page.dart';
import 'package:nylo_framework/nylo_framework.dart';

/// Widget that shows a minimized call banner at the top of the app
class CallOverlayBanner extends StatelessWidget {
  final CallOverlayState callState;

  const CallOverlayBanner({Key? key, required this.callState}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // Hide the banner and navigate back to the call page
        CallOverlayService().hideCallBanner();
        routeTo(VoiceCallPage.path, 
          navigationType: NavigationType.push,
          data: {
            'chatId': callState.chatId,
            'isJoining': false,
            'isReturningFromMinimize': true, // Flag to indicate we're returning
            'isGroup': callState.callType == CallType.group,
          },
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
          child: Row(
            children: [
              // Mute icon
              Icon(
                callState.isMuted ? Icons.mic_off : Icons.mic,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 12),
              
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
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Voice call · In call',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              // Duration
              Text(
                callState.duration,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              
              const SizedBox(width: 12),
              
              // End call button
              GestureDetector(
                onTap: () {
                  // Show confirmation dialog
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('End Call'),
                      content: const Text('Are you sure you want to end this call?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
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
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade700,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.call_end,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
