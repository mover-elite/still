import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/app/models/group_creation_response.dart';
import 'package:flutter_app/app/networking/chat_api_service.dart';
import 'package:flutter_app/app/utils/chat.dart';
import 'package:nylo_framework/nylo_framework.dart';
import 'package:image_picker/image_picker.dart';
import '/app/services/chat_service.dart';
import '/app/models/chat.dart' as models;
import '/app/models/message.dart';
import '/resources/pages/chat_screen_page.dart';

class ChannelsTab extends StatefulWidget {
  const ChannelsTab({super.key});

  @override
  createState() => _ChannelsTabState();
}

class _ChannelsTabState extends NyState<ChannelsTab> {
  bool _showMyChannels = true;
  bool _isLoadingMyChannels = false;
  bool _myChannelsError = false;
  List<Channel> _myChannels = [];
  bool _isLoadingJoinedChannels = false;
  bool _joinedChannelsError = false;
  List<Channel> _joinedChannels = [];
  int? _currentUserId;

  final List<Contact> _contacts = [
    Contact(name: "Layla B", image: "image2.png"),
    Contact(name: "Eleanor", image: "image1.png"),
    Contact(name: "Sheilla", image: "image5.png"),
    Contact(name: "Sandra", image: "image4.png"),
    Contact(name: "Fenta", image: "image8.png"),
    Contact(name: "Arthur", image: "image6.png"),
    Contact(name: "Amanda", image: "image7.png"),
    Contact(name: "Al-Amin", image: "image3.png"),
    Contact(name: "Ahmad", image: "image10.png"),
  ];

  // Add missing variable for alphabet scroll
  String _currentActiveLetter = '';

  // Channel image picking state
  final ImagePicker _channelImagePicker = ImagePicker();
  File? _selectedChannelImage;
  bool _isCreatingChannel = false;
  // Persisted controllers to avoid losing text on rebuilds
  final TextEditingController _channelNameController = TextEditingController();
  final TextEditingController _channelDescriptionController = TextEditingController();
  
  // Contact selection state - persisted to avoid losing selections on rebuild
  List<Contact> _selectedContacts = [];
  Set<int> _selectedChatIds = {};
  List<models.Chat> _topPrivateChats = [];
  bool _loadedTopChats = false;
  
  // Current channel info for adding members
  GroupCreationResponse? _currentChannelInfo;
  bool _isAddingMembers = false;
  
  // Channel type settings - persisted state
  bool _channelIsPrivate = false;
  bool _channelRestrictContent = false;
  
  // Stream subscription for chat updates
  StreamSubscription<List<models.Chat>>? _chatListSubscription;

  Future<void> _pickChannelImage() async {
    try {
      final XFile? picked = await _channelImagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 2048,
      );
      if (!mounted) return;
      if (picked != null) {
        final newFile = File(picked.path);
        // Evict any cached image for this file path to avoid stale previews
        try { await FileImage(newFile).evict(); } catch (_) {}
        setState(() {
          _selectedChannelImage = newFile;
        });
      }
    } catch (e) {
      // Silently ignore for now; could add a toast/snackbar
    }
  }

  @override
  get init => () async {
        final userData = await Auth.data();
        _currentUserId = userData?['id'];
        _loadMyChannels();
        _setupChatListListener();
      };
  
  void _setupChatListListener() {
    // Listen to chat list updates from ChatService
    _chatListSubscription = ChatService().chatListStream.listen((chats) {
      if (!mounted) return;
      
      // Update the currently visible tab
      if (_showMyChannels) {
        _updateMyChannelsFromList(chats);
      } else {
        _updateJoinedChannelsFromList(chats);
      }
    });
  }
  
  void _updateMyChannelsFromList(List<models.Chat> chats) async {
    final userData = await Auth.data();
    final uid = userData != null ? userData['id'] as int? : null;
    final myChannelChats = chats.where((c) => c.type == 'CHANNEL' && (uid != null && c.creatorId == uid)).toList();

    final mapped = myChannelChats.map((c) {
      final image = c.avatar ?? 'image1.png';
      final desc = c.description ?? '';
      return Channel(
        name: c.name,
        description: desc,
        image: image,
        hasNotification: (c.unreadCount > 0),
        chat: c,
      );
    }).toList();

    if (mounted) {
      setState(() {
        _myChannels = mapped;
      });
    }
  }
  
  void _updateJoinedChannelsFromList(List<models.Chat> chats) {
    final joined = chats.where((c) => c.type == 'CHANNEL').toList();

    final mapped = joined.map((c) {
      final image = c.avatar ?? 'image1.png';
      final desc = c.description ?? '';
      return Channel(
        name: c.name,
        description: desc,
        image: image,
        hasNotification: (c.unreadCount > 0),
        chat: c,
      );
    }).toList();

    if (mounted) {
      setState(() {
        _joinedChannels = mapped;
      });
    }
  }

  Future<void> _loadMyChannels() async {
    setState(() {
      _isLoadingMyChannels = true;
      _myChannelsError = false;
    });
    try {
      // Ensure chat service is ready
      if (!ChatService().isInitialized) {
        await ChatService().initialize();
      }
      final userData = await Auth.data();
      final uid = userData != null ? userData['id'] as int? : null;
      final chats = await ChatService().loadChatList();
      final myChannelChats = chats.where((c) => c.type == 'CHANNEL' && (uid != null && c.creatorId == uid)).toList();

      final mapped = myChannelChats.map((c) {
        final image = c.avatar ?? 'image1.png';
        final desc = c.description ?? '';
        return Channel(
          name: c.name,
          description: desc,
          image: image,
          hasNotification: (c.unreadCount > 0),
          chat: c,
        );
      }).toList();

      if (mounted) {
        setState(() {
          _myChannels = mapped;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _myChannelsError = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMyChannels = false;
        });
      }
    }
  }

  Future<void> _loadJoinedChannels() async {
    setState(() {
      _isLoadingJoinedChannels = true;
      _joinedChannelsError = false;
    });
    try {
      if (!ChatService().isInitialized) {
        await ChatService().initialize();
      }
      final chats = await ChatService().loadChatList();
  // Joined = All channels the user is in (including those they created)
  final joined = chats.where((c) => c.type == 'CHANNEL').toList();

      final mapped = joined.map((c) {
        final image = c.avatar ?? 'image1.png';
        final desc = c.description ?? '';
        return Channel(
          name: c.name,
          description: desc,
          image: image,
          hasNotification: (c.unreadCount > 0),
          chat: c,
        );
      }).toList();

      if (mounted) {
        setState(() {
          _joinedChannels = mapped;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _joinedChannelsError = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingJoinedChannels = false;
        });
      }
    }
  }

  Future<void> _handleCreateChannelPressed({
    required String name,
    required String description,
  }) async {
    if (_isCreatingChannel) return;
    final trimmedName = name.trim();
    
    if (trimmedName.isEmpty) {
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a channel name'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isCreatingChannel = true);
    try {
      List<int> members = [];
      // Close the create sheet and move to type/settings, passing the selected image
      GroupCreationResponse? response = await ChatApiService().createGroupChat(
        trimmedName,
        description.trim(),
        members,
        _selectedChannelImage?.path,
      );
      if (response == null) {
        throw Exception('Failed to create channel');
      }
      
      Navigator.pop(context);
      _showChannelTypeSettings(response);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to start channel creation: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isCreatingChannel = false);
    }
  }

  void _showCreateChannelFlow() {
    // Reset fields for a fresh create flow but keep during this session
    _channelNameController.text = '';
    _channelDescriptionController.text = '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (modalContext, modalSetState) {
            void refresh() => modalSetState(() {});
            return _CreateChannelStep1(refresh);
          },
        );
      },
    ).whenComplete(() {
      if (!mounted) return;
      setState(() {
        _selectedChannelImage = null;
      });
    });
  }

  @override
  Widget view(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF0F131B),
      body: Column(
        children: [
          // Top section with proper layout
          Container(
            color: Color(0xff1C212C),
            padding: const EdgeInsets.only(top: 38, left: 16, right: 16),
            child: Column(
              children: [
                // Stillur logo aligned to left
                // Container(
                //   padding: const EdgeInsets.only(bottom: 4),
                //   child: Align(
                //     alignment: Alignment.centerLeft,
                //     child: Container(
                //       width: 50,
                //       height: 13,
                //       child: Image.asset('stillurlogo.png').localAsset(),
                //     ),
                //   ),
                // ),

                // Tabs row with search on extreme right
                Row(
                  children: [
                    // Channel tabs
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _showMyChannels = true;
                        });
                        _loadMyChannels();
                      },
                      child: Container(
                        padding: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          border: _showMyChannels
                              ? const Border(
                                  bottom: BorderSide(
                                      color: Color(0xFF3B69C6), width: 2))
                              : null,
                        ),
                        child: Text(
                          'My Channels',
                          style: TextStyle(
                            color: _showMyChannels
                                ? Color(0xFFFFFFFF)
                                : Colors.grey,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 32),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _showMyChannels = false;
                        });
                        _loadJoinedChannels();
                      },
                      child: Container(
                        padding: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          border: !_showMyChannels
                              ? const Border(
                                  bottom: BorderSide(
                                      color: Color(0xFF3B69C6), width: 2))
                              : null,
                        ),
                        child: Text(
                          'Joined Channels',
                          style: TextStyle(
                            color: !_showMyChannels
                                ? Color(0xFFE8E7EA)
                                : Colors.grey,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),

                    // Spacer to push search to extreme right
                    const Spacer(),

                    // Search icon on extreme right
                    IconButton(
                      icon: const Icon(Icons.search, color: Color(0xFFE8E7EA)),
                      onPressed: () {},
                    ),
                  ],
                ),

                const SizedBox(height: 8),
              ],
            ),
          ),

          // Content area
          Expanded(
            child: _showMyChannels
                ? _buildMyChannelsView()
                : _buildJoinedChannelsView(),
          ),
        ],
      ),
    );
  }

  Widget _buildMyChannelsView() {
    if (_isLoadingMyChannels) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
        ),
      );
    }

    if (_myChannelsError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent),
            const SizedBox(height: 8),
            const Text('Failed to load your channels', style: TextStyle(color: Color(0xFFE8E7EA))),
            const SizedBox(height: 8),
            TextButton(onPressed: _loadMyChannels, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_myChannels.isEmpty) {
      return Column(
        children: [
          // Empty state content first
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Folder image placeholder
                Container(
                  width: 120,
                  height: 120,
                  child: Image.asset(
                    'channel.png', // Replace with your actual image
                    fit: BoxFit.contain,
                  ).localAsset(),
                ),

                const SizedBox(height: 32),

                const Text(
                  'Be a part of a Private Channels',
                  style: TextStyle(
                    color: Color(0xFFE8E7EA),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 8),

                const Text(
                  'Your created or joined channels will\nshow up here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF8E9297),
                    fontSize: 14,
                  ),
                ),

                const SizedBox(height: 40),

                // Create My Channel button moved below the text
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _showCreateChannelFlow,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1C212C),
                      foregroundColor: Color(0xFFE8E7EA),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add, size: 14, color: Color(0xffAACFFF)),
                        SizedBox(
                          width: 8,
                        ),
                        Text('Create New Channel',
                            style: TextStyle(
                                fontSize: 16, color: Color(0xffAACFFF))),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    } else {
      return Column(
        children: [
          Expanded(child: _buildChannelsList(_myChannels)),
          // Bottom Create Channel button
          SafeArea(
            top: false,
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _showCreateChannelFlow,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1C212C),
                  foregroundColor: const Color(0xFFE8E7EA),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 16, color: Color(0xffAACFFF)),
                    SizedBox(width: 8),
                    Text(
                      'Create New Channel',
                      style: TextStyle(fontSize: 16, color: Color(0xffAACFFF)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }
  }

  Widget _buildJoinedChannelsView() {
    if (_isLoadingJoinedChannels) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
        ),
      );
    }

    if (_joinedChannelsError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent),
            const SizedBox(height: 8),
            const Text('Failed to load joined channels', style: TextStyle(color: Color(0xFFE8E7EA))),
            const SizedBox(height: 8),
            TextButton(onPressed: _loadJoinedChannels, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_joinedChannels.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              child: Image.asset('channel.png', fit: BoxFit.contain).localAsset(),
            ),
            const SizedBox(height: 16),
            const Text(
              'No joined channels yet',
              style: TextStyle(
                color: Color(0xFFE8E7EA),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Channels you join will appear here.',
              style: TextStyle(color: Color(0xFF8E9297), fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return _buildChannelsList(_joinedChannels);
  }

  /// Get message preview text with appropriate icon for message type
  Map<String, dynamic> _getMessagePreview(Message? lastMessage) {
    if (lastMessage == null) {
      return {'icon': null, 'text': ''};
    }

    IconData? icon;
    String text;

    switch (lastMessage.type) {
      case 'PHOTO':
      case 'IMAGE':
        icon = Icons.photo;
        text = lastMessage.caption?.isNotEmpty == true 
            ? lastMessage.caption! 
            : 'Photo';
        break;
      
      case 'VIDEO':
        icon = Icons.videocam;
        text = lastMessage.caption?.isNotEmpty == true 
            ? lastMessage.caption! 
            : 'Video';
        break;
      
      case 'AUDIO':
      case 'VOICE':
      case 'VOICE_NOTE':
        icon = Icons.mic;
        text = 'Voice message';
        break;
      
      case 'DOCUMENT':
      case 'FILE':
        icon = Icons.insert_drive_file;
        text = lastMessage.caption?.isNotEmpty == true 
            ? lastMessage.caption! 
            : 'Document';
        break;
      
      case 'VOICE_CALL':
        icon = Icons.phone;
        text = _getCallStatusText(lastMessage, isVoiceCall: true);
        break;
      
      case 'VIDEO_CALL':
        icon = Icons.videocam;
        text = _getCallStatusText(lastMessage, isVoiceCall: false);
        break;
      
      case 'TEXT':
      default:
        icon = null;
        text = lastMessage.text ?? lastMessage.caption ?? '';
        break;
    }

    return {'icon': icon, 'text': text};
  }

  /// Get call status text for channel preview
  String _getCallStatusText(Message message, {required bool isVoiceCall}) {
    final callStatus = message.callStatus ?? 'UNKNOWN';
    final isSentByMe = message.senderId == _currentUserId;
    
    switch (callStatus) {
      case 'MISSED':
        return isSentByMe ? 'Cancelled call' : 'Missed call';
      case 'DECLINED':
        return isSentByMe ? 'Call declined' : 'Declined call';
      case 'FAILED':
        return 'Call failed';
      case 'ENDED':
        if (message.duration != null && message.duration! > 0) {
          return 'Call • ${_formatCallDuration(message.duration!)}';
        }
        return isSentByMe ? 'Outgoing call' : 'Incoming call';
      case 'ONGOING':
        return 'Call in progress';
      case 'INITIALIZED':
      default:
        return isVoiceCall ? 'Voice call' : 'Video call';
    }
  }

  /// Format call duration for preview
  String _formatCallDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    if (minutes > 0) {
      return '${minutes}m ${secs}s';
    }
    return '${secs}s';
  }

  Widget _buildChannelsList(List<Channel> channels) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: channels.length,
      itemBuilder: (context, index) {
        final channel = channels[index];
        return GestureDetector(
          onTap: () {
            if (channel.chat != null) {
              final chat = channel.chat!;
              final userImage = getChatAvatar(chat, getEnv("API_BASE_URL"));
              routeTo(ChatScreenPage.path, data: {
                'chatId': chat.id,
                'userName': chat.name,
                'userImage': userImage,
                'isOnline': false,
                'description': channel.description,
              });
            }
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              // Remove solid background color for list items
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.grey.shade700,
                  ),
                  child: ClipOval(
                    child: _buildChannelImage(channel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        channel.name,
                        style: const TextStyle(
                          color: Color(0xFFE8E7EA),
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Builder(builder: (_) {
                        final lastMsg = channel.chat?.lastMessage;
                        final messagePreview = _getMessagePreview(lastMsg);
                        String preview = messagePreview['text'] as String;
                        final messageIcon = messagePreview['icon'] as IconData?;
                        
                        if (preview.isEmpty) {
                          preview = (channel.chat?.description ?? channel.description).trim();
                        }
                        
                        return Row(
                          children: [
                            if (messageIcon != null) ...[
                              Icon(
                                messageIcon,
                                size: 16,
                                color: Colors.grey.shade500,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Expanded(
                              child: Text(
                                preview,
                                style: TextStyle(
                                  color: Colors.grey.shade400,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        );
                      }),
                    ],
                  ),
                ),
                if (channel.hasNotification)
                  Container(
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(
                      color: Color(0xFF3498DB),
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildChannelImage(Channel channel) {
    final baseUrl = getEnv("API_BASE_URL") ?? '';

    // Prefer resolving avatar via original chat when available
    if (channel.chat != null) {
      final resolved = getChatAvatar(channel.chat!, baseUrl);
      
      if (resolved != null) {
        return Image.network(
          resolved,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(color: Colors.grey.shade800),
        );
      }
      
    }else{
      return Center(
      child: Icon(
        Icons.person,
        color: Colors.grey.shade300,
        size: 36,
      ),
    );
    }
    return Center(
      child: Icon(
        Icons.person,
        color: Colors.grey.shade300,
        size: 36,
      ),
    );
    
  }

  Widget _CreateChannelStep1([void Function()? refresh]) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Color(0xff1B1C1D),
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
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade600,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Color(0xFFE8E7EA), fontSize: 14),
                  ),
                ),
                const Text(
                  'Create Channel',
                  style: TextStyle(
                    color: Color(0xFFE8E7EA),
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 60),
              ],
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // Camera icon and Channel Name on same row
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () async {
                          await _pickChannelImage();
                          if (refresh != null) refresh();
                        },
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: const Color(0xFF3498DB), width: 2),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: ClipOval(
                            key: ValueKey(_selectedChannelImage?.path ?? 'no-image'),
                            child: _selectedChannelImage != null
                                ? Image.file(
                                    _selectedChannelImage!,
                                    fit: BoxFit.cover,
                                    key: ValueKey(_selectedChannelImage!.path),
                                  )
                                : Image.asset("channel_camera.png").localAsset(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFF1F1F1F),
                                Color(0xB2919191),
                              ],
                              stops: [0.3, 1.0],
                            ),
                          ),
                          padding: const EdgeInsets.all(1.5),
                          child: TextField(
                            controller: _channelNameController,
                            style: const TextStyle(color: Color(0xFFE8E7EA)),
                            decoration: InputDecoration(
                              hintText: 'Channel Name',
                              hintStyle: TextStyle(
                                color: Colors.grey.shade400,
                                fontSize: 14,
                              ),
                              filled: true,
                              fillColor: const Color(0xff1B1C1D),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10.5),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10.5),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10.5),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Description field
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF1F1F1F),
                          Color(0xB2919191),
                        ],
                        stops: [0.3, 1.0],
                      ),
                    ),
                    padding: const EdgeInsets.all(1.5),
                    child: TextField(
                      controller: _channelDescriptionController,
                      style: const TextStyle(color: Color(0xFFE8E7EA)),
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: 'Description',
                        hintStyle: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 14,
                        ),
                        filled: true,
                        fillColor: const Color(0xff1B1C1D),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Colors.grey.shade700,
                            width: 1,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Colors.grey.shade700,
                            width: 1,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Colors.grey.shade600,
                            width: 1,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Next button directly below description
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isCreatingChannel
                          ? null
                          : () => _handleCreateChannelPressed(
                                name: _channelNameController.text,
                                description: _channelDescriptionController.text,
                              ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFC8DEFC),
                        foregroundColor: const Color(0xFF0F131B),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        _isCreatingChannel ? 'Next…' : 'Next',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  Text(
                    'You can provide an optional description for your channel',
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 14,
                    ),
                  ),

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showChannelTypeSettings(GroupCreationResponse channelInfo) {
    // Initialize channel settings from the response
    setState(() {
      _channelIsPrivate = channelInfo.isPublic;
      _channelRestrictContent = channelInfo.restrictContent ?? false;
    });
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _ChannelTypeScreen(channelInfo),
      ),
    );
  }

  Widget _ChannelTypeScreen(GroupCreationResponse channelInfo) {
    return StatefulBuilder(
      builder: (context, setModalState) {
        return Scaffold(
          backgroundColor: const Color(0xFF0F131B), // Main page background
          appBar: AppBar(
            backgroundColor: const Color(0xFF0F131B),
            elevation: 0,
            centerTitle: true,
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_ios,
                  color: Color(0xFFE8E7EA), size: 20),
            ),
            title: const Text(
              'Channel Type',
              style: TextStyle(
                color: Color(0xFFE8E7EA),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _showContactSelection(channelInfo);
                },
                child: const Text(
                  'Next',
                  style: TextStyle(color: Color(0xFF3498DB), fontSize: 16),
                ),
              ),
            ],
          ),
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Channel Type Selection Section
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C212C), // Section background
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        // Public option
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _channelIsPrivate = false;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            child: Row(
                              children: [
                                Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: !_channelIsPrivate
                                          ? const Color(0xFF3498DB)
                                          : Colors.grey.shade600,
                                      width: 2,
                                    ),
                                  ),
                                  child: !_channelIsPrivate
                                      ? Container(
                                          margin: const EdgeInsets.all(4),
                                          decoration: const BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Color(0xFF3498DB),
                                          ),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 16),
                                const Text(
                                  'Public',
                                  style: TextStyle(
                                    color: Color(0xFFE8E7EA),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Divider
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 20),
                          height: 1,
                          color: Colors.grey.shade800,
                        ),

                        // Private option
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _channelIsPrivate = true;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            child: Row(
                              children: [
                                Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: _channelIsPrivate
                                          ? const Color(0xFF3498DB)
                                          : Colors.grey.shade600,
                                      width: 2,
                                    ),
                                  ),
                                  child: _channelIsPrivate
                                      ? Container(
                                          margin: const EdgeInsets.all(4),
                                          decoration: const BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Color(0xFF3498DB),
                                          ),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 16),
                                const Text(
                                  'Private',
                                  style: TextStyle(
                                    color: Color(0xFFE8E7EA),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (_channelIsPrivate) ...[
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        'Private channel can only be joined via link',
                        style: TextStyle(
                          color: Color(0xff82808F),
                          fontSize: 13,
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Invite Link section
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C212C), // Section background
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header inside the container
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                            child: Text(
                              'INVITE LINK',
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),

                          // Link row - compact width
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Color(0xff0F131B),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 12),
                              child: Row(
                                mainAxisSize: MainAxisSize.max,
                                children: [
                                  // Allow the invite text to shrink and ellipsize instead of overflowing
                                  Flexible(
                                    child: Text(
                                      's.me/+${channelInfo.inviteCode}',
                                      style: const TextStyle(
                                        color: Color(0xFFE8E7EA),
                                        fontSize: 18,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  GestureDetector(
                                    onTap: () {
                                      HapticFeedback.lightImpact();
                                    },
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Color(0xFFC8DEFC),
                                        shape: BoxShape.circle,
                                      ),
                                      padding: EdgeInsets.all(
                                          8.0), // Add padding for better visual appearance
                                      child: const Icon(
                                        Icons.more_horiz,
                                        color: Color(0xff0F131B),
                                        size: 24,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Share Link button inside the container
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 22, 20),
                            child: SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () {},
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(
                                      0xFFC8DEFC), // Button background
                                  foregroundColor: const Color(
                                      0xFF0F131B), // Button text color (dark)
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(1),
                                  ),
                                  elevation: 0,
                                ),
                                child: const Text(
                                  'Share Link',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    Text(
                      'People can join channel by following this link.\nYou can revoke the link at any time.',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.left,
                    ),

                    const SizedBox(height: 40),

                    // Saving and Copying Content section
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        'SAVING AND COPYING CONTENT',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C212C), // Section background
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Restrict Saving Content',
                            style: TextStyle(
                              color: Color(0xFFE8E7EA),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Switch(
                            value: _channelRestrictContent,
                            onChanged: (value) {
                              setState(() {
                                _channelRestrictContent = value;
                              });
                            },
                            activeThumbColor: const Color(0xFF3498DB),
                            inactiveThumbColor: Colors.grey.shade400,
                            inactiveTrackColor: Colors.grey.shade700,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 6,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        'Subscribe will be able to copy, save and forward content from this channel',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Add missing methods
  List<Map<String, dynamic>> _getSortedContactsWithHeaders() {
    // Sort contacts by name
    final sortedContacts = List<Contact>.from(_contacts)
      ..sort((a, b) => a.name.compareTo(b.name));

    List<Map<String, dynamic>> result = [];
    String currentLetter = '';

    for (final contact in sortedContacts) {
      final firstLetter = contact.name[0].toUpperCase();
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
        'contact': contact,
      });
    }

    return result;
  }

  List<String> _getAlphabetLetters() {
    final letters = <String>{};
    for (final contact in _contacts) {
      letters.add(contact.name[0].toUpperCase());
    }
    return letters.toList()..sort();
  }

  void _scrollToLetter(String letter) {
    // Implement scroll to letter functionality if needed
    // This would require a ScrollController and calculating positions
    setState(() {
      _currentActiveLetter = letter;
    });
  }

  void _showContactSelection(GroupCreationResponse channelInfo) {
    // Reset selections when opening contact selection
    setState(() {
      _selectedContacts = [];
      _selectedChatIds = {};
      _loadedTopChats = false;
      _topPrivateChats = [];
      _currentChannelInfo = channelInfo;
    });
    
    // Load top chats before showing modal to avoid loading in Builder
    _loadTopPrivateChats();
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ContactSelection(),
    );
  }
  
  Future<void> _loadTopPrivateChats() async {
    if (_loadedTopChats) return;
    _loadedTopChats = true;
    
    try {
      if (!ChatService().isInitialized) {
        await ChatService().initialize();
      }
      final chats = await ChatService().loadChatList();
      final filtered = chats.where((c) => c.type == 'PRIVATE').take(10).toList();
      if (mounted) {
        setState(() {
          _topPrivateChats = filtered;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _topPrivateChats = [];
        });
      }
    }
  }

  Future<void> _handleAddMembers() async {
    if (_isAddingMembers || _currentChannelInfo == null) return;
    
    // Collect all selected user IDs from both contacts and chats
    List<int> memberIds = [];
    
    // Add selected chat IDs (these are user IDs from private chats)
    memberIds.addAll(_selectedChatIds);
    
    // Note: _selectedContacts uses Contact objects which don't have user IDs
    // If you need to add contacts, you'll need to store their user IDs in the Contact model
    
    if (memberIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one member to add'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isAddingMembers = true);
    
    try {
      final result = await ChatApiService().addMembersToChat(
        _currentChannelInfo!.id,
        memberIds,
      );
      
      if (!mounted) return;
      
      if (result != null) {
        final addedCount = result['added']?.length ?? 0;
        final alreadyMembersCount = result['alreadyMembers']?.length ?? 0;
        final notFoundCount = result['notFound']?.length ?? 0;
        
        String message = '';
        if (addedCount > 0) {
          message = 'Successfully added $addedCount member${addedCount > 1 ? 's' : ''}';
        }
        if (alreadyMembersCount > 0) {
          if (message.isNotEmpty) message += '. ';
          message += '$alreadyMembersCount already member${alreadyMembersCount > 1 ? 's' : ''}';
        }
        if (notFoundCount > 0) {
          if (message.isNotEmpty) message += '. ';
          message += '$notFoundCount not found';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message.isNotEmpty ? message : 'Members added successfully'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: addedCount > 0 ? Colors.green : Colors.orange,
          ),
        );
        
        // Close the contact selection modal
        Navigator.pop(context);
      } else {
        throw Exception('Failed to add members');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to add members: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isAddingMembers = false);
    }
  }

  Widget _ContactSelection() {
    // Use state variables instead of local variables to persist selections across rebuilds
    return StatefulBuilder(
      builder: (context, setModalState) {
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
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  margin: const EdgeInsets.only(top: 8),
                  width: 84,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Color(0xFFC4C6C8),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              Container(
                padding: const EdgeInsets.all(8),
                child: Row(
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
                    const Expanded(
                      child: Center(
                        child: Text(
                          'Contact',
                          style: TextStyle(
                              color: Color(0xFFFFFFFF),
                              fontSize: 18,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _isAddingMembers ? null : _handleAddMembers,
                      child: Text(
                        _isAddingMembers
                            ? 'Adding...'
                            : (_selectedContacts.length + _selectedChatIds.length) > 0
                                ? 'Add (${_selectedContacts.length + _selectedChatIds.length})'
                                : 'Add',
                        style: TextStyle(
                          color: _isAddingMembers ? Colors.grey : const Color(0xFF3498DB),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
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
                    hintStyle:
                        TextStyle(color: Colors.grey.shade500, fontSize: 18),
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

              // Recent contacts row (Top PRIVATE chats from ChatService)
              Container(
                  height: 80,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _topPrivateChats.length,
                    itemBuilder: (context, index) {
                      final chat = _topPrivateChats[index];
                      final displayName = chat.name;
                      final avatarUrl = chat.avatar ?? chat.partner?.avatar;
                      final isSelected = _selectedChatIds.contains(chat.id);

                      Widget avatarWidget;
                      if (avatarUrl != null) {
                        final baseUrl = getEnv("API_BASE_URL") ?? '';
                        final avatarLink = avatarUrl.startsWith('http') ? avatarUrl : '$baseUrl$avatarUrl';
                        avatarWidget = Image.network(avatarLink, fit: BoxFit.cover);
                      } else if (avatarUrl != null && avatarUrl.isNotEmpty) {
                        avatarWidget = Image.asset(avatarUrl, fit: BoxFit.cover).localAsset();
                      } else {
                        avatarWidget = Center(
                          child: Icon(
                          Icons.person,
                          color: Colors.grey.shade300,
                          size: 24,
                          ),
                        );
                      }

                      return Container(
                        margin: const EdgeInsets.only(right: 16),
                        child: GestureDetector(
                          onTap: () {
                            if (isSelected) {
                              _selectedChatIds.remove(chat.id);
                            } else {
                              _selectedChatIds.add(chat.id);
                            }
                            setModalState(() {});
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
                                      ? Border.all(color: const Color(0xFF57A1FF), width: 2)
                                      : null,
                                ),
                                child: ClipOval(child: avatarWidget),
                              ),
                              const SizedBox(height: 4),
                              SizedBox(
                                width: 60,
                                child: Text(
                                  displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: isSelected ? const Color(0xFF57A1FF) : const Color(0xFFC4C6C8),
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

              // Invite link section
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.content_copy,
                        color: Color(0xFF57A1FF),
                        size: 14,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Text(
                      's.me/+CGHSDhdkgjudkj',
                      style: TextStyle(
                          color: Color(0xFF3498DB),
                          fontSize: 16,
                          fontWeight: FontWeight.w300),
                    ),
                  ],
                ),
              ),

              Container(
                height: 0.5,
                margin:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                color: Color(0xFF2B2A30),
              ),

              // Frequently Contacted section
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Frequently Contacted',
                    style: TextStyle(
                      color: Color(0xFF82808F),
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Contacts list with alphabet scroll
              Expanded(
                child: Stack(
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
                          final contact = item['contact'] as Contact;
                          final isSelected = _selectedContacts.contains(contact);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: GestureDetector(
                              onTap: () {
                                if (isSelected) {
                                  _selectedContacts.remove(contact);
                                } else {
                                  _selectedContacts.add(contact);
                                }
                                setModalState(() {});
                              },
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.grey.shade700,
                                      border: isSelected
                                          ? Border.all(
                                              color: Color(0xFF57A1FF),
                                              width: 2)
                                          : null,
                                    ),
                                    child: ClipOval(
                                      child: Image.asset(
                                        contact.image,
                                        fit: BoxFit.cover,
                                      ).localAsset(),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      contact.name,
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
                                      if (isSelected) {
                                        _selectedContacts.remove(contact);
                                      } else {
                                        _selectedContacts.add(contact);
                                      }
                                      setModalState(() {});
                                    },
                                    child: Container(
                                      width: 20,
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
                                      child: Container(),
                                    ),
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
                      bottom: 0,
                      child: Container(
                        width: 20,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: _getAlphabetLetters().map((letter) {
                            // Check if this letter is the active one
                            final isActive = _currentActiveLetter == letter;
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
                                    fontSize: 10,
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

              // Removed bottom Send bar; action moved to header
            ],
          ),
        );
      },
    );
  }
  
  @override
  void dispose() {
    _chatListSubscription?.cancel();
    _channelNameController.dispose();
    _channelDescriptionController.dispose();
    super.dispose();
  }
}

// Helper functions removed (unused)

// Model classes
class Channel {
  final String name;
  final String description;
  final String image;
  final bool hasNotification;
  final models.Chat? chat; // original chat for avatar resolution

  Channel({
    required this.name,
    required this.description,
    required this.image,
    this.hasNotification = false,
    this.chat,
  });
}

class Contact {
  final String name;
  final String image;
  final bool isOnline;

  Contact({
    required this.name,
    required this.image,
    this.isOnline = false,
  });
}

class CallHistory {
  final Contact contact;
  final String time;
  final CallType type;
  final String duration;
  final int? count;

  CallHistory({
    required this.contact,
    required this.time,
    required this.type,
    required this.duration,
    this.count,
  });
}

enum CallType { incoming, outgoing, missed }
