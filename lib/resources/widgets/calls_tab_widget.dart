import 'package:flutter/material.dart';
import 'package:flutter_app/app/models/user_calls_model.dart';
import 'package:flutter_app/app/models/chat.dart';
import 'package:flutter_app/app/networking/chat_api_service.dart';
import 'package:flutter_app/app/services/chat_service.dart';
import 'package:flutter_app/resources/pages/video_call_page.dart';
import 'package:flutter_app/resources/pages/voice_call_page.dart';
import 'package:flutter_app/resources/pages/profile_details_page.dart';
import 'package:nylo_framework/nylo_framework.dart';

class CallsTab extends StatefulWidget {
  const CallsTab({super.key});

  @override
  createState() => _CallsTabState();
}

class _CallsTabState extends NyState<CallsTab> {
  bool _showHistory = false;
  String _currentActiveLetter = "A";

  Set<String> _selectedContacts = {};
  
  // Data loaded from API
  List<UserCallsModel> _callHistory = [];
  List<Chat> _chats = [];
  bool _isLoadingCalls = true;
  
  // Track if we should refresh on next build
  bool _shouldRefresh = true;

  @override
  get init => () {
    print("Here");
    _loadCallHistory();
    _loadChats();
  };

  @override
  void deactivate() {
    // Mark that we should refresh when this tab comes back into view
    _shouldRefresh = true;
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    // Refresh when the widget is reactivated (tab comes back into focus)
    if (_shouldRefresh) {
      _shouldRefresh = false;
      print('📞 Calls tab reactivated, refetching calls...');
      _loadCallHistory();
      _loadChats();
    }
  }

  /// Load call history from API
  Future<void> _loadCallHistory() async {
    try {
      setState(() => _isLoadingCalls = true);
      final apiService = ChatApiService();
      final calls = await apiService.getUserCalls();
      if (calls != null) {
        setState(() {
          _callHistory = calls;
          _isLoadingCalls = false;
        });
        print('✅ Loaded ${calls.length} call history items');
      } else {
        setState(() => _isLoadingCalls = false);
        print('⚠️ No calls returned from API');
      }
    } catch (e) {
      setState(() => _isLoadingCalls = false);
      print('❌ Error loading call history: $e');
    }
  }

  /// Load chats from ChatService
  Future<void> _loadChats() async {
    try {
      // Ensure ChatService is initialized
      if (!ChatService().isInitialized) {
        print('⏳ Initializing ChatService...');
        await ChatService().initialize();
      }
      
      final chatList = await ChatService().loadChatList();
      setState(() {
        _chats = chatList;
      });
      print('✅ Loaded ${chatList.length} chats for calls tab');
      print('Private chats: ${chatList.where((c) => c.type == "PRIVATE").length}');
    } catch (e) {
      print('❌ Error loading chats: $e');
    }
  }

  void _showNewCallBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildNewCallBottomSheet(),
    );
  }

  @override
  Widget view(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF0F131B),
      appBar: PreferredSize(
        preferredSize:
            const Size.fromHeight(60), // Reduced height for compact header
        child: AppBar(
          backgroundColor: Color(0xFF1C212C),
          elevation: 0,
          automaticallyImplyLeading: false,
          flexibleSpace: SafeArea(
            child: Column(
              children: [
                SizedBox(
                  height: 4,
                ),
                // Top row - Logo aligned left
                // Container(
                //   height: 13,
                //   padding: const EdgeInsets.symmetric(horizontal: 16),
                //   alignment: Alignment.centerLeft,
                //   child: Container(
                //     width: 49,
                //     height: 13,
                //     child: Image.asset(
                //       'stillurlogo.png',
                //       width: 24,
                //       height: 24,
                //     ).localAsset(),
                //   ),
                // ),

                // Bottom row - Calls title centered
                Container(
                  height: 44,
                  alignment: Alignment.center,
                  child: Text(
                    'Calls',
                    style: TextStyle(
                      color: Color(0xFFFFFFFFF),
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        backgroundColor: Color(0xFF1C212C),
        color: Color(0xFF3498DB),
        child: _showHistory ? _buildCallHistory() : _buildMainCallsView(),
      ),
    );
  }

  /// Handle pull-to-refresh
  Future<void> _handleRefresh() async {
    print('🔄 Pull-to-refresh triggered');
    await Future.wait([
      _loadCallHistory(),
      _loadChats(),
    ]);
  }

  Widget _buildMainCallsView() {
    if (_isLoadingCalls) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF3498DB)),
      );
    }

    // Show empty state with start call button only if no call history
    if (_callHistory.isEmpty) {
      return Column(
        children: [
          // Make private calls section
          Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                SizedBox(
                  height: 40,
                ),
                Image.asset(
                  'make_call.png', // Your phone image asset
                  width: 80,
                  height: 64,
                  color: Color(0xFF6C7B7F),
                ).localAsset(),
                const SizedBox(height: 60),
                const Text(
                  'Make private calls',
                  style: TextStyle(
                      color: Color(0xFFE8E7EA),
                      fontSize: 16,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Your recent voice and video calls will\nappear here',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Color(0xFF8E9297),
                      fontSize: 14,
                      fontWeight: FontWeight.w400),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _showNewCallBottomSheet,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E333E),
                      foregroundColor: Color(0xFF2E333E),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add,
                          size: 14,
                          color: Color(0xFFAACFFF),
                        ),
                        SizedBox(width: 8),
                        Text('Start Call',
                            style: TextStyle(
                                fontSize: 14, color: Color(0xFFAACFFF))),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // Show call history if available
    return Column(
      children: [
        // Recent calls section
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Recent calls',
                      style: TextStyle(
                          color: Color(0xFFE8E7EA),
                          fontSize: 16,
                          fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: _callHistory.length,
                  itemBuilder: (context, index) {
                    final call = _callHistory[index];
                    return _buildCallHistoryItemAsContact(call);
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCallHistoryItemAsContact(UserCallsModel call) {
    final chat = call.chat;
    final sender = call.sender;
    final baseUrl = getEnv('API_BASE_URL');
    
    // Determine name and userId based on chat type
    String name;
    int? userId;
    
    if (chat.type == 'GROUP' || chat.type == 'CHANNEL') {
      // For group/channel: use chat name
      name = chat.name ?? 'Unknown Group';
      userId = null; // Groups don't have a single user avatar
    } else {
      // For private chat: use partner's name if current user is not the partner, else use creator
      final currentUserId = Auth.data()?['id'];
      if (currentUserId != null && chat.partner != null && chat.partner!.id != currentUserId) {
        // Current user is not the partner, use partner's name and id
        name = chat.partner!.username;
        userId = chat.partner!.id;
      } else if (chat.creator != null) {
        // Use creator's name and id
        name = chat.creator!.username;
        userId = chat.creator!.id;
      } else {
        // Fallback to sender
        name = sender.username;
        userId = sender.id;
      }
    }
    
    // Build avatar URL using userId
    final imagePath = userId != null ? '$baseUrl/uploads/$userId' : null;
    
    // Determine call type icon and color
    final currentUserId = Auth.data()?['id'];
    final isIncoming = currentUserId != null && call.senderId != currentUserId;
    final isMissed = call.callStatus == 'MISSED';
    final isDeclined = call.callStatus == 'DECLINED';
    final isFailed = call.callStatus == 'FAILED';
    
    IconData callIcon;
    Color callColor;
    
    if (isMissed || isDeclined) {
      callIcon = Icons.call_received;
      callColor = const Color(0xFFE74C3C);
    } else if (isFailed) {
      callIcon = Icons.call_end;
      callColor = const Color(0xFFFF9800);
    } else if (isIncoming) {
      callIcon = Icons.call_received;
      callColor = const Color(0xFF2ECC71);
    } else {
      callIcon = Icons.call_made;
      callColor = Colors.grey;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Stack(
            children: [
              GestureDetector(
                onTap: () {
                  // Navigate to profile details page
                  routeTo(ProfileDetailsPage.path, data: {
                    'userName': name,
                    'userImage': imagePath,
                    'description': '',
                  });
                },
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.grey.shade700,
                  ),
                  child: ClipOval(
                    child: imagePath != null
                        ? Image.network(
                            imagePath,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(Icons.person,
                                  color: Colors.grey.shade500);
                            },
                          )
                        : Icon(Icons.person, color: Colors.grey.shade500),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Color(0xFFE8E7EA),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      callIcon,
                      size: 14,
                      color: callColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      call.type == 'VIDEO_CALL' ? 'Video' : 'Voice',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {
              // Navigate to voice call with chat data
              final isGroup = call.chat.type == 'CHANNEL' || call.chat.type == 'GROUP';
              routeTo(VoiceCallPage.path, data: {
                'chatId': call.chatId,
                'partner': {
                  'username': name,
                  'avatar': imagePath,
                },
                'isGroup': isGroup,
                'initiateCall': true,
                'avatar': imagePath,
                'groupName': isGroup ? call.chat.name : null,
                'groupImage': isGroup ? imagePath : null,
              });
            },
            icon: const Icon(
              Icons.call,
              color: Color(0xFFE8E7EA),
              size: 22,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () {
              // Navigate to video call with chat data
              final isGroup = call.chat.type == 'CHANNEL' || call.chat.type == 'GROUP';
              routeTo(VideoCallPage.path, data: {
                'chatId': call.chatId,
                'partner': {
                  'username': name,
                  'avatar': imagePath,
                },
                'isGroup': isGroup,
                'initiateCall': true,
                'avatar': imagePath,
                'groupName': isGroup ? call.chat.name : null,
                'groupImage': isGroup ? imagePath : null,
              });
            },
            icon: const Icon(
              Icons.videocam,
              color: Color(0xFFE8E7EA),
              size: 22,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCallHistory() {
    if (_isLoadingCalls) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF3498DB)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Text(
            'Call History',
            style: TextStyle(
              color: Color(0xFFE8E7EA),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: _callHistory.isEmpty
              ? const Center(
                  child: Text(
                    'No call history',
                    style: TextStyle(color: Color(0xFF8E9297)),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: _callHistory.length,
                  itemBuilder: (context, index) {
                    final call = _callHistory[index];
                    return _buildCallHistoryItem(call);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildCallHistoryItem(UserCallsModel call) {
    final sender = call.sender;
    final name = sender.username;
    final avatar = sender.avatar;
    final baseUrl = getEnv('API_BASE_URL');
    final imagePath = '$baseUrl$avatar';
    
    // Format time
    final now = DateTime.now();
    final difference = now.difference(call.createdAt);
    String timeText;
    if (difference.inDays == 0) {
      timeText = '${call.createdAt.hour}:${call.createdAt.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      timeText = 'Yesterday';
    } else if (difference.inDays < 7) {
      timeText = '${difference.inDays}d ago';
    } else {
      timeText = '${call.createdAt.day}/${call.createdAt.month}';
    }
    
    // Determine call type icon and color
    final currentUserId = Auth.data()?['id'];
    final isIncoming = currentUserId != null && call.senderId != currentUserId;
    final isMissed = call.callStatus == 'MISSED';
    final isDeclined = call.callStatus == 'DECLINED';
    final isFailed = call.callStatus == 'FAILED';
    
    IconData callIcon;
    Color callColor;
    
    if (isMissed || isDeclined) {
      callIcon = Icons.call_received;
      callColor = const Color(0xFFE74C3C);
    } else if (isFailed) {
      callIcon = Icons.call_end;
      callColor = const Color(0xFFFF9800);
    } else if (isIncoming) {
      callIcon = Icons.call_received;
      callColor = const Color(0xFF2ECC71);
    } else {
      callIcon = Icons.call_made;
      callColor = Colors.grey;
    }
    
    // Format duration
    String durationText;
    if (call.duration != null && call.duration! > 0) {
      final minutes = call.duration! ~/ 60;
      final seconds = call.duration! % 60;
      durationText = '${minutes}m ${seconds}s';
    } else if (isMissed) {
      durationText = 'Missed';
    } else if (isDeclined) {
      durationText = 'Declined';
    } else if (isFailed) {
      durationText = 'Failed';
    } else {
      durationText = 'No duration';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              // Navigate to profile details page
              routeTo(ProfileDetailsPage.path, data: {
                'userName': name,
                'userImage': imagePath,
                'description': '',
              });
            },
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.grey.shade700,
              ),
              child: ClipOval(
                child: Image.network(
                  imagePath,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Icon(Icons.person, color: Colors.grey.shade500);
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Color(0xFFE8E7EA),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      callIcon,
                      size: 14,
                      color: callColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      durationText,
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                timeText,
                style: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              const Icon(
                Icons.info_outline,
                color: Colors.grey,
                size: 18,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNewCallBottomSheet() {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Color(0xFF1B1C1D),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 84,
            height: 4,
            decoration: BoxDecoration(
              color: Color(0xFFC4C6C8),
              borderRadius: BorderRadius.circular(2),
            ),
          ).onTap(() => Navigator.pop(context)),

          // Header
          Container(
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                        color: Color(0xFFFFFFFF),
                        fontSize: 14,
                        fontWeight: FontWeight.w400),
                  ),
                ),
                const Text(
                  'New Call',
                  style: TextStyle(
                      color: Color(0xFFFFFFFF),
                      fontSize: 18,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 60),
              ],
            ),
          ),

          // Search bar
          Container(
            height: 50,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.transparent,
              border: Border(
                bottom: BorderSide(
                  color: Colors.grey.shade600,
                  width: 1.0,
                ),
              ),
            ),
            child: TextField(
              style: const TextStyle(color: Color(0xFFE8E7EA)),
              decoration: InputDecoration(
                hintText: 'Search contact or username',
                hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 18),
                prefixIcon: Icon(
                  Icons.search,
                  color: Colors.grey.shade500,
                  size: 20,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Recent contacts row
          Container(
            height: 80,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _chats.length > 5 ? 5 : _chats.length,
              itemBuilder: (context, index) {
                final chat = _chats[index];
                final partner = chat.partner;
                final name = partner?.username ?? chat.name;
                final avatar = chat.avatar ?? partner?.avatar;
                final baseUrl = getEnv('API_BASE_URL');
                final imagePath = avatar != null ? '$baseUrl$avatar' : null;
                final chatIdStr = chat.id.toString();
                final isSelected = _selectedContacts.contains(chatIdStr);
                
                return Container(
                  margin: const EdgeInsets.only(right: 16),
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        if (_selectedContacts.contains(chatIdStr)) {
                          _selectedContacts.remove(chatIdStr);
                        } else {
                          _selectedContacts.add(chatIdStr);
                        }
                      });
                    },
                    child: Column(
                      children: [
                        Container(
                          width: 47,
                          height: 47,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.grey.shade700,
                            border: isSelected
                                ? Border.all(color: Color(0xFF57A1FF), width: 2)
                                : null,
                          ),
                          child: ClipOval(
                            child: imagePath != null
                                ? Image.network(
                                    imagePath,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Icon(Icons.person,
                                          color: Colors.grey.shade500);
                                    },
                                  )
                                : Icon(Icons.person, color: Colors.grey.shade500),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          name,
                          style: TextStyle(
                            color: isSelected
                                ? Color(0xFF57A1FF)
                                : Color(0xFFC4C6C8),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          Container(
            height: 0.5,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            color: Color(0xFF2B2A30),
          ),

          const SizedBox(height: 20),

          // Contacts list with alphabet scroll
          Expanded(
            child: _chats.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24.0),
                      child: Text(
                        'No contacts available',
                        style: TextStyle(
                          color: Color(0xFF8E9297),
                          fontSize: 14,
                        ),
                      ),
                    ),
                  )
                : Stack(
              children: [
                // Contacts list
                ListView.builder(
                  padding: const EdgeInsets.only(
                      left: 16,
                      right: 40,
                      bottom: 20), // Add right padding for alphabet
                  itemCount: _getSortedContactsWithHeaders().length,
                  itemBuilder: (context, index) {
                    final item = _getSortedContactsWithHeaders()[index];

                    if (item['isHeader'] == true) {
                      // Section header
                      return Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          item['letter'],
                          style: const TextStyle(
                            color: Color(0xFFE8E7EA),
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    } else {
                      // Contact item
                      final chat = item['contact'] as Chat;
                      final partner = chat.partner;
                      final name = partner?.username ?? chat.name;
                      final avatar = chat.avatar ?? partner?.avatar;
                      final baseUrl = getEnv('API_BASE_URL');
                      final imagePath = avatar != null ? '$baseUrl$avatar' : null;
                      final chatIdStr = chat.id.toString();
                      final isSelected = _selectedContacts.contains(chatIdStr);

                      return Container(
                        margin:
                            const EdgeInsets.only(bottom: 8), // Reduced margin
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              if (isSelected) {
                                _selectedContacts.remove(chatIdStr);
                              } else {
                                _selectedContacts.add(chatIdStr);
                              }
                            });
                          },
                          child: Row(
                            children: [
                              Container(
                                width: 36, // Reduced size
                                height: 36,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.grey.shade700,
                                  border: isSelected
                                      ? Border.all(
                                          color: Color(0xFF57A1FF), width: 2)
                                      : null,
                                ),
                                child: ClipOval(
                                  child: imagePath != null
                                      ? Image.network(
                                          imagePath,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) {
                                            return Icon(Icons.person,
                                                color: Colors.grey.shade500);
                                          },
                                        )
                                      : Icon(Icons.person, color: Colors.grey.shade500),
                                ),
                              ),
                              const SizedBox(width: 12), // Reduced spacing
                              Expanded(
                                child: Text(
                                  name,
                                  style: TextStyle(
                                    color: isSelected
                                        ? Color(0xFF57A1FF)
                                        : Color(0xFFE8E7EA),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    if (isSelected) {
                                      _selectedContacts.remove(chatIdStr);
                                      print(_selectedContacts);
                                    } else {
                                      _selectedContacts.add(chatIdStr);
                                      print(_selectedContacts);
                                    }
                                  });
                                },
                                child: Container(
                                    width: 20, // Smaller selection circle
                                    height: 20,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isSelected
                                          ? Color(0xFF57A1FF)
                                          : Colors.transparent,
                                      border: Border.all(
                                        color: isSelected
                                            ? Color(0xFF57A1FF)
                                            : Colors.grey.shade600,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Container()),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                  },
                ),

                // Alphabet index on the right
                Positioned(
                  right: 8,
                  top: 0,
                  bottom: -1,
                  child: Container(
                    width: 20,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: _getAlphabetLetters().map((letter) {
                        // Check if this letter is the active one
                        final isActive = _currentActiveLetter == letter;
                        print(_currentActiveLetter == letter);
                        return GestureDetector(
                          onTap: () => _scrollToLetter(letter),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: isActive
                                ? BoxDecoration(
                                    color: Color(0xFF57A1FF),
                                    shape: BoxShape.circle,
                                  )
                                : null,
                            child: Text(
                              letter,
                              style: TextStyle(
                                color: isActive
                                    ? Colors.white
                                    : Colors.grey.shade500,
                                fontSize: 12, // Smaller font
                                fontWeight: isActive
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Bottom buttons
          Container(
            color: const Color(0xFF161518),
            padding:
                const EdgeInsets.fromLTRB(16, 8, 16, 16), // Reduced top padding
            child: Column(
              children: [
                // Video Call button
                SizedBox(
                  width: double.infinity,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 12), // Reduced padding
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F131B),
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.videocam,
                            color: Color(0xFFE8E7EA), size: 16),
                        SizedBox(width: 8),
                        Text(
                          'Video Call',
                          style:
                              TextStyle(color: Color(0xFFE8E7EA), fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8), // Reduced spacing
                // Call button with count
                SizedBox(
                  width: double.infinity,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 12), // Reduced padding
                    decoration: BoxDecoration(
                      color: Color(0xFFC8DEFC),
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.call,
                            color: Color(0xFFC8DEFC), size: 16),
                        const SizedBox(width: 8),
                        const Text(
                          'Call',
                          style: TextStyle(
                              color: Color(0xFF121417),
                              fontSize: 18,
                              fontWeight: FontWeight.w700),
                        ),
                        if (_selectedContacts.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Center(
                              child: Text(
                                '${_selectedContacts.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Helper methods to add to your class
  List<Map<String, dynamic>> _getSortedContactsWithHeaders() {
    // Filter to get only private chats (contacts) and sort by name
    final contacts = _chats.where((chat) => chat.type == 'PRIVATE').toList();
    contacts.sort((a, b) {
      final nameA = a.partner?.username ?? a.name;
      final nameB = b.partner?.username ?? b.name;
      return nameA.compareTo(nameB);
    });

    List<Map<String, dynamic>> result = [];
    String currentLetter = '';

    for (final chat in contacts) {
      final name = chat.partner?.username ?? chat.name;
      final firstLetter = name[0].toUpperCase();
      if (firstLetter != currentLetter) {
        // Add section header
        result.add({
          'isHeader': true,
          'letter': firstLetter,
        });
        currentLetter = firstLetter;
      }
      // Add contact
      result.add({
        'isHeader': false,
        'contact': chat,
      });
    }

    return result;
  }

  List<String> _getAlphabetLetters() {
    final letters = <String>{};
    final contacts = _chats.where((chat) => chat.type == 'PRIVATE').toList();
    for (final chat in contacts) {
      final name = chat.partner?.username ?? chat.name;
      letters.add(name[0].toUpperCase());
    }
    return letters.toList()..sort();
  }

  void _scrollToLetter(String letter) {
    // Implement scroll to letter functionality if needed
    // This would require a ScrollController and calculating positions
  }
}
