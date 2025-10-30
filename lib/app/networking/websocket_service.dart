import 'dart:async';
import 'dart:convert';
// import 'dart:io';
import 'package:nylo_framework/nylo_framework.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();
  IO.Socket? _socket;

  // WebSocket? _webSocket;
  String? _currentChatId;
  bool _isConnected = false;
  bool _isConnecting = false;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  final int _maxReconnectAttempts = 5;

  // Stream controllers for different types of messages
  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _notificationController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _chatListController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<bool> _connectionStatusController =
      StreamController<bool>.broadcast();

  // Getters
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  Stream<Map<String, dynamic>> get notificationStream =>
      _notificationController.stream;
  Stream<Map<String, dynamic>> get chatListStream => _chatListController.stream;
  Stream<bool> get connectionStatusStream => _connectionStatusController.stream;
  bool get isConnected => _isConnected;
  String? get currentChatId => _currentChatId;

  /// Initialize Socket.IO connection for general notifications and chat list updates
  Future<void> initializeConnection() async {
    if (_socket != null && _socket!.connected) return;

    _isConnecting = true;
    try {
      Map<String, dynamic>? userData = await Auth.data();
      String? accessToken = userData != null ? userData['accessToken'] : null;

      _socket = IO.io(getEnv('API_BASE_URL'), <String, dynamic>{
        'transports': <String>['websocket'], // Add polling as fallback
        'autoConnect': false,
        'auth': {
          'token': accessToken,
        },
        'timeout': 20000, // 20 second timeout
        'reconnection': true,
        'reconnectionAttempts': 5,
        'reconnectionDelay': 1000,
        'forceNew': true, // Force new connection
        'upgrade': true, // Allow transport upgrade
        'rememberUpgrade': true, // Remember transport preference
      });
      _socket!.connect();

      _socket!.on('connect', (_) async {
        print('Socket.IO connected');
        _isConnected = true;
        _isConnecting = false;
        _reconnectAttempts = 0;
        _connectionStatusController.add(true);
        // await _sendAuthMessage();
      });

      _socket!.on('disconnect', (reason) {
        print('Socket.IO disconnected: $reason');
        _isConnected = false;
        _connectionStatusController.add(false);
        _handleDisconnection();
      });

      _socket!.on('connect_error', (error) {
        print('Socket.IO connection error: $error');
        _isConnected = false;
        _connectionStatusController.add(false);
        _handleError(error);
      });

      _socket!.on('reconnect', (attemptNumber) {
        print('Socket.IO reconnected after $attemptNumber attempts');
        _isConnected = true;
        _connectionStatusController.add(true);
        _reconnectAttempts = 0;
      });

      _socket!.on('reconnect_error', (error) {
        print('Socket.IO reconnection error: $error');
        _handleError(error);
      });

      _socket!.on('message',
          (data) => _handleIncomingMessage('message', jsonEncode(data)));
      _socket!.on('message:new',
          (data) => _handleIncomingMessage('message:new', jsonEncode(data)));
      _socket!.on('message:edit',
          (data) => _handleIncomingMessage('message:edit', jsonEncode(data)));
      _socket!.on('message:delete',
          (data) => _handleIncomingMessage('message:delete', jsonEncode(data)));
      _socket!.on('notification',
          (data) => _handleIncomingMessage('notification', jsonEncode(data)));
      _socket!.on(
          'chat_list_update',
          (data) =>
              _handleIncomingMessage('chat_list_update', jsonEncode(data)));
      _socket!.on('typing',
          (data) => _handleIncomingMessage('typing', jsonEncode(data)));
      _socket!.on('read_receipt',
          (data) => _handleIncomingMessage('read_receipt', jsonEncode(data)));
    } catch (e) {
      _isConnecting = false;
      _handleError(e);
    }
  }

  // 
  Future<void> sendDeleteMessage(int messageID, int chatID) async {
    if (!_isConnected || _socket == null) return;

    try {
      final deleteData = {
        'messageId': messageID,
        'chatId': chatID,
      };

      _socket!.emit('message:delete', deleteData);
      print('Message delete requested: $deleteData');
    } catch (e) {
      print('Error deleting message: $e');
    }
  }

  Future<void> sendEditMessage(int messageID, int chatID, String text) async {
    if (!_isConnected || _socket == null) return;

    try {
      final deleteData = {
        'messageId': messageID,
        'chatId': chatID,
        "text": text,
      };

      _socket!.emit('message:edit', deleteData);
      print('Message edit requested: $deleteData');
    } catch (e) {
      print('Error editing message: $e');
    }
  }
  

  /// Handle incoming messages and route them to appropriate streams
  void _handleIncomingMessage(String type, dynamic data) {
    try {
      final messageData = jsonDecode(data);

      switch (type) {
        case 'message:new':
          print('✅ Received new message: $messageData');
          _messageController.add(messageData);
          break;
        case 'message:edit':
          print('Editing message: $messageData');
          _messageController.add({'action': 'edit', ...messageData});
          break;
        case 'message:delete':
          print('Deleting message: $messageData');
          _messageController.add({'action': 'delete', ...messageData});
          break;
        case 'notification':
          _notificationController.add(messageData);
          break;
        case 'chat_list_update':
          _chatListController.add(messageData);
          break;

        default:
          print('Unknown message type: $type');
      }
    } catch (e) {
      print('Error parsing incoming message: $e');
    }
  }

  /// Send a message to the current chat
  Future<void> sendMessage(String message, int chatId, int? referenceId) async {
    if (!_isConnected || _socket == null) {
      print('Socket.IO not connected');
      return;
    }

    try {
      final messageData = {
        'type': 'TEXT',
        'text': message,
        'chatId': chatId,
        if (referenceId != null) 'referenceId': referenceId,
      };

      print('Sending message: $messageData');
      final jsonString = jsonEncode(messageData);
      _socket!.emit('message:send', jsonString);
    } catch (e) {
      print('Error sending message: $e');
    }
  }

  /// Send typing indicator
  Future<void> sendTypingIndicator(bool isTyping, int chatId) async {
    if (!_isConnected || _socket == null) return;

    try {
      final typingData = {
        'chatId': chatId,
      };

      final event = isTyping ? 'typing:start' : 'typing:stop';
      print('🚀 EMITTING TYPING EVENT: $event');
      print('📤 Typing data: $typingData');
      print('📤 Timestamp: ${DateTime.now().toIso8601String()}');
      _socket!.emit(event, typingData);
      print(
          '✅ TYPING EVENT SENT: $event at ${DateTime.now().toIso8601String()}');
    } catch (e) {
      print('Error sending typing indicator: $e');
    }
  }

  /// Send read receipt
  Future<void> sendReadReceipt(int messageId, int chatId) async {
    if (!_isConnected || _socket == null) return;

    try {
      _socket!.emit('message:read', {'messageId': messageId, 'chatId': chatId});
    } catch (e) {
      print('Error sending read receipt: $e');
    }
  }

  Future<void> sendDeclineCall(int chatID, String type ) async {
    if (!_isConnected || _socket == null) return;

    try {
      final declineData = {
        'chatId': chatID,
        "type": type
      };

      _socket!.emit('decline:call', declineData);
      print('Call declined: $declineData');
    } catch (e) {
      print('Error declining call: $e');
    }
  }

  Future<void> sendAcceptCall(int chatID) async {
    if (!_isConnected || _socket == null) return;

    try {
      final acceptData = {
        'chatId': chatID,
      };

      _socket!.emit('accept:call', acceptData);
      print('Call accepted: $acceptData');
    } catch (e) {
      print('Error accepting call: $e');
    }
  }

  /// Request chat list updates
  Future<void> requestChatList() async {
    if (!_isConnected || _socket == null) return;

    try {
      final requestData = {
        'type': 'get_chat_list',
      };

      _socket!.emit('get_chat_list', requestData);
    } catch (e) {
      print('Error requesting chat list: $e');
    }
  }

  /// Handle WebSocket errors
  void _handleError(dynamic error) {
    print('WebSocket error: $error');
    _isConnected = false;
    _connectionStatusController.add(false);

    // Attempt to reconnect
    if (_reconnectAttempts < _maxReconnectAttempts) {
      _scheduleReconnect();
    }
  }

  /// Handle WebSocket disconnection
  void _handleDisconnection() {
    print('WebSocket disconnected');
    _isConnected = false;
    _connectionStatusController.add(false);

    // Attempt to reconnect
    if (_reconnectAttempts < _maxReconnectAttempts) {
      _scheduleReconnect();
    }
  }

  /// Schedule reconnection attempt
  void _scheduleReconnect() {
    _reconnectAttempts++;
    final delay =
        Duration(seconds: _reconnectAttempts * 2); // Exponential backoff

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      print('Attempting to reconnect... (attempt $_reconnectAttempts)');
      initializeConnection();
    });
  }

  /// Disconnect from current chat
  Future<void> _disconnectFromChat() async {
    if (_socket != null && _currentChatId != null) {
      try {
        final disconnectData = {
          'type': 'leave_chat',
          'chatId': _currentChatId,
        };
        _socket!.emit('leave_chat', disconnectData);
      } catch (e) {
        print('Error disconnecting from chat: $e');
      }
    }
    _currentChatId = null;
    _isConnected = false;
  }

  /// Disconnect completely
  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    await _disconnectFromChat();
    _socket?.disconnect();
    _socket = null;
    _isConnected = false;
    _connectionStatusController.add(false);
    print('Socket.IO disconnected completely');
  }

  /// Dispose resources
  void dispose() {
    print("Disposing WebSocketService");
    disconnect();
    _messageController.close();
    _notificationController.close();
    _chatListController.close();
    _connectionStatusController.close();
  }
}
