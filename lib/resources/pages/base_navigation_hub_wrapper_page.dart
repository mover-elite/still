import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_app/resources/pages/base_navigation_hub.dart';
import 'package:flutter_app/app/services/call_overlay_service.dart';
import 'package:flutter_app/resources/widgets/call_overlay_banner.dart';
import 'package:nylo_framework/nylo_framework.dart';

class BaseNavigationHubWrapperPage extends NyStatefulWidget {
  static RouteView path =
      ("/base-navigation-hub-wrapper", (_) => BaseNavigationHubWrapperPage());

  BaseNavigationHubWrapperPage({super.key})
      : super(child: () => _BaseNavigationHubWrapperPageState());
}

class _BaseNavigationHubWrapperPageState
    extends NyPage<BaseNavigationHubWrapperPage> {
  @override
  get init => () {
    print("🎬 BaseNavigationHubWrapper initialized");
    print("   CallOverlayService current state: ${CallOverlayService().currentState?.name}");
  };

  @override
  Widget view(BuildContext context) {
    return Scaffold(
      extendBody:
          true, // This is crucial - allows content to extend behind bottom nav
      body: Stack(
        children: [
          // Main navigation hub
          BaseNavigationHub(),
          
          // Call overlay banner (shown when call is minimized)
          StreamBuilder<CallOverlayState?>(
            stream: CallOverlayService().overlayStream,
            builder: (context, snapshot) {
              print("🔄 StreamBuilder rebuild - hasData: ${snapshot.hasData}, data: ${snapshot.data?.name}");
              final callState = snapshot.data;
              if (callState != null) {
                print("✅ Showing banner for: ${callState.name}");
                return Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: CallOverlayBanner(callState: callState),
                );
              }
              print("❌ Not showing banner - callState is null");
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      bottomNavigationBar: _buildBlurredBottomNav(),
    );
  }

  Widget _buildBlurredBottomNav() {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: Container(
          decoration: BoxDecoration(
            color: Color(0x1C212CE5), // Your color with alpha for blur effect
          ),
          child: Container(
            height: 100, // Adjust height as needed
            child: Center(
              child: Text(
                'Custom Bottom Nav with Blur',
                style: TextStyle(color: Colors.transparent),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
