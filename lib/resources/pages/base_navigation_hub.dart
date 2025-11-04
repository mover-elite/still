import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:nylo_framework/nylo_framework.dart';

import '../widgets/calls_tab_widget.dart';
import '../widgets/channels_tab_widget.dart';
import '../widgets/chats_tab_widget.dart';
import '../widgets/settings_tab_widget.dart';
import '../widgets/call_overlay_banner.dart';
import '../../app/services/chat_service.dart';
import '../../app/services/call_overlay_service.dart';

class BaseNavigationHub extends NyStatefulWidget with BottomNavPageControls {
  static RouteView path = ("/base", (_) => BaseNavigationHub());

  BaseNavigationHub()
      : super(
            child: () => _BaseNavigationHubState(),
            stateName: path.stateName());

  /// State actions
  static NavigationHubStateActions stateActions =
      NavigationHubStateActions(path.stateName());
}

class _BaseNavigationHubState extends NavigationHub<BaseNavigationHub> {
  int _totalUnreadCount = 0;
  Timer? _unreadCountTimer;

  /// Layouts:
  /// - [NavigationHubLayout.bottomNav] Bottom navigation
  /// - [NavigationHubLayout.topNav] Top navigation
  /// - [NavigationHubLayout.journey] Journey navigation
  @override
  NavigationHubLayout get layout => NavigationHubLayout.bottomNav(
    selectedFontSize: 13,
    unselectedFontSize: 13,
    backgroundColor: Colors.transparent, // Keep transparent for blur effect
    selectedItemColor: Color(0xFFE8E7EA), // White for active items
    unselectedItemColor: const Color(0xFF6E6E6E), // Gray for inactive items
    type: BottomNavigationBarType.fixed, // Ensures all tabs are visible
    elevation: 0, // Remove default elevation
  );

  /// Should the state be maintained
  @override
  bool get maintainState => true;

  @override
  void initState() {
    super.initState();
    print("🎬 BaseNavigationHub initState");
    print("   CallOverlayService current state: ${CallOverlayService().currentState?.name}");
    
    // Load immediately
    _updateUnreadCount();
    
    // Set up periodic timer to check every 2 seconds
    _unreadCountTimer = Timer.periodic(Duration(seconds: 2), (timer) {
      _updateUnreadCount();
    });
  }

  @override
  void dispose() {
    _unreadCountTimer?.cancel();
    super.dispose();
  }

  void _updateUnreadCount() async {
    try {
      final chats = await ChatService().loadChatList();
      int unreadCount = 0;
      for (var chat in chats) {
        unreadCount += chat.unreadCount;
      }
      if (mounted) {
        setState(() {
          _totalUnreadCount = unreadCount;
        });
      }
    } catch (e) {
      print('❌ Error updating unread count: $e');
    }
  }

  /// Override bottomNavBuilder to add blur effect and proper spacing
  @override
  Widget bottomNavBuilder(
      BuildContext context, Widget body, Widget? bottomNavigationBar) {
    // Check if bottomNavigationBar is null
    if (bottomNavigationBar == null) {
      return Scaffold(body: body);
    }

    // Rebuild bottom nav with custom icons
    if (bottomNavigationBar is BottomNavigationBar) {
      final items = <BottomNavigationBarItem>[
        BottomNavigationBarItem(
          icon: _buildChatIcon(false, _totalUnreadCount),
          activeIcon: _buildChatIcon(true, _totalUnreadCount),
          label: "Chats",
        ),
        BottomNavigationBarItem(
          icon: Container(
            child: SvgPicture.asset(
              'public/images/channel_tab.svg',
              width: 19,
              height: 19,
              colorFilter: ColorFilter.mode(
                Color(0xff6E6E6E),
                BlendMode.srcIn,
              ),
            ),
          ),
          activeIcon: Container(
            child: SvgPicture.asset(
              'public/images/channel_tab.svg',
              width: 19,
              height: 19,
              colorFilter: ColorFilter.mode(
                Color(0xffFBFBFC),
                BlendMode.srcIn,
              ),
            ),
          ),
          label: "Channels",
        ),
        BottomNavigationBarItem(
          icon: Container(
            child: SvgPicture.asset(
              'public/images/call.svg',
              width: 19,
              height: 19,
              colorFilter: ColorFilter.mode(
                Color(0xff6E6E6E),
                BlendMode.srcIn,
              ),
            ),
          ),
          activeIcon: Container(
            child: SvgPicture.asset(
              'public/images/call.svg',
              width: 19,
              height: 19,
              colorFilter: ColorFilter.mode(
                Color(0xffFBFBFC),
                BlendMode.srcIn,
              ),
            ),
          ),
          label: "Calls",
        ),
        BottomNavigationBarItem(
          icon: Container(
            child: SvgPicture.asset(
              'public/images/setting.svg',
              width: 19,
              height: 19,
              colorFilter: ColorFilter.mode(
                Color(0xff6E6E6E),
                BlendMode.srcIn,
              ),
            ),
          ),
          activeIcon: Container(
            child: SvgPicture.asset(
              'public/images/setting.svg',
              width: 19,
              height: 19,
              colorFilter: ColorFilter.mode(
                Color(0xffFBFBFC),
                BlendMode.srcIn,
              ),
            ),
          ),
          label: "Settings",
        ),
      ];

      bottomNavigationBar = BottomNavigationBar(
        items: items,
        currentIndex: bottomNavigationBar.currentIndex,
        onTap: bottomNavigationBar.onTap,
        type: bottomNavigationBar.type,
        backgroundColor: bottomNavigationBar.backgroundColor,
        selectedItemColor: bottomNavigationBar.selectedItemColor,
        unselectedItemColor: bottomNavigationBar.unselectedItemColor,
        selectedFontSize: bottomNavigationBar.selectedFontSize,
        unselectedFontSize: bottomNavigationBar.unselectedFontSize,
        elevation: bottomNavigationBar.elevation,
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          // Main body content
          body,
          
          // Call overlay banner (shown when call is minimized)
          StreamBuilder<CallOverlayState?>(
            stream: CallOverlayService().overlayStream,
            builder: (context, snapshot) {
              print("🔄 BaseNavigationHub StreamBuilder - hasData: ${snapshot.hasData}, data: ${snapshot.data?.name}");
              final callState = snapshot.data;
              if (callState != null) {
                print("✅ Showing banner in BaseNavigationHub for: ${callState.name}");
                return Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: CallOverlayBanner(callState: callState),
                );
              }
              print("❌ Not showing banner in BaseNavigationHub - callState is null");
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      extendBody: true, // Allow body to extend behind bottom nav
      bottomNavigationBar: Container(
        height: 90,
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black
                    .withOpacity(0.4), // Semi-transparent background
                border: Border(
                  top: BorderSide(
                    color: Colors.white.withOpacity(0.1),
                    width: 0.5,
                  ),
                ),
              ),
              // Add padding to create proper spacing from top
              padding: EdgeInsets.only(top: 2, bottom: 0),
              child: bottomNavigationBar,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChatIcon(bool isActive, int unreadCount) {
    return Container(
      padding: EdgeInsets.only(top: 2),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          SvgPicture.asset(
            isActive ? 'public/images/chat_tab.svg' : 'public/images/chat_icon.svg',
            colorFilter: ColorFilter.mode(
              isActive ? Color(0xFFFBFBFC) : Color(0xff6E6E6E),
              BlendMode.srcIn,
            ),
            width: 19,
            height: 19,
          ),
          // Custom Badge
          if (unreadCount > 0)
            Positioned(
              right: -6,
              top: -6,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                constraints: BoxConstraints(
                  minWidth: 18,
                  minHeight: 18,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF57A1FF), Color(0xFF3B69C6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Center(
                  child: Text(
                    unreadCount > 99 ? '99+' : '$unreadCount',
                    style: TextStyle(
                      color: Color(0xFFFBFBFC),
                      fontSize: isActive ? 12 : 10,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Navigation pages
  _BaseNavigationHubState()
      : super(() async {
          /// * Creating Navigation Tabs
          /// [Navigation Tabs] 'dart run nylo_framework:main make:stateful_widget chats_tab,channels_tab,calls_tab,settings_tab'
          return {
            0: NavigationTab(
              title: "Chats",
              page: ChatsTab(),
              icon: Container(
                child: SvgPicture.asset(
                  'public/images/chat_icon.svg',
                  colorFilter: ColorFilter.mode(
                    Color(0xff6E6E6E),
                    BlendMode.srcIn,
                  ),
                  width: 19,
                  height: 19,
                ),
              ),
              activeIcon: Container(
                child: SvgPicture.asset(
                  'public/images/chat_tab.svg',
                  width: 19,
                  height: 19,
                  colorFilter: ColorFilter.mode(
                    Color(0xFFFBFBFC),
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
            1: NavigationTab(
              title: "Channels",
              page: ChannelsTab(),
              icon: Container(
                child: SvgPicture.asset(
                  'public/images/channel_tab.svg',
                  width: 19,
                  height: 19,
                  colorFilter: ColorFilter.mode(
                    Color(0xff6E6E6E),
                    BlendMode.srcIn,
                  ),
                ),
              ),
              activeIcon: Container(
                child: SvgPicture.asset(
                  'public/images/channel_tab.svg',
                  width: 19,
                  height: 19,
                  colorFilter: ColorFilter.mode(
                    Color(0xffFBFBFC),
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
            2: NavigationTab(
              title: "Calls",
              page: CallsTab(),
              icon: Container(
                child: SvgPicture.asset(
                  'public/images/call.svg',
                  width: 19,
                  height: 19,
                  colorFilter: ColorFilter.mode(
                    Color(0xff6E6E6E),
                    BlendMode.srcIn,
                  ),
                ),
              ),
              activeIcon: Container(
                child: SvgPicture.asset(
                  'public/images/call.svg',
                  width: 19,
                  height: 19,
                  colorFilter: ColorFilter.mode(
                    Color(0xffFBFBFC),
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
            3: NavigationTab(
              title: "Settings",
              page: SettingsTab(),
              icon: Container(
                child: SvgPicture.asset(
                  'public/images/setting.svg',
                  width: 19,
                  height: 19,
                  colorFilter: ColorFilter.mode(
                    Color(0xff6E6E6E),
                    BlendMode.srcIn,
                  ),
                ),
              ),
              activeIcon: Container(
                child: SvgPicture.asset(
                  'public/images/setting.svg',
                  width: 19,
                  height: 19,
                  colorFilter: ColorFilter.mode(
                    Color(0xffFBFBFC),
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
          };
        });

  /// Handle the tap event
  @override
  onTap(int index) {
    super.onTap(index);
    // Add any custom logic when tabs are tapped
    print('Tab tapped: $index');

    // Debug: Check if navigation is working
    switch (index) {
      case 0:
        print('Navigating to Chats tab');
        break;
      case 1:
        print('Navigating to Channels tab');
        break;
      case 2:
        print('Navigating to Calls tab');
        break;
      case 3:
        print('Navigating to Settings tab');
        break;
    }
  }
}
