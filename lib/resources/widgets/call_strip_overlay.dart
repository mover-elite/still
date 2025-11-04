import 'package:flutter/material.dart';
import 'package:flutter_app/app/services/call_strip_manager.dart';
import 'package:flutter_app/resources/widgets/minimized_call_strip.dart';
import 'package:nylo_framework/nylo_framework.dart';

/// Wrapper widget that displays the minimized call strip over the app content
class CallStripOverlay extends StatefulWidget {
  final Widget child;

  const CallStripOverlay({
    Key? key,
    required this.child,
  }) : super(key: key);

  @override
  State<CallStripOverlay> createState() => _CallStripOverlayState();
}

class _CallStripOverlayState extends State<CallStripOverlay> {
  final CallStripManager _stripManager = CallStripManager();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CallStripState?>(
      valueListenable: _stripManager.stateNotifier,
      builder: (context, stripState, child) {
        return Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: [
              // Main app content
              widget.child,
              
              // Minimized call strip overlay
              if (stripState != null)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: MinimizedCallStrip(
                    callerName: stripState.callerName,
                    onTap: () {
                      // Navigate back to voice call page
                      _stripManager.hideStrip();
                      routeTo(
                        '/voice-call',
                        data: {
                          'chatId': stripState.chatId,
                          'contactName': stripState.callerName,
                        },
                      );
                    },
                    onClose: () {
                      // Just hide the strip, don't end the call
                      _stripManager.hideStrip();
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
