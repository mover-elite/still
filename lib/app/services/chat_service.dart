import 'dart:async';
import 'package:nylo_framework/nylo_framework.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '/app/models/chat.dart';
import '/app/models/message.dart';
import '/app/networking/websocket_service.dart';
import '/app/networking/chat_api_service.dart';

class ChatService {
  // Singleton pattern implementation
  static final ChatService _instance = ChatService._internal();
  factory ChatService() => _instance;

  ChatService._internal();

  // Private properties
  final Map<int, Chat> _chats = {};
  final Map<int, List<Message>> _chatMessages = {};
  final Map<int, bool> _hasLoadInitialMessages = {};
  // Track seen message IDs per chat to prevent duplicates
  final Map<int, Set<int>> _seenMessageIds = {};
  final Set<int> _activeChatScreens = {}; // Track which chats have active screens
  final StreamController<List<Chat>> _chatListController =
      StreamController<List<Chat>>.broadcast();

  final StreamController<Chat> _chatController =
      StreamController<Chat>.broadcast();

  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  bool _isInitialized = false;
  IO.Socket? _socket;

  // Getters
  Stream<List<Chat>> get chatListStream => _chatListController.stream;
  Stream<Chat> get chatStream => _chatController.stream;

  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  bool get isInitialized => _isInitialized;

  /// Register a chat screen as active to prevent message duplication
  void registerActiveChatScreen(int chatId) {
    _activeChatScreens.add(chatId);
    print('📱 Registered active chat screen for chat $chatId');
  }

  /// Unregister a chat screen when it's no longer active
  void unregisterActiveChatScreen(int chatId) {
    _activeChatScreens.remove(chatId);
    print('📱 Unregistered active chat screen for chat $chatId');
  }

  /// Private initialization method called in constructor
  Future<void> initialize() async {
    print("Initializing ChatService...");
    if (_isInitialized) return;

    try {
      // Initialize WebSocket connection
      final apiService = ChatApiService();
      final chatListResponse = await apiService.getChatList();
      for (final chat in chatListResponse!.chats) {
        _chats[chat.id] = chat;
      }
      print("Gotten chat list with ${_chats.length} chats");
      await WebSocketService().initializeConnection();

      // Listen to WebSocket messages
      WebSocketService()
          .notificationStream
          .listen(_handleWebSocketNotification);
      WebSocketService().messageStream.listen(_handleWebSocketMessage);
      

      _isInitialized = true;
      print('✅ ChatService initialized automatically');
    } catch (e) {
      print('❌ Error initializing ChatService: $e');
    }
  }


  Future<void> updateChatAvatarImage(int chatId, String imagePath) async {
    try {
      await ChatApiService().uploadGroupAvatarImage(imagePath, chatId);
    final updatedChat = await ChatApiService().getChatDetails(chatId: chatId);
    if (updatedChat != null) {
      _chats[chatId] = updatedChat;
      _chatController.add(updatedChat);
      _chatListController.add(_chats.values.toList());
    }
      print('✅ Chat avatar updated successfully for chat $chatId');
    } catch (e) {
      print('❌ Error updating chat avatar: $e');
      rethrow;
    }
  }
  
  /// Load chat list from API
  Future<List<Chat>> loadChatList() async {
    try {
      final chats = _chats.values.toList();
      print("Loaded ${chats} chats");

      chats.sort((a, b) {
        final aTime =
            a.lastMessage?.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime =
            b.lastMessage?.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });
      // print("Loaded ${chats.length} chats");
      return chats;
    } catch (e) {
      return [];
    }
  }

  /// Get chat details by ID
  Future<Chat?> getChatDetails(int chatId) async {
    try {
      // Check cache first
      if (_chats.containsKey(chatId)) {
        return _chats[chatId];
      }

      // Fetch from API
      final apiService = ChatApiService();
      final chat = await apiService.getChatDetails(chatId: chatId);

      if (chat != null) {
        _chats[chatId] = chat;
        return chat;
      }

      return null;
    } catch (e) {
      print('❌ Error getting chat details: $e');
      return null;
    }
  }

  /// Get messages for a specific chat
  Future<List<Message>> getChatMessages(int chatId) async {
    // Check if initial messages have been loaded for this chat
    if (_hasLoadInitialMessages[chatId] != true) {
      // Fetch initial messages from API
      final apiService = ChatApiService();
      final messagesResponse =
          await apiService.getChatMessages(chatId: chatId, limit: 50);

      if (messagesResponse?.messages.isNotEmpty == true) {
        // Initialize caches
        _chatMessages.putIfAbsent(chatId, () => []);
        _seenMessageIds.putIfAbsent(chatId, () => <int>{});

        // Filter out duplicates by ID
        final existingIds = _seenMessageIds[chatId]!;
        final unique = messagesResponse!.messages
            .where((m) => !existingIds.contains(m.id))
            .toList();

        // Insert fetched messages at the start of the list
        if (unique.isNotEmpty) {
          _chatMessages[chatId]!.insertAll(0, unique);
          existingIds.addAll(unique.map((m) => m.id));
        }
      } else if (!_chatMessages.containsKey(chatId)) {
        _chatMessages[chatId] = [];
      }
      _hasLoadInitialMessages[chatId] = true;
    }
    return _chatMessages[chatId] ?? [];
  }

  /// Load previous messages for a chat given the last message ID
  Future<List<Message>> loadPreviousMessages(
      int chatId, int lastMessageId) async {
    try {
      final apiService = ChatApiService();
      final messagesResponse = await apiService.getChatMessages(
          chatId: chatId, limit: 20, messageId: lastMessageId);

      if (messagesResponse?.messages.isNotEmpty == true) {
        _chatMessages.putIfAbsent(chatId, () => []);
        _seenMessageIds.putIfAbsent(chatId, () => <int>{});

        // Filter out duplicates by ID
        final existingIds = _seenMessageIds[chatId]!;
        final unique = messagesResponse!.messages
            .where((m) => !existingIds.contains(m.id))
            .toList();

        // Insert fetched messages at the start of the existing list
        if (unique.isNotEmpty) {
          _chatMessages[chatId]!.insertAll(0, unique);
          existingIds.addAll(unique.map((m) => m.id));
        }

        return messagesResponse.messages;
      }

      return [];
    } catch (e) {
      print('❌ Error loading previous messages: $e');
      return [];
    }
  }

  /// Add message to chat
  void addMessage(int chatId, Message message) {
    _chatMessages.putIfAbsent(chatId, () => []);
    _seenMessageIds.putIfAbsent(chatId, () => <int>{});
    // Skip if we've already seen this message ID
    if (_seenMessageIds[chatId]!.contains(message.id) ||
        _chatMessages[chatId]!.any((m) => m.id == message.id)) {
      return;
    }
    _chatMessages[chatId]!.add(message);
    _seenMessageIds[chatId]!.add(message.id);

    // Update the chat list for last message display
    updateChatListWithMessage(chatId, message);
  }

  /// Update chat list with new message (used for last message display)
  void updateChatListWithMessage(int chatId, Message message, {bool incrementUnread = true}) {
    // Update last message in chat
    if (_chats.containsKey(chatId)) {
      final chat = _chats[chatId]!;
      // Only increment unread if requested and this isn't the same as last
      final isSameLast = (chat.lastMessage?.id == message.id);
      chat.lastMessage = message;
      chat.lastMessageTime = message.createdAt;
      if (incrementUnread && !isSameLast) {
        chat.unreadCount += 1;
      }

      loadChatList().then((sortedChats) {
        _chatListController.add(sortedChats);
      });
    }
  }

  /// Send message through API
  Future<void> sendMessage(String chatId, String message) async {
    try {
      // Create message data for sending
      final messageData = {
        'chat_id': chatId,
        'message': message,
        'timestamp': DateTime.now().toIso8601String(),
      };

      // Send through API
      // await apiService.sendMessage(chatId: int.parse(chatId), message: message);

      // Also emit through WebSocket for real-time delivery
      _socket?.emit('sendMessage', messageData);

      print('✅ Message sent successfully to chat $chatId');
    } catch (e) {
      print('❌ Error sending message: $e');
      rethrow;
    }
  }

  /// Mark messages as read
  Future<void> markMessagesAsRead(List<int> messageIds) async {
    try {
      await WebSocketService().sendReadReceipt(messageIds);

      // Update local messages
      for (final chatMessages in _chatMessages.values) {
        for (final message in chatMessages) {
          if (messageIds.contains(message.id)) {
            message.isRead = true;
          }
        }
      }

      _messageController.add({
        'type': 'messages_read',
        'messageIds': messageIds,
      });
    } catch (e) {
      print('❌ Error marking messages as read: $e');
    }
  }

  /// Handle WebSocket messages
  void _handleWebSocketMessage(Map<String, dynamic> messageData) {
    try {
      final message = Message.fromJson(messageData);

      // Initialize caches
      _chatMessages.putIfAbsent(message.chatId, () => []);
      _seenMessageIds.putIfAbsent(message.chatId, () => <int>{});

      // De-duplication: if we've already seen this message ID, ignore entirely
      if (_seenMessageIds[message.chatId]!.contains(message.id) ||
          _chatMessages[message.chatId]!.any((m) => m.id == message.id)) {
        return;
      }

      // Check if this chat has an active screen that will handle the message
      if (_activeChatScreens.contains(message.chatId)) {
        // Update last message but do not increment unread
        updateChatListWithMessage(message.chatId, message, incrementUnread: false);
        print('📨 Chat list updated for chat ${message.chatId} - message handled by active chat screen');
        return;
      }

      // Add to local message cache only for chats without active screens
      _chatMessages[message.chatId]!.add(message);
      _seenMessageIds[message.chatId]!.add(message.id);

      // Update chat list and increment unread normally
      updateChatListWithMessage(message.chatId, message, incrementUnread: true);

      print('📨 Received message for chat ${message.chatId}');
    } catch (e) {
      print('❌ Error handling WebSocket message: $e');
    }
  }

  /// Handle WebSocket notifications
  void _handleWebSocketNotification(Map<String, dynamic> notificationData) {
    try {
      final action = notificationData['action'];

      switch (action) {
        case 'message:delivered':
          _handleMessageDelivered(notificationData);
          break;
        case 'message:read':
          _handleMessageRead(notificationData);
          break;
        case 'user:connected':
        case 'user:disconnected':
          _handleUserStatusChange(notificationData);
          break;
        case 'typing:start':
        case 'typing:stop':
          _handleTypingStatus(notificationData);
          break;
        case 'chat:new':
          _handleNewChat(notificationData);
          break;

        case "join:call":
          _handleJoinCall(notificationData);
          break;

        default:
          print('🔔 Unhandled notification: $action');
      }
    } catch (e) {
      print('❌ Error handling WebSocket notification: $e');
    }
  }

  void _handleNewChat(Map<String, dynamic> data) async {
    try {
      final int chatId = data['chatId'];
      final apiService = ChatApiService();
      final newChat = await apiService.getChatDetails(chatId: chatId);

      if (newChat != null) {
        _chats[newChat.id] = newChat;
        _chatListController.add(_chats.values.toList());
      }
    } catch (e) {
      print('❌ Error handling new chat: $e');
    }
  }

  /// Handle incoming call notification
  void _handleJoinCall(Map<String, dynamic> data) async {
    try {
      final int callerId = data['callerId'];
      final int chatId = data['chatId'];
      final String type = data['type'];
      print('📞 Incoming call from user $callerId in chat $chatId');
      final userData = await Auth.data();
      final int currentUserId = userData['id'];
      print('Current user ID: $currentUserId');

      if (callerId == currentUserId) {
        // Ignore if the caller is the current user
        return;
      }
      // Get chat details to show caller info
      final chat = await getChatDetails(chatId);

      if (chat != null) {
        if (type == "audio") {
          await routeTo(
            "/receive-call-screen",
            data: {
              'isGroup': false,
              'partner': {
                'username': chat.partner?.username ?? 'Unknown',
                'avatar': chat.partner?.avatar ?? 'default_avatar.png',
              },
              'chatId': chatId,
              'callerId': callerId,
              'initiateCall': false, // This indicates joining, not initiating
              'isJoining': true, // Flag to indicate this is an incoming call
            },
          );
        } else {
          await routeTo(
            "/receive-video-call-screen",
            data: {
              'isGroup': false,
              'partner': {
                'username': chat.partner?.username ?? 'Unknown',
                'avatar': chat.partner?.avatar ?? 'default_avatar.png',
              },
              'chatId': chatId,
              'callerId': callerId,
              'initiateCall': false, // This indicates joining, not initiating
              'isJoining': true, // Flag to indicate this is an incoming call
            },
          );
        }
      }
    } catch (e) {
      print('❌ Error handling join call: $e');
    }
  }

  /// Handle message delivered notification
  void _handleMessageDelivered(Map<String, dynamic> data) {
    try {
      final List<int> ids = List<int>.from(data['ids']);

      // Update local messages
      for (final chatMessages in _chatMessages.values) {
        for (final message in chatMessages) {
          if (ids.contains(message.id)) {
            message.isDelivered = true;
          }
        }
      }

      _messageController.add({
        'type': 'messages_delivered',
        'messageIds': ids,
      });
    } catch (e) {
      print('❌ Error handling message delivered: $e');
    }
  }

  /// Handle message read notification
  void _handleMessageRead(Map<String, dynamic> data) {
    try {
      final List<int> ids = List<int>.from(data['ids']);

      // Update local messages
      for (final chatMessages in _chatMessages.values) {
        for (final message in chatMessages) {
          if (ids.contains(message.id)) {
            message.isRead = true;

            final Chat? chat = _chats[message.chatId];
            if (chat != null) {
              if (chat.lastMessage?.id == message.id) {
                chat.lastMessage!.isRead = true;
              }

              _chatController.add(chat);
              _chatListController.add(_chats.values.toList());
            }
          }
        }
      }

      _messageController.add({
        'type': 'messages_read',
        'messageIds': ids,
      });
    } catch (e) {
      print('❌ Error handling message read: $e');
    }
  }

  /// Handle user status change
  void _handleUserStatusChange(Map<String, dynamic> data) async {
    final userData = await Auth.data();
    final int currentUserId = userData['id'];

    final int userId = data['userId'];
    final String action = data['action'];

    if (userId != currentUserId) {
      for (final chat in _chats.values) {
        if (chat.partner?.id == userId) {
          chat.partner?.status =
              action == 'user:connected' ? "online" : "offline";
          _chatListController.add(_chats.values.toList());
          break;
        }
      }
    }
  }

  void _handleTypingStatus(Map<String, dynamic> data) async {
    final userData = await Auth.data();
    final int currentUserId = userData['id'];
    final int userId = data['userId'];
    if (userId == currentUserId) return;

    final int chatId = data['chatId'];
    final bool isTyping = data['action'] == 'typing:start';
    final chat = _chats[chatId];

    if (chat == null) return;

    if (isTyping) {
      chat.typingUsers.add(userId);
    } else {
      chat.typingUsers.remove(userId);
    }

    _chatController.add(chat);
    _chatListController.add(_chats.values.toList());
  }

  /// Clear chat cache and reset all user-specific data
  void clearCache() {
    print('🧹 Clearing ChatService cache...');
    
    // Clear all cached data
    _chats.clear();
    _chatMessages.clear();
    _hasLoadInitialMessages.clear();
    _activeChatScreens.clear();
    
    // Reset initialization flag
    _isInitialized = false;
    
    // Notify all listeners with empty data
    _chatListController.add([]);
    
    print('✅ ChatService cache cleared');
  }

  /// Comprehensive logout cleanup
  Future<void> logoutCleanup() async {
    print('🔓 Starting ChatService logout cleanup...');
    
    try {
      // Clear all cached data
      clearCache();
      
      // Disconnect WebSocket
      await WebSocketService().disconnect();
      print('✅ WebSocket disconnected');
      
      print('✅ ChatService logout cleanup completed');
    } catch (e) {
      print('❌ Error during ChatService logout cleanup: $e');
      rethrow;
    }
  }

  /// Dispose resources
  void dispose() {
    _chatListController.close();
    _messageController.close();
    clearCache();
    _isInitialized = false;
  }
}
