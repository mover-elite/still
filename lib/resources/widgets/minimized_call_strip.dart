import 'package:flutter/material.dart';
import 'package:flutter_app/app/services/livekit_service.dart';
import 'dart:async';

/// A minimized call strip widget that displays at the top of the app
/// Shows caller name and call duration
/// Tapping on it opens the full voice call page
class MinimizedCallStrip extends StatefulWidget {
  final String callerName;
  final VoidCallback onTap;
  final VoidCallback? onClose;

  const MinimizedCallStrip({
    Key? key,
    required this.callerName,
    required this.onTap,
    this.onClose,
  }) : super(key: key);

  @override
  State<MinimizedCallStrip> createState() => _MinimizedCallStripState();
}

class _MinimizedCallStripState extends State<MinimizedCallStrip> {
  final LiveKitService _liveKitService = LiveKitService();
  StreamSubscription? _durationSubscription;
  String _formattedDuration = '00:00';

  @override
  void initState() {
    super.initState();
    _updateDuration();
    
    // Update duration every second
    _durationSubscription = Stream.periodic(const Duration(seconds: 1)).listen((_) {
      if (mounted) {
        _updateDuration();
      }
    });
  }

  void _updateDuration() {
    if (mounted) {
      setState(() {
        _formattedDuration = _liveKitService.formatDuration();
      });
    }
  }

  @override
  void dispose() {
    _durationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      color: const Color(0xFF1A1D26),
      child: InkWell(
        onTap: widget.onTap,
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF1E2128),
                const Color(0xFF2A2D36),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withOpacity(0.1),
                width: 1,
              ),
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                // Call icon with pulse animation
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF4CAF50).withOpacity(0.2),
                    border: Border.all(
                      color: const Color(0xFF4CAF50),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.phone,
                    color: Color(0xFF4CAF50),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                
                // Caller info
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.callerName,
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
                              shape: BoxShape.circle,
                              color: Color(0xFF4CAF50),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _formattedDuration,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                // Tap to expand hint
                Text(
                  'Tap to return',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                
                if (widget.onClose != null) ...[
                  const SizedBox(width: 12),
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      color: Colors.white.withOpacity(0.7),
                      size: 20,
                    ),
                    onPressed: widget.onClose,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
