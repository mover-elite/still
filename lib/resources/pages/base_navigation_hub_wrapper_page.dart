import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_app/resources/pages/base_navigation_hub.dart';
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
  get init => () {};

  @override
  Widget view(BuildContext context) {
    return Scaffold(
      extendBody:
          true, // This is crucial - allows content to extend behind bottom nav
      body: BaseNavigationHub(),
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
