import 'package:flutter/material.dart';
import 'package:flutter_app/app/models/message.dart';

/// Widget for rendering VOICE_CALL and VIDEO_CALL message types
class CallMessageWidget extends StatelessWidget {
  final Message message;
  final bool isSentByMe;
  final String? senderName;

  const CallMessageWidget({
    Key? key,
    required this.message,
    required this.isSentByMe,
    this.senderName,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isVideoCall = message.type == 'VIDEO_CALL';
    final callStatus = message.callStatus ?? 'UNKNOWN';

    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.7,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: isSentByMe
            ? const LinearGradient(
                colors: [Color(0xFF18365B), Color(0xFF163863)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : const LinearGradient(
                colors: [Color(0xFF3C434C), Color(0xFF262D35)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        borderRadius: isSentByMe
            ? const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(4),
              )
            : const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(18),
              ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Show sender name for group chats
          if (senderName != null) ...[
            Text(
              senderName!,
              style: const TextStyle(
                color: Color(0xFFFF9800),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
          ],
          
          // Call icon and info row
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Call type icon
              _buildCallIcon(isVideoCall, callStatus, isSentByMe),
              const SizedBox(width: 12),
              
              // Call status text and duration
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _getCallStatusText(callStatus, isSentByMe, isVideoCall),
                      style: TextStyle(
                        color: _getCallStatusColor(callStatus),
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (message.duration != null && message.duration! > 0) ...[
                      const SizedBox(height: 2),
                      Text(
                        _formatDuration(message.duration!),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 4),
          
          // Timestamp and read status
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message.createdAt.toIso8601String().substring(11, 16),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 12,
                ),
              ),
              if (isSentByMe) ...[
                const SizedBox(width: 4),
                if (!message.isSent)
                  Icon(
                    Icons.schedule,
                    color: Colors.white.withOpacity(0.7),
                    size: 16,
                  ),
                if (message.isSent && !message.isDelivered && !message.isRead)
                  Icon(
                    Icons.done,
                    color: Colors.white.withOpacity(0.7),
                    size: 16,
                  ),
                if (message.isRead)
                  Icon(
                    Icons.done_all,
                    color: Colors.white.withOpacity(0.7),
                    size: 16,
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// Build the call icon based on type and status
  Widget _buildCallIcon(bool isVideoCall, String callStatus, bool isSentByMe) {
    IconData iconData;
    Color iconColor;

    // Determine icon based on call type and direction
    if (isVideoCall) {
      iconData = Icons.videocam;
    } else {
      iconData = Icons.phone;
    }

    // Determine color and icon variation based on status
    switch (callStatus) {
      case 'MISSED':
        iconData = isVideoCall ? Icons.videocam_off : Icons.phone_missed;
        iconColor = const Color(0xFFFF5252); // Red for missed
        break;
      case 'DECLINED':
        iconData = isVideoCall ? Icons.videocam_off : Icons.phone_disabled;
        iconColor = const Color(0xFFFF5252); // Red for declined
        break;
      case 'FAILED':
        iconData = isVideoCall ? Icons.videocam_off : Icons.phone_disabled;
        iconColor = const Color(0xFFFF9800); // Orange for failed
        break;
      case 'ONGOING':
      case 'ENDED':
        // Determine incoming or outgoing
        if (isSentByMe) {
          iconData = isVideoCall ? Icons.videocam : Icons.call_made;
          iconColor = const Color(0xFF4CAF50); // Green for outgoing
        } else {
          iconData = isVideoCall ? Icons.videocam : Icons.call_received;
          iconColor = const Color(0xFF4CAF50); // Green for incoming
        }
        break;
      case 'INITIALIZED':
      default:
        iconData = isVideoCall ? Icons.videocam : Icons.phone;
        iconColor = Colors.white.withOpacity(0.9);
        break;
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: iconColor.withOpacity(0.2),
        shape: BoxShape.circle,
      ),
      child: Icon(
        iconData,
        color: iconColor,
        size: 24,
      ),
    );
  }

  /// Get the status text based on call status and direction
  String _getCallStatusText(String callStatus, bool isSentByMe, bool isVideoCall) {
    final callType = isVideoCall ? 'Video call' : 'Voice call';
    
    switch (callStatus) {
      case 'MISSED':
        return isSentByMe ? 'Cancelled $callType' : 'Missed $callType';
      case 'DECLINED':
        return isSentByMe ? '$callType declined' : 'Declined $callType';
      case 'FAILED':
        return '$callType failed';
      case 'ONGOING':
        return '$callType in progress';
      case 'ENDED':
        return isSentByMe ? 'Outgoing $callType' : 'Incoming $callType';
      case 'INITIALIZED':
        return '$callType started';
      default:
        return callType;
    }
  }

  /// Get color based on call status
  Color _getCallStatusColor(String callStatus) {
    switch (callStatus) {
      case 'MISSED':
      case 'DECLINED':
        return const Color(0xFFFF5252); // Red
      case 'FAILED':
        return const Color(0xFFFF9800); // Orange
      case 'ONGOING':
      case 'ENDED':
        return Colors.white;
      case 'INITIALIZED':
      default:
        return Colors.white.withOpacity(0.9);
    }
  }

  /// Format duration in seconds to MM:SS or HH:MM:SS
  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
  }
}
