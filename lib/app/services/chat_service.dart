import 'dart:async';
import 'package:nylo_framework/nylo_framework.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '/app/models/chat.dart';
import '/app/models/message.dart';
import '/app/networking/websocket_service.dart';
import '/app/networking/chat_api_service.dart';
import '/app/services/notification_service.dart';

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
    if (_isInitialized) {
      print('ChatService already initialized, skipping...');
      return;
    }

    // Set flag immediately to prevent duplicate initialization
    _isInitialized = true;

    try {
      // Initialize WebSocket connection
      final apiService = ChatApiService();
      final chatListResponse = await apiService.getChatList();
      for (final chat in chatListResponse!.chats) {
        _chats[chat.id] = chat;
      }
      print("Gotten chat list with ${_chats.length} chats");
      
      // Emit initial chat list to stream so listeners get the data
      _chatListController.add(_chats.values.toList());
      
      await WebSocketService().initializeConnection();

      // Listen to WebSocket messages (only once since _isInitialized prevents re-entry)
      print("Listening to websocket notifications");
      WebSocketService()
          .notificationStream
          .listen(_handleWebSocketNotification);
      WebSocketService().messageStream.listen(_handleWebSocketMessage);
      
      // Listen to call notification actions
      NotificationService.instance.onCallAction.listen(_handleCallAction);
      
      print('✅ ChatService initialized automatically');
    } catch (e) {
      print('❌ Error initializing ChatService: $e');
      // Reset flag on error so initialization can be retried
      _isInitialized = false;
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
      // print("Loaded ${chats} chats");

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

  /// Refresh chat details from API and broadcast update
  Future<Chat?> refreshChatDetails(int chatId) async {
    try {
      // Force fetch from API
      final apiService = ChatApiService();
      final chat = await apiService.getChatDetails(chatId: chatId);

      if (chat != null) {
        _chats[chatId] = chat;
        // Broadcast the update to listeners
        _chatController.add(chat);
        return chat;
      }

      return null;
    } catch (e) {
      print('❌ Error refreshing chat details: $e');
      return null;
    }
  }

  /// Get messages for a specific chat
  Future<List<Message>> getChatMessages(int chatId) async {
    print('📨 getChatMessages called for chatId: $chatId');
    print('📨 ChatService initialized: $_isInitialized');
    print('📨 Initial messages loaded: ${_hasLoadInitialMessages[chatId] == true}');
    
    // Ensure ChatService is initialized before loading messages
    if (!_isInitialized) {
      print('⚠️ ChatService not initialized in getChatMessages, initializing now...');
      await initialize();
    }
    
    // Check if initial messages have been loaded for this chat
    if (_hasLoadInitialMessages[chatId] != true) {
      print('📨 Fetching initial messages from API for chat $chatId...');
      // Fetch initial messages from API
      final apiService = ChatApiService();
      final messagesResponse =
          await apiService.getChatMessages(chatId: chatId, limit: 50);

      if (messagesResponse?.messages.isNotEmpty == true) {
        print('📨 Received ${messagesResponse!.messages.length} messages from API');
        // Initialize caches
        _chatMessages.putIfAbsent(chatId, () => []);
        _seenMessageIds.putIfAbsent(chatId, () => <int>{});

        // Filter out duplicates by ID
        final existingIds = _seenMessageIds[chatId]!;
        print('📨 Existing seen message IDs count: ${existingIds.length}');
        print('📨 Current cached messages count: ${_chatMessages[chatId]!.length}');
        
        final unique = messagesResponse.messages
            .where((m) => !existingIds.contains(m.id))
            .toList();
        
        print('📨 Unique (not seen) messages count: ${unique.length}');

        // Insert fetched messages at the start of the list
        if (unique.isNotEmpty) {
          _chatMessages[chatId]!.insertAll(0, unique);
          existingIds.addAll(unique.map((m) => m.id));
          print('📨 Added ${unique.length} unique messages to cache');
        } else {
          print('⚠️ All ${messagesResponse.messages.length} messages were already seen/cached!');
        }
      } else {
        print('📨 No messages received from API or empty response');
        if (!_chatMessages.containsKey(chatId)) {
          _chatMessages[chatId] = [];
        }
      }
      _hasLoadInitialMessages[chatId] = true;
    } else {
      print('📨 Using cached messages for chat $chatId');
    }
    
    final messages = _chatMessages[chatId] ?? [];
    print('📨 Returning ${messages.length} messages for chat $chatId');
    return messages;
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
  Future<void> markMessagesAsRead(int messageId, int chatId) async {
    try {
      await WebSocketService().sendReadReceipt(messageId, chatId);

      // Update local messages
      for (final chatMessages in _chatMessages.values) {
        for (final message in chatMessages) {
          if (message.id == messageId) {
            message.isRead = true;
          }
        }
      }

      _messageController.add({
        'type': 'messages_read',
        'messageId': messageId,
        'chatId': chatId,
      });
    } catch (e) {
      print('❌ Error marking messages as read: $e');
    }
  }

  /// Handle WebSocket messages
  void _handleWebSocketMessage(Map<String, dynamic> messageData) async {
    try {
      final message = Message.fromJson(messageData);
      
      print('📨 ChatService received message - ID: ${message.id}, chatId: ${message.chatId}, referenceId: ${message.referenceId}');

      // Initialize caches
      _chatMessages.putIfAbsent(message.chatId, () => []);
      _seenMessageIds.putIfAbsent(message.chatId, () => <int>{});

      print('📨 Current seenMessageIds for chat ${message.chatId}: ${_seenMessageIds[message.chatId]}');
      print('📨 Current message count in cache: ${_chatMessages[message.chatId]!.length}');

      // De-duplication: if we've already seen this message ID, ignore entirely
      if (_seenMessageIds[message.chatId]!.contains(message.id) ||
          _chatMessages[message.chatId]!.any((m) => m.id == message.id)) {
        print('📨❌ Duplicate message ignored (already seen ID): ${message.id}');
        return;
      }

      // Get current user ID to check if message is from current user
      final userData = await Auth.data();
      final int currentUserId = userData['id'];
      final bool isMessageFromCurrentUser = (message.sender.id == currentUserId);
      print("Message is from current user: $isMessageFromCurrentUser");
      // Check if this chat has an active screen that will handle the message
      if (_activeChatScreens.contains(message.chatId)) {
        // Update last message but do not increment unread
        updateChatListWithMessage(message.chatId, message, incrementUnread: false);
        print('📨 Chat list updated for chat ${message.chatId} - message handled by active chat screen');
        return;
      }

      // Check if this is an update to a pending message (by referenceId)
      if (message.referenceId != null) {
        final index = _chatMessages[message.chatId]!
            .indexWhere((m) => m.referenceId == message.referenceId);
        if (index != -1) {
          print('📨 Updating pending message with referenceId: ${message.referenceId} -> new ID: ${message.id}');
          // Remove old message ID from seen set if it exists
          final oldMessageId = _chatMessages[message.chatId]![index].id;
          _seenMessageIds[message.chatId]!.remove(oldMessageId);
          
          // Replace the pending message with the confirmed one
          _chatMessages[message.chatId]![index] = message;
          _seenMessageIds[message.chatId]!.add(message.id);
          
          // Update chat list without incrementing unread (message already exists)
          updateChatListWithMessage(message.chatId, message, incrementUnread: false);
          print('📨 Replaced pending message for chat ${message.chatId}');
          return;
        }
      }

      // If app is backgrounded and chat is not active, show a local notification
      final shouldNotify = !NotificationService.instance.isAppInForeground &&
          !_activeChatScreens.contains(message.chatId) &&
          !isMessageFromCurrentUser; // Don't notify for own messages
      if (shouldNotify) {
        final chat = _chats[message.chatId];
        final title = chat?.name ?? 'New message';
        final text = (message.text?.isNotEmpty ?? false)
            ? message.text!
            : (message.caption?.isNotEmpty ?? false)
                ? message.caption!
                : (message.type.toUpperCase());
        NotificationService.instance.showChatMessageNotification(
          chatId: message.chatId,
          title: title,
          body: text,
        );
      }

      // Add to local message cache only for chats without active screens
      _chatMessages[message.chatId]!.add(message);
      _seenMessageIds[message.chatId]!.add(message.id);
      
      print('📨✅ ADDED NEW message to cache - ID: ${message.id}, referenceId: ${message.referenceId}');
      print('📨 New message count in cache: ${_chatMessages[message.chatId]!.length}');
      print('📨 Updated seenMessageIds: ${_seenMessageIds[message.chatId]}');

      // Update chat list and increment unread only if message is NOT from current user
      final shouldIncrementUnread = !isMessageFromCurrentUser;
      updateChatListWithMessage(message.chatId, message, incrementUnread: shouldIncrementUnread);

      print('📨 Received NEW message for chat ${message.chatId} (from current user: $isMessageFromCurrentUser, incrementUnread: $shouldIncrementUnread)');
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
        
        case "call:declined":
        case "call:ended":
          _handleCallEnded(notificationData);
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

  // Track active incoming calls to prevent duplicates
  final Set<String> _activeIncomingCalls = {};

  /// Handle incoming call notification
  void _handleJoinCall(Map<String, dynamic> data) async {
    try {
      
      print("Joining call ☎️: $data");
      final int callerId = data['callerId'];
      final int chatId = data['chatId'];
      final String type = data['type'];
      
      // Create a unique key for this call
      final callKey = '$chatId-$callerId-$type';
      
      // Prevent duplicate call notifications
      if (_activeIncomingCalls.contains(callKey)) {
        print('📞 Ignoring duplicate call notification: $callKey');
        return;
      }
      
      print('📞 Incoming call from user $callerId in chat $chatId');
      final userData = await Auth.data();
      final int currentUserId = userData['id'];
      print('Current user ID: $currentUserId');

      if (callerId == currentUserId) {
        // Ignore if the caller is the current user
        return;
      }
      
      // Mark this call as active
      _activeIncomingCalls.add(callKey);
      
      // Get chat details to show caller info
      final chat = await getChatDetails(chatId);

      if (chat != null) {
        final callData = {
          'isGroup': chat.isGroup,
          'partner': {
            'username': chat.partner?.username ?? 'Unknown',
            'avatar': chat.partner?.avatar ?? 'default_avatar.png',
          },
          "avatar": chat.avatar,
          "name": chat.name,
          "groupName": chat.name,
          'chatId': chatId,
          'callerId': callerId,
          'initiateCall': false, // This indicates joining, not initiating
          'isJoining': true, // Flag to indicate this is an incoming call
        };
        
        // Check if app is in foreground
        if (NotificationService.instance.isAppInForeground) {
          // App is in foreground, show the full-screen call UI
          if (type == "audio") {
            await routeTo("/receive-call-screen", data: callData);
          } else {
            await routeTo("/receive-video-call-screen", data: callData);
          }
          print('📞 Call screen opened for: $callKey (tracking will be cleared on call end)');
        } else {
          // App is in background, show notification with actions
          await NotificationService.instance.showIncomingCallNotification(
            chatId: chatId,
            callerId: callerId,
            callerName: chat.partner?.username ?? 'Unknown',
            callType: type,
          );
          print('📞 Call notification shown for: $callKey');
        }
        
        // DON'T remove from active calls here - keep it to prevent duplicates
        // It will be removed when the call is answered, declined, or times out
      } else {
        // If chat is null, remove from tracking since navigation didn't happen
        _activeIncomingCalls.remove(callKey);
        print('📞 Chat not found, cleared tracking: $callKey');
      }
    } catch (e) {
      print('❌ Error handling join call: $e');
      // Remove from tracking on error since navigation failed
      final callKey = '${data['chatId']}-${data['callerId']}-${data['type']}';
      _activeIncomingCalls.remove(callKey);
    }
  }

  /// Clear call tracking for a specific chat/caller combination
  void clearIncomingCall(int chatId, int callerId, String type) async {
    final callKey = '$chatId-$callerId-$type';
    _activeIncomingCalls.remove(callKey);
    
    // Cancel any active call notification
    await NotificationService.instance.cancelCallNotification(chatId);
    
    print('📞 Cleared incoming call tracking: $callKey');
  }

  /// Handle call ended/declined notification
  void _handleCallEnded(Map<String, dynamic> data) async {
    try {
      final int chatId = data['chatId'];
      final int callerId = data['callerId'] ?? data['userId'];
      final String type = data['type'] ?? 'audio'; // Default to audio if not specified
      print("Data for call ended: $data");
      clearIncomingCall(chatId, callerId, type);
      
      // Cancel any active call notification
      await NotificationService.instance.cancelCallNotification(chatId);
      
      print('📞 Call ended/declined for chat $chatId');
    } catch (e) {
      print('❌ Error handling call ended: $e');
    }
  }

  /// Handle call notification actions (accept/decline from notification)
  void _handleCallAction(Map<String, dynamic> actionData) async {
    try {
      final action = actionData['action'];
      final chatId = actionData['chatId'];
      final callerId = actionData['callerId'];
      final callType = actionData['callType'];
      
      print('📞 Call action received: $action for chat $chatId');
      
      // Cancel the notification
      await NotificationService.instance.cancelCallNotification(chatId);
      
      if (action.toString().startsWith('decline_')) {
        // User declined the call from notification
        print('📞 Declining call from notification');
        clearIncomingCall(chatId, callerId, callType);
        WebSocketService().sendDeclineCall(chatId, callType);
      } else if (action.toString().startsWith('accept_') || action == 'open') {
        // User accepted the call from notification or tapped the notification
        print('📞 Accepting call from notification');
        
        // Get chat details to show caller info
        final chat = await getChatDetails(chatId);
        
        if (chat != null) {
          final callData = {
            'isGroup': false,
            'partner': {
              'username': chat.partner?.username ?? 'Unknown',
              'avatar': chat.partner?.avatar ?? 'default_avatar.png',
            },
            'chatId': chatId,
            'callerId': callerId,
            'initiateCall': false,
            'isJoining': true,
          };
          
          // Navigate to the appropriate call screen
          if (callType == 'audio') {
            await routeTo("/receive-call-screen", data: callData);
          } else {
            await routeTo("/receive-video-call-screen", data: callData);
          }
        }
      }
    } catch (e) {
      print('❌ Error handling call action: $e');
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
  void _handleMessageRead(Map<String, dynamic> data) async {
    try {
      print("Handling message read notification: $data");
      final List<int> ids = List<int>.from(data['ids']);
      final int chatId = data['chatId'];
      final int userId = data['userId'];
      
      // Get current user ID
      final userData = await Auth.data();
      final int currentUserId = userData['id'];

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

      // Reduce unread count if the current user is the one who read the messages
      if (userId == currentUserId && _chats.containsKey(chatId)) {
        final chat = _chats[chatId]!;
        final idsCount = ids.length;
        
        // Reduce unread count by the number of messages read, but not below 0
        chat.unreadCount = (chat.unreadCount - idsCount).clamp(0, chat.unreadCount);
        
        print('📖 Reduced unread count for chat $chatId by $idsCount. New count: ${chat.unreadCount}');
        
        // Broadcast updated chat list
        _chatController.add(chat);
        _chatListController.add(_chats.values.toList());
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
    _seenMessageIds.clear();
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
