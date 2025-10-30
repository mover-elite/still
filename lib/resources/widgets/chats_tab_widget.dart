import 'dart:ui';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/app/models/chat.dart';
import 'package:flutter_app/app/models/contact_info.dart';
import 'package:flutter_app/app/models/message.dart';
import 'package:flutter_app/resources/widgets/alphabet_scroll_view_widget.dart';
import 'package:flutter_svg/svg.dart';
import 'package:nylo_framework/nylo_framework.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import '../../app/networking/contact_api_service.dart';
import '../../app/networking/chat_api_service.dart';
import '../../app/models/user_info.dart';
import '../../app/models/chat_creation_response.dart';
import '../pages/chat_screen_page.dart';
import '../pages/profile_details_page.dart';
import '../../app/networking/websocket_service.dart';
import "../../app/utils/chat.dart";
import "/app/services/chat_service.dart";

class ChatsTab extends StatefulWidget {
  const ChatsTab({super.key});

  @override
  createState() => _ChatsTabState();
}

class _ChatsTabState extends NyState<ChatsTab> {
  List<ContactInfo> contactList = [];
  List<ContactInfo> filteredContactList = [];
  List<Chat> chatList = [];
  List<UserInfo> searchResults = [];
  List<String> recentSearches = [];
  Map<String, List<UserInfo>> searchCache = {};
  bool isLoadingContacts = false; // Keep for internal logic
  bool isSearching = false;
  bool showSearchResults = false;
  int? _currentUserId;
  TextEditingController searchController = TextEditingController();
  Timer? _searchDebounceTimer;

  // Websocket subscriptions
  StreamSubscription<Map<String, dynamic>>? _wsSubscription;
  StreamSubscription<Map<String, dynamic>>? _msgStream;
  StreamSubscription<bool>? _connectionSubscription;

  StreamSubscription<List<Chat>>? _chatListSubscription;

  @override
  get init => () {
        _initializeChatService();
        // _initializeWebSocket();
        _initContactList();

        _preloadCommonSearches();
      };

  @override
  void dispose() {
    searchController.dispose();
    _searchDebounceTimer?.cancel();
    _wsSubscription?.cancel();
    _msgStream?.cancel();
    _chatListSubscription?.cancel();
    _connectionSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initializeChatService() async {
    final userData = await Auth.data();
    _currentUserId = userData?['id'];

    // Set up stream listener BEFORE initializing to catch the initial emission
    _chatListSubscription?.cancel();
    _chatListSubscription = ChatService().chatListStream.listen((chats) {
      if (mounted) {
        setState(() {
          chatList = chats;
        });
        print('📱 Chats tab received ${chats.length} chats from stream');
      }
    });

    await ChatService().initialize();
    
    // Also load directly to ensure we have data even if stream timing is off
    _loadRecentChats();
  }

  Future<void> _initializeWebSocket() async {
    await WebSocketService().initializeConnection();

    _msgStream = WebSocketService().messageStream.listen((messageData) {
      _handleIncomingMessage(messageData);
    });
  }

  void _handleIncomingMessage(Map<String, dynamic> messageData) {
    // This runs on the main thread and won't block UI

    Message newMessage = Message.fromJson(messageData);

    setState(() {
      final index = chatList.indexWhere((chat) => chat.id == newMessage.chatId);
      if (index != -1) {
        final chat = chatList[index];
        chatList[index] = chat.copyWith(
          lastMessage: newMessage,
          unreadCount: (chat.unreadCount ?? 0) + 1,
        );
        // Move chat to top
        final updatedChat = chatList.removeAt(index);
        print("Inserted here");
        chatList.insert(0, updatedChat);
      }
    });
  }

  // Clear search cache (call this when user logs out or app refreshes)
  void _clearSearchCache() {
    searchCache.clear();
    recentSearches.clear();
  }

  // Show invite dialog
  void _showInviteDialog(BuildContext context, ContactInfo contact) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Color(0xFF1B1C1D),
          title: Text(
            'Invite ${contact.name}',
            style: TextStyle(
              color: Color(0xFFE8E7EA),
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Text(
            'Would you like to invite ${contact.name} to join the platform?',
            style: TextStyle(
              color: Color(0xFFE8E7EA),
              fontSize: 14,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: Colors.grey,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _sendInvite(contact);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFF57A1FF),
              ),
              child: Text(
                'Send Invite',
                style: TextStyle(
                  color: Colors.white,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // Send invite to contact
  void _sendInvite(ContactInfo contact) {
    // TODO: Implement invite functionality
    // This could be sending an SMS, email, or sharing a link
    print('Sending invite to ${contact.name} at ${contact.phoneNumber}');

    // Show success message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Invite sent to ${contact.name}'),
        backgroundColor: Color(0xFF57A1FF),
      ),
    );
  }

  // Search users with debounce and caching
  void _onSearchChanged(String query) {
    // Cancel previous timer
    _searchDebounceTimer?.cancel();

    if (query.trim().isEmpty) {
      // Show recent contacts when search is empty but user might want to see suggestions
      if (searchCache.containsKey('')) {
        setState(() {
          searchResults = searchCache['']!;
          showSearchResults = true;
          isSearching = false;
        });
      } else {
        setState(() {
          showSearchResults = false;
          searchResults = [];
          isSearching = false;
        });
      }
      return;
    }

    // Check cache first for immediate results
    if (searchCache.containsKey(query.trim())) {
      setState(() {
        searchResults = searchCache[query.trim()]!;
        showSearchResults = true;
        isSearching = false;
      });
      return;
    }

    // Show progressive results for short queries
    if (query.length <= 2) {
      _showQuickResults(query.trim());
    } else {
      // Set searching state
      setState(() {
        isSearching = true;
        showSearchResults = true;
      });

      // Faster debounce for better UX
      _searchDebounceTimer = Timer(Duration(milliseconds: 250), () {
        _performSearch(query.trim());
      });
    }
  }

  // Show quick results for short queries
  void _showQuickResults(String query) {
    // Filter from existing contacts and chats for immediate results
    List<UserInfo> quickResults = [];

    // Add contacts that match
    for (var contact in contactList) {
      if ((contact.name?.toLowerCase().contains(query.toLowerCase()) ??
              false) ||
          (contact.platformUsername != null &&
              contact.platformUsername!
                  .toLowerCase()
                  .contains(query.toLowerCase()))) {
        quickResults.add(UserInfo(
          id: int.tryParse(contact.contactId ?? '0'),
          username: contact.platformUsername,
          firstName: contact.name,
          lastName: '',
          email: null,
          phone: contact.phoneNumber,
          avatar: null,
          isOnline: false,
          isVerified: false,
        ));
      }
    }

    // Add recent chats that match
    for (var chat in chatList) {
      if (chat.partner?.username.toLowerCase().contains(query.toLowerCase()) ??
          false) {
        quickResults.add(UserInfo(
          id: chat.partner?.id,
          username: chat.partner?.username,
          firstName: chat.partner?.firstName,
          lastName: chat.partner?.lastName,
          email: null,
          phone: null,
          avatar: null,
          isOnline: false,
          isVerified: false,
        ));
      }
    }

    setState(() {
      searchResults = quickResults;
      showSearchResults = true;
      isSearching = false;
    });
  }

  // Perform actual search with caching
  Future<void> _performSearch(String query) async {
    try {
      // Check if user is authenticated
      Map<String, dynamic>? userData = await Auth.data();
      if (userData == null || userData['accessToken'] == null) {
        print('User not authenticated, skipping search');
        setState(() {
          isSearching = false;
          showSearchResults = false;
        });
        return;
      }

      // Create API service
      ChatApiService apiService = ChatApiService(buildContext: context);

      // Search users
      List<Map<String, dynamic>> response = await apiService.searchUsers(query);

      if (mounted) {
        List<UserInfo> results = response.map((userData) {
          return UserInfo.fromJson(userData);
        }).toList();

        // Cache the results
        searchCache[query] = results;

        // Add to recent searches
        _addToRecentSearches(query);

        setState(() {
          searchResults = results;
          isSearching = false;
        });
      }
    } catch (e) {
      print('Error searching users: $e');
      if (mounted) {
        setState(() {
          isSearching = false;
        });
      }
    }
  }

  // Add search to recent searches
  void _addToRecentSearches(String query) {
    if (query.trim().isNotEmpty && !recentSearches.contains(query)) {
      recentSearches.insert(0, query);
      if (recentSearches.length > 5) {
        recentSearches.removeLast();
      }
    }
  }

  // Preload common searches
  void _preloadCommonSearches() {
    // Preload recent contacts for quick access
    if (contactList.isNotEmpty) {
      // Cache first few contacts for instant search
      List<UserInfo> recentContacts = contactList.take(10).map((contact) {
        return UserInfo(
          id: int.tryParse(contact.contactId ?? '0'),
          username: contact.platformUsername,
          firstName: contact.name,
          lastName: '',
          email: null,
          phone: contact.phoneNumber,
          avatar: null,
          isOnline: false,
          isVerified: false,
        );
      }).toList();

      searchCache[''] = recentContacts; // Empty query shows recent contacts
    }
  }

  // Handle user selection from search
  Future<void> _onUserSelected(UserInfo user) async {
    try {
      print('=== USER SELECTION DEBUG ===');
      print('Selected user: ${user.displayName} (ID: ${user.id})');

      // Show loading state (optional - like WhatsApp)
      setState(() {
        showSearchResults = false;
      });

      // Create or get existing chat
      ChatApiService apiService = ChatApiService(buildContext: context);

      print('Creating chat with partnerId: ${user.id}');
      Map<String, dynamic>? chatResponse = await apiService.createOrGetChat(
        type: "PRIVATE",
        partnerId: user.id.toString(),
      );

      print('Chat creation response: $chatResponse');

      if (chatResponse != null) {
        // Parse the response
        ChatCreationResponse chatData =
            ChatCreationResponse.fromJson(chatResponse);

        print('✅ Chat created successfully, navigating with chat data');
        // Navigate to chat screen with chat data
        routeTo(ChatScreenPage.path, data: {
          'chatId': chatData.id,
          'partnerId': user.id,
          'partnerUsername': user.username,
          'userName': user.displayName,
          'userImage': user.avatar,
          'isOnline': user.isOnline ?? false,
          'isVerified': user.isVerified ?? false,
          'chatData': chatData, // Pass structured chat data
          'messages': chatData.messages, // Pass messages array
        });
      } else {
        print('❌ Chat creation failed, using fallback navigation');
        // Fallback navigation if chat creation fails
        routeTo(ChatScreenPage.path, data: {
          'chatId': 999, // Temporary chat ID for testing
          'partnerId': user.id,
          'partnerUsername': user.username,
          'userName': user.displayName,
          'userImage': user.avatar,
          'isOnline': user.isOnline ?? false,
          'isVerified': user.isVerified ?? false,
        });
      }

      // Clear search
      setState(() {
        searchController.clear();
        showSearchResults = false;
        searchResults = [];
      });
    } catch (e) {
      print('Error creating chat: $e');
      // Fallback navigation
      routeTo(ChatScreenPage.path, data: {
        'partnerId': user.id,
        'partnerUsername': user.username,
        'userName': user.displayName,
        'userImage': user.avatar,
        'isOnline': user.isOnline ?? false,
        'isVerified': user.isVerified ?? false,
      });
    }
  }

  // Build search skeleton loading
  Widget _buildSearchSkeleton() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Color(0xFF2B2A30),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          // Skeleton avatar
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Color(0xFF2B2A30),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          SizedBox(width: 12),
          // Skeleton text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 14,
                  width: 120,
                  decoration: BoxDecoration(
                    color: Color(0xFF2B2A30),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                SizedBox(height: 8),
                Container(
                  height: 12,
                  width: 80,
                  decoration: BoxDecoration(
                    color: Color(0xFF2B2A30),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Build search result item
  Widget _buildSearchResultItem(UserInfo user) {
    return InkWell(
      onTap: () => _onUserSelected(user),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Color(0xFF2B2A30),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            // User avatar
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Color(0xFF57A1FF),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Center(
                child: Text(
                  user.displayName.isNotEmpty
                      ? user.displayName[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            SizedBox(width: 12),
            // User info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        user.displayName,
                        style: TextStyle(
                          color: Color(0xFFE8E7EA),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (user.isVerified == true) ...[
                        SizedBox(width: 4),
                        Icon(
                          Icons.verified,
                          color: Color(0xFF57A1FF),
                          size: 14,
                        ),
                      ],
                    ],
                  ),
                  if (user.username != null)
                    Text(
                      '@${user.username}',
                      style: TextStyle(
                        color: Color(0xFF82808F),
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            // Online indicator
            if (user.isOnline == true)
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Load recent chats from API (silent loading like WhatsApp)
  Future<void> _loadRecentChats() async {
    try {
      final List<Chat> chats = await ChatService().loadChatList();
      print('📱 Chats tab _loadRecentChats loaded ${chats.length} chats');
      if (mounted) {
        setState(() {
          chatList = chats;
        });
        print('📱 Chats tab setState completed with ${chatList.length} chats');
      }
    } catch (e) {
      print('❌ Error loading recent chats: $e');
    }
  }

  void _initContactList() {
    // Initialize with empty list - no dummy data
    contactList = [];
    filteredContactList = [];
  }

  // Helper function to get avatar image for contact
  String _getContactAvatar(String name) {
    final avatars = [
      'image1.png',
      'image2.png',
      'image3.png',
      'image4.png',
      'image5.png',
      'image6.png',
      'image7.png',
      'image8.png',
      'image9.png',
      'image10.png',
      'image11.png'
    ];
    final index = name.hashCode % avatars.length;
    return avatars[index.abs()];
  }

  // Helper function to clean phone number
  String _cleanPhoneNumber(String phoneNumber) {
    // Remove all non-digit characters
    String cleaned = phoneNumber.replaceAll(RegExp(r'[^\d]'), '');

    // If it starts with 0, replace with country code
    if (cleaned.startsWith('0')) {
      cleaned = '234' + cleaned.substring(1);
    }

    // If it doesn't start with country code, add it
    if (!cleaned.startsWith('234')) {
      cleaned = '234' + cleaned;
    }

    return cleaned;
  }

  // Check contacts against platform
  Future<void> _checkContactsOnPlatform(List<ContactInfo> contacts) async {
    try {
      // Check if user is authenticated
      Map<String, dynamic>? userData = await Auth.data();
      if (userData == null || userData['accessToken'] == null) {
        print('User not authenticated, skipping platform contact check');
        return;
      }

      // Extract phone numbers
      List<String> phoneNumbers = contacts
          .where((contact) =>
              contact.phoneNumber != null && contact.phoneNumber!.isNotEmpty)
          .map((contact) => _cleanPhoneNumber(contact.phoneNumber!))
          .toList();

      if (phoneNumbers.isEmpty) return;

      // Create API service
      ContactApiService apiService = ContactApiService(buildContext: context);

      // Check contacts
      List<Map<String, dynamic>> results =
          await apiService.checkContacts(phoneNumbers);

      // Update contacts with platform status
      for (ContactInfo contact in contacts) {
        if (contact.phoneNumber != null) {
          String cleanedPhone = _cleanPhoneNumber(contact.phoneNumber!);

          // Find matching result
          Map<String, dynamic>? result = results.firstWhere(
            (result) => result['phone'].toString() == cleanedPhone,
            orElse: () => {'status': false},
          );

          if (result['status'] == true) {
            contact.isRegisteredOnPlatform = true;
            contact.platformUsername = result['data']['username'];
            contact.platformUserId = result['data']['id'].toString();
          } else {
            contact.isRegisteredOnPlatform = false;
          }
        }
      }
    } catch (e) {
      print('Error checking contacts on platform: $e');
    }
  }

  Future<void> _loadDeviceContacts() async {
    if (isLoadingContacts) return;

    setState(() {
      isLoadingContacts = true;
    });

    try {
      // Check if contacts permission is granted
      if (!await FlutterContacts.requestPermission()) {
        setState(() {
          isLoadingContacts = false;
        });
        return;
      }

      // Get all contacts
      List<Contact> contacts = await FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: false, // We'll use our own avatars
      ).timeout(
        Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Timeout while loading contacts');
        },
      );

      // If no contacts found, set empty state
      if (contacts.isEmpty) {
        setState(() {
          contactList = [];
          filteredContactList = [];
          isLoadingContacts = false;
        });
        return;
      }

      // Convert to ContactInfo objects
      List<ContactInfo> deviceContacts = [];

      for (Contact contact in contacts) {
        if (contact.name.first.isNotEmpty) {
          String? phoneNumber;
          if (contact.phones.isNotEmpty) {
            phoneNumber = contact.phones.first.number;
          }

          deviceContacts.add(ContactInfo.create(
            name: contact.name.first,
            imagePath:
                _getContactAvatar(contact.name.first), // Use avatar image
            tagIndex: contact.name.first[0].toUpperCase(),
            phoneNumber: phoneNumber,
            contactId: contact.id,
          ));
        }
      }

      // Sort alphabetically
      deviceContacts.sort((a, b) {
        String nameA = a.name ?? '';
        String nameB = b.name ?? '';
        return nameA.compareTo(nameB);
      });

      // Add section headers
      _handleSectionHeadersForContacts(deviceContacts);

      // Check contacts against platform
      await _checkContactsOnPlatform(deviceContacts);

      setState(() {
        contactList = deviceContacts;
        filteredContactList = deviceContacts;
        isLoadingContacts = false;
      });
    } catch (e) {
      setState(() {
        isLoadingContacts = false;
      });

      // Show a snackbar or dialog to inform user about the error
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load contacts: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _handleSectionHeadersForContacts(List<ContactInfo> contacts) {
    String currentTag = "";
    for (int i = 0; i < contacts.length; i++) {
      String? contactName = contacts[i].name;
      if (contactName != null && contactName.isNotEmpty) {
        String tag = contactName[0].toUpperCase();
        if (tag != currentTag) {
          contacts[i].tagIndex = tag;
          contacts[i].isShowSuspension = true;
          currentTag = tag;
        } else {
          contacts[i].isShowSuspension = false;
        }
      } else {
        contacts[i].tagIndex = "#";
        contacts[i].isShowSuspension = false;
      }
    }
  }

  void _filterContacts(String query) {
    if (query.isEmpty) {
      setState(() {
        filteredContactList = contactList;
      });
    } else {
      setState(() {
        filteredContactList = contactList.where((contact) {
          final name = contact.name?.toLowerCase() ?? '';
          final phone = contact.phoneNumber?.toLowerCase() ?? '';
          final username = contact.platformUsername?.toLowerCase() ?? '';
          final searchQuery = query.toLowerCase();
          return name.contains(searchQuery) ||
              phone.contains(searchQuery) ||
              username.contains(searchQuery);
        }).toList();
      });
    }
  }

  void _showNewChatBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          TextEditingController modalSearchController = TextEditingController();
          List<ContactInfo> modalFilteredContacts = filteredContactList;

          // Filter contacts function for the modal
          void filterModalContacts(String query) {
            if (query.isEmpty) {
              setModalState(() {
                modalFilteredContacts = contactList;
              });
            } else {
              setModalState(() {
                modalFilteredContacts = contactList.where((contact) {
                  final name = contact.name?.toLowerCase() ?? '';
                  final phone = contact.phoneNumber?.toLowerCase() ?? '';
                  final username =
                      contact.platformUsername?.toLowerCase() ?? '';
                  final searchQuery = query.toLowerCase();
                  return name.contains(searchQuery) ||
                      phone.contains(searchQuery) ||
                      username.contains(searchQuery);
                }).toList();
              });
            }
          }

          // Load contacts if not already loaded
          if (contactList.isEmpty && !isLoadingContacts) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _loadDeviceContacts().then((_) {
                setModalState(() {
                  modalFilteredContacts = filteredContactList;
                });
              });
            });
          }

          return Container(
            height: MediaQuery.of(context).size.height * 0.8,
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
                ).onTap(() {
                  modalSearchController.dispose();
                  Navigator.pop(context);
                }),

                // Header
                Container(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () {
                          modalSearchController.dispose();
                          Navigator.pop(context);
                        },
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                              color: Color(0xFFFFFFFF),
                              fontSize: 14,
                              fontWeight: FontWeight.w400),
                        ),
                      ),
                      const Text(
                        'New Chat',
                        style: TextStyle(
                            color: Color(0xFFFFFFFF),
                            fontSize: 18,
                            fontWeight: FontWeight.w600),
                      ),
                      IconButton(
                        onPressed: () {
                          modalSearchController.clear();
                          filterModalContacts('');
                          _loadDeviceContacts().then((_) {
                            setModalState(() {
                              modalFilteredContacts = filteredContactList;
                            });
                          });
                        },
                        icon: Icon(
                          Icons.refresh,
                          color: Color(0xFF57A1FF),
                          size: 20,
                        ),
                        tooltip: 'Refresh Contacts',
                      ),
                    ],
                  ),
                ),

                // Search bar
                Container(
                  height: 45,
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
                    controller: modalSearchController,
                    style: const TextStyle(color: Color(0xFFE8E7EA)),
                    onChanged: filterModalContacts,
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

                const SizedBox(height: 2),

                // New Group and New Contact options
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                  child: Column(
                    children: [
                      _buildOptionItem(
                        iconImage: 'group.png',
                        title: 'New Group',
                        color: const Color(0xFF57A1FF),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        height: 0.5,
                        color: Color(0xFF2B2A30),
                      ),
                      const SizedBox(height: 2),
                      _buildOptionItem(
                        iconImage: 'person-add.png',
                        title: 'New Contact',
                        color: const Color(0xFF3498DB),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 4),

                // Recently Contacted header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Recently Contacted',
                    style: TextStyle(
                      color: Color(0xFF82808F),
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),

                const SizedBox(height: 4),

                // Contact list with custom alphabet scroll (silent loading like WhatsApp)
                Expanded(
                  child: contactList.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.contacts,
                                color: Color(0xFF82808F),
                                size: 48,
                              ),
                              SizedBox(height: 16),
                              Text(
                                'No contacts found',
                                style: TextStyle(
                                  color: Color(0xFF82808F),
                                  fontSize: 16,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Make sure you have granted contacts permission',
                                style: TextStyle(
                                  color: Color(0xFF82808F),
                                  fontSize: 14,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: () {
                                  _loadDeviceContacts().then((_) {
                                    setModalState(() {
                                      modalFilteredContacts =
                                          filteredContactList;
                                    });
                                  });
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Color(0xFF57A1FF),
                                ),
                                child: Text(
                                  'Load Contacts',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        )
                      : Padding(
                          padding: EdgeInsets.only(bottom: 16),
                          child: AlphabetScrollView(
                            contactList: modalFilteredContacts,
                            onContactTap: (contact) async {
                              modalSearchController.dispose();
                              Navigator.pop(context);

                              // Only create chat if contact is registered on platform
                              if (contact.isRegisteredOnPlatform == true &&
                                  contact.platformUserId != null) {
                                try {
                                  // Create or get existing chat
                                  ChatApiService apiService =
                                      ChatApiService(buildContext: context);

                                  Map<String, dynamic>? chatResponse =
                                      await apiService.createOrGetChat(
                                    type: "PRIVATE",
                                    partnerId: contact.platformUserId,
                                  );

                                  if (chatResponse != null) {
                                    // Parse the response
                                    ChatCreationResponse chatData =
                                        ChatCreationResponse.fromJson(
                                            chatResponse);

                                    // Navigate to chat screen with chat data
                                    routeTo('/chat-screen', data: {
                                      'chatId': chatData.id,
                                      'contact': contact,
                                      'userName':
                                          contact.name ?? 'Unknown User',
                                      'userImage': contact.imagePath,
                                      'phoneNumber': contact.phoneNumber,
                                      'platformUsername':
                                          contact.platformUsername,
                                      'platformUserId': contact.platformUserId,
                                      'chatData':
                                          chatData, // Pass structured chat data
                                      'messages': chatData
                                          .messages, // Pass messages array
                                    });
                                  } else {
                                    // Fallback navigation
                                    routeTo('/chat-screen', data: {
                                      'contact': contact,
                                      'userName':
                                          contact.name ?? 'Unknown User',
                                      'userImage': contact.imagePath,
                                      'phoneNumber': contact.phoneNumber,
                                      'platformUsername':
                                          contact.platformUsername,
                                      'platformUserId': contact.platformUserId,
                                    });
                                  }
                                } catch (e) {
                                  print('Error creating chat: $e');
                                  // Fallback navigation
                                  routeTo('/chat-screen', data: {
                                    'contact': contact,
                                    'userName': contact.name ?? 'Unknown User',
                                    'userImage': contact.imagePath,
                                    'phoneNumber': contact.phoneNumber,
                                    'platformUsername':
                                        contact.platformUsername,
                                    'platformUserId': contact.platformUserId,
                                  });
                                }
                              } else {
                                // For non-registered contacts, show invite dialog
                                _showInviteDialog(context, contact);
                              }
                            },
                            onInviteTap: (contact) {
                              // Handle invite functionality
                              _showInviteDialog(context, contact);
                            },
                          ),
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildOptionItem({
    required String iconImage,
    required String title,
    required Color color,
  }) {
    return GestureDetector(
      onTap: () {
        // Handle option tap
        HapticFeedback.lightImpact();
        if (title == 'New Group') {
          // Handle new group creation
          Navigator.pop(context);
          // Add your new group logic here
        } else if (title == 'New Contact') {
          // Handle new contact creation
          Navigator.pop(context);
          // Add your new contact logic here
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Image.asset(
                  iconImage,
                  width: 16,
                  height: 16,
                  color: Color(0xFF57A1FF),
                ).localAsset(),
              ),
            ),
            const SizedBox(width: 16),
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFF57A1FF),
                fontSize: 16,
                fontWeight: FontWeight.w300,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatItem({
    required Chat chat,
    bool isLastItem = false, // To control whether to show line demarcation
  }) {
    final name = chat.name;
    final message = chat.lastMessage?.text ?? chat.lastMessage?.caption ?? '';
    final time = formatMessageTime(chat.lastMessage?.createdAt) ?? '';
    final isTyping = chat.typingUsers.isNotEmpty;

    final typingMessage = isTyping
        ? (chat.typingUsers.length == 1
            ? 'Typing...'
            : '${chat.typingUsers.length} are typing')
        : null;

    print("chat.typingUsers: ${chat.typingUsers}");
    final isVerified = false; // You can add verification logic later
    final unReadCount = chat.unreadCount ;
    final hasUnread = unReadCount > 0; // You can add unread logic later
    
    final isOnline = chat.partner?.status == "online";
    final imagePath = getChatAvatar(
        chat, getEnv("API_BASE_URL")); // Use avatar based on username

    return Column(
      children: [
        GestureDetector(
          onTap: () {
            // Navigate to chat screen with existing chat data
            routeTo(ChatScreenPage.path, data: {
              'chatId': chat.id,
              'userName': name,
              "description": chat.description,
              'userImage': imagePath,
              'isOnline': isOnline,
              'isVerified': isVerified,
              'partnerId': chat.partner?.id,
              'partnerUsername': chat.partner?.username,
              'existingChat': true, // Indicate this is an existing chat
            });
          },
          child: Container(
            padding: EdgeInsets.fromLTRB(16, 18, 16, 8),
            child: Row(
              children: [
                // Avatar with online indicator
                Stack(
                  children: [
                    GestureDetector(
                      onTap: () {
                        // Navigate to profile details page
                        routeTo(ProfileDetailsPage.path, data: {
                          'partner': chat.partner,
                          "isGroup": chat.type == 'CHANNEL',
                          "chatId": chat.id,
                          'userId': chat.partner?.id,
                          'userName': name,
                          'userImage': imagePath,
                          'isOnline': isOnline,
                          'isVerified': isVerified,
                          'description': chat.description,
                        });
                      },
                      child: Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.grey.shade700, // Placeholder background
                        ),
                        child: imagePath != null
                            ? ClipOval(
                                child: Image.network(
                                  imagePath,
                                  width: 54,
                                  height: 54,
                                  fit: BoxFit.cover,
                                ),
                              )
                            : Icon(
                                Icons.person,
                                color: Colors.grey.shade500,
                                size: 24,
                              ),
                      ),
                    ),
                    if (isOnline)
                      Positioned(
                        right: 2,
                        bottom: 2,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: const Color(
                                0xFF2ECC71), // Green online indicator
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Color(0xFF1C212C),
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),

                // Message content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              style: const TextStyle(
                                  color: Color(0xFFE8E7EA),
                                  letterSpacing: 0.5,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isVerified) ...[
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.verified,
                              color: Color(0xFF3498DB),
                              size: 16,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (chat.lastMessage != null &&
                              !isTyping &&
                              chat.lastMessage!.senderId == _currentUserId)
                            Icon(
                              chat.lastMessage!.isRead == true
                                  ? Icons.done_all
                                  : Icons.check,
                              size: 16,
                              color: chat.lastMessage!.isRead == true
                                  ? Color(0xFF57A1FF)
                                  : Colors.grey.shade500,
                            ),
                          if (chat.lastMessage != null) SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              isTyping && typingMessage != null
                                  ? typingMessage
                                  : message,
                              style: TextStyle(
                                color: isTyping
                                    ? Color(0xFF57A1FF)
                                    : Colors.grey.shade400,
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                fontStyle: isTyping
                                    ? FontStyle.italic
                                    : FontStyle.normal,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Time and unread indicator
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Text(
                      time,
                      style: TextStyle(
                        color: Color(0xff9D9C9C),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (hasUnread)
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [Color(0xFF57A1FF), Color(0xFF3B69C6)]),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            unReadCount.toString(), // Your text here
                            style: TextStyle(
                              color: Colors.white,
                              fontSize:
                                  12, // Small font size to fit in 12x12 container
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        // Faint line demarcation (only if not the last item)
        if (!isLastItem)
          Container(
            margin:
                const EdgeInsets.only(left: 76), // Align with message content
            height: 0.5,
            color: Colors.grey.shade800.withOpacity(0.3), // Very faint line
          ),
      ],
    );
  }

  @override
  Widget view(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F131B),
      appBar: PreferredSize(
        preferredSize:
            const Size.fromHeight(140), // Increased height for search bar
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: AppBar(
              backgroundColor: const Color(0xFF1C212C),
              elevation: 3,
              automaticallyImplyLeading: false, // Remove default back button
              flexibleSpace: SafeArea(
                child: Column(
                  children: [
                    // Top row with logo, title, and action buttons
                    Container(
                      height: 60,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          SizedBox(
                            height: 10,
                          ),
                          // Top row - Logo centered
                          // Container(
                          //   height: 10,
                          //   alignment: Alignment.topLeft,
                          //   child: Container(
                          //     width: 50,
                          //     height: 13,
                          //     child: Image.asset(
                          //       'stillurlogo.png',
                          //       width: 50,
                          //       height: 13,
                          //     ).localAsset(),
                          //   ),
                          // ),

                          // Bottom row - Edit, Chats, Icons
                          Container(
                            height: 30,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // Left - Edit
                                Text(
                                  'Edit',
                                  style: TextStyle(
                                    color: Color(0xFF3498DB),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),

                                // Center - Chats
                                Text(
                                  'Chats',
                                  style: TextStyle(
                                    color: Color(0xFFE8E7EA),
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),

                                // Right - Action buttons (closer together)
                                Row(
                                  children: [
                                    Container(
                                      width: 18,
                                      height: 18,
                                      decoration: BoxDecoration(
                                        color: Colors.transparent,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: IconButton(
                                        icon: Container(
                                          width: 20,
                                          height: 20,
                                          child: Image.asset(
                                            'add-a-photo.png',
                                            width: 20,
                                            height: 20,
                                            color: Color(0xFFE8E7EA),
                                          ).localAsset(),
                                        ),
                                        onPressed: () {},
                                        padding: EdgeInsets.zero,
                                      ),
                                    ),
                                    const SizedBox(
                                        width: 8), // Much closer spacing

                                    Container(
                                      width: 20,
                                      height: 20,
                                      decoration: BoxDecoration(
                                        color: Color.lerp(Color(0xffD0DBFF),
                                                Color(0xff5B67D1), 0.5)!
                                            .withValues(alpha: 0.5),
                                        borderRadius: BorderRadius.circular(
                                            3), // 3px border radius
                                      ),
                                      child: Center(
                                        // Center the icon within the container
                                        child: SvgPicture.asset(
                                          'public/images/plus_icon.svg',
                                          width: 11,
                                          height: 11,
                                          colorFilter: ColorFilter.mode(
                                            Color(0xffffffff), // White color
                                            BlendMode.srcIn,
                                          ),
                                        ),
                                      ),
                                    ).onTap(() {
                                      _showNewChatBottomSheet(context);
                                    })
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      // Align with message content
                      height: 0.5,

                      color: Color(0xFF2B2A30), // Very faint line
                    ),
                    // Search bar
                    SizedBox(
                      height: 10,
                    ),
                    Container(
                      height: 65,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F131B),
                          borderRadius:
                              BorderRadius.circular(5.0), // 5px border radius

                          // borderRadius: BorderRadius.circular(12),
                        ),
                        child: TextField(
                          controller: searchController,
                          style: const TextStyle(color: Color(0xFFE8E7EA)),
                          onChanged: _onSearchChanged,
                          decoration: InputDecoration(
                            hintText: 'Search users...',
                            hintStyle: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 12,
                            ),
                            prefixIcon: Icon(
                              Icons.search,
                              color: Colors.grey.shade500,
                              size: 16,
                            ),
                            suffixIcon: searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: Icon(
                                      Icons.clear,
                                      color: Colors.grey.shade500,
                                      size: 16,
                                    ),
                                    onPressed: () {
                                      searchController.clear();
                                      _onSearchChanged('');
                                    },
                                  )
                                : Image.asset(
                                    'public/images/suffix_icon.png',
                                    width: 12,
                                    height: 12,
                                    color: const Color(0xffE8E7EA),
                                  ),

                            // SvgPicture.asset(
                            //   'public/images/suffix_icon.svg',
                            //   width: 12, // optional: set desired size
                            //   height: 12,
                            //   alignment: Alignment.center,
                            //   colorFilter: ColorFilter.mode(
                            //     Color(0xffE8E7EA),
                            //     BlendMode.srcIn,
                            //   ), // optional: set desired size
                            // ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 0,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // Chat list with pull-to-refresh
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _loadRecentChats,
                  backgroundColor: Color(0xFF1B1C1D),
                  color: Color(0xFF3498DB),
                  child: chatList.isEmpty
                      ? ListView(
                          // Wrap in ListView to enable pull-to-refresh on empty state
                          children: [
                            Container(
                              height: MediaQuery.of(context).size.height - 200,
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.chat_bubble_outline,
                                      color: Color(0xFF82808F),
                                      size: 48,
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      'No chats yet',
                                      style: TextStyle(
                                        color: Color(0xFF82808F),
                                        fontSize: 16,
                                      ),
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      'Start a conversation with your contacts',
                                      style: TextStyle(
                                        color: Color(0xFF82808F),
                                        fontSize: 14,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          itemCount: chatList.length,
                          itemBuilder: (context, index) {
                            final chat = chatList[index];
                            final isLastItem = index == chatList.length - 1;

                            return _buildChatItem(
                              chat: chat,
                              isLastItem: isLastItem,
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
          // Search results dropdown overlay
          if (showSearchResults)
            Positioned(
              top: 0,
              left: 16,
              right: 16,
              child: Container(
                margin: EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  color: Color(0xFF1B1C1D),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Color(0xFF2B2A30),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 8,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isSearching)
                      // Show nothing while searching (like WhatsApp)
                      Container()
                    else if (searchResults.isEmpty &&
                        searchController.text.isNotEmpty)
                      Container(
                        padding: EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Text(
                              'No users found',
                              style: TextStyle(
                                color: Color(0xFF82808F),
                                fontSize: 14,
                              ),
                            ),
                            if (recentSearches.isNotEmpty) ...[
                              SizedBox(height: 12),
                              Text(
                                'Recent searches:',
                                style: TextStyle(
                                  color: Color(0xFF82808F),
                                  fontSize: 12,
                                ),
                              ),
                              SizedBox(height: 8),
                              ...recentSearches
                                  .map((search) => InkWell(
                                        onTap: () {
                                          searchController.text = search;
                                          _onSearchChanged(search);
                                        },
                                        child: Container(
                                          padding: EdgeInsets.symmetric(
                                              vertical: 8, horizontal: 12),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.history,
                                                color: Color(0xFF82808F),
                                                size: 16,
                                              ),
                                              SizedBox(width: 8),
                                              Text(
                                                search,
                                                style: TextStyle(
                                                  color: Color(0xFFE8E7EA),
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ))
                                  .toList(),
                            ],
                          ],
                        ),
                      )
                    else
                      ...searchResults
                          .map((user) => _buildSearchResultItem(user))
                          .toList(),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
