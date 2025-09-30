import 'dart:ui';
import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/app/models/message.dart';
import 'package:flutter_svg/svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:nylo_framework/nylo_framework.dart';
import '/app/models/chat.dart';
import '/app/networking/chat_api_service.dart';
import '/app/networking/websocket_service.dart';
import '/resources/pages/video_call_page.dart';
import '/resources/pages/voice_call_page.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import "../../app/utils/chat.dart";
import "/app/services/chat_service.dart";
import 'package:audioplayers/audioplayers.dart';

class ChatScreenPage extends NyStatefulWidget {
  static RouteView path = ("/chat-screen", (_) => ChatScreenPage());

  ChatScreenPage({super.key}) : super(child: () => _ChatScreenPageState());
}

class _ChatScreenPageState extends NyPage<ChatScreenPage>
    with HasApiService<ChatApiService> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _showMediaPicker = false;
  bool _hasText = false;
  XFile? _pickedImage;
  bool _isRecording = false;
  String? _recordedAudioPath;
  late Record _audioRecorder;
  Timer? _recordingTimer;
  int _recordingDuration = 0;

  // Chat data
  Chat? _chat;
  String _userName = 'Ahmad';
  String? _userImage;
  bool _isOnline = false;
  bool _isVerified = false;
  Set<int> _typingUsers = {};

  String? currentDay; // Track current day for day separators
  bool _isShowingFloatingHeader = false; // Control visibility of the floating header
  Timer? _headerVisibilityTimer; // Timer to hide header after period of inactivity

  // WebSocket integration
  StreamSubscription<Map<String, dynamic>>? _wsSubscription;
  StreamSubscription<Map<String, dynamic>>? _notificationSubscription;
  StreamSubscription<Chat>? _chatSubscription;

  bool _isWebSocketConnected = false;

  List<Message> _messages = [];
  int? _currentUserId;
  bool _isLoadingAtTop = false; // Track loading state when at top

  AudioPlayer? _audioPlayer;
  int? _playingMessageId;
  bool _isAudioPlaying = false;
  Duration _audioPosition = Duration.zero;
  Duration _audioDuration = Duration.zero;

  // Message interaction state
  Message? _replyingToMessage;
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFocusNode = FocusNode();
  Set<int> _selectedMessages = {};
  bool _isSelectionMode = false;

  @override
  get init => () async {
        _audioRecorder = Record();
        _messageController.addListener(_onTextChanged);
        _textController.addListener(_onTextChanged);
        _scrollController.addListener(_onScroll);

        ChatService().chatStream.listen((chat) {
          if (!mounted) return; // Ensure widget is still mounted
          if (chat.id == _chat?.id) {
            setState(() {
              _chat = chat;
              _userName = chat.name;
              _userImage = getChatAvatar(chat, getEnv("API_BASE_URL"));
              _isOnline = chat.partner?.status == "online";
              _typingUsers = chat.typingUsers;
              ;
            });
          }
        });

        try {
          final userData = await Auth.data();
          print("User data: $userData"); // Debug
          if (userData != null && userData['id'] != null) {
            _currentUserId = userData['id'] is int
                ? userData['id']
                : int.tryParse(userData['id'].toString());
            print('Current user id: [38;5;246m$_currentUserId[0m');
          }
        } catch (e) {
          print('Error fetching user id: $e');
        }

        // Retrieve chat data from navigation
        final navigationData = data();

        if (navigationData != null) {
          final chatId = navigationData['chatId'] as int?;

          
          if (chatId != null) {
            _chat = await ChatService().getChatDetails(chatId);
            final messages = await ChatService().getChatMessages(chatId);

            
            if (_chat != null) {
              if (_chat!.type == 'PRIVATE' && _chat!.partner != null) {
                _userName = _chat!.name;
                _userImage = getChatAvatar(_chat!, getEnv("API_BASE_URL"));
                _isOnline = _chat!.partner!.status == "online";
                _typingUsers = _chat!.typingUsers;
              } else {
                _userName = _chat!.name;
                _userImage = getChatAvatar(_chat!, getEnv("API_BASE_URL"));
                _isOnline = false;
                _isVerified = false;
                _typingUsers = _chat!.typingUsers;
              }
            }
            setState(() {
              _messages = messages;
            });

            _scrollToBottom();
            await _connectToWebSocket();
            _sendReadReceipts(_messages);
          }
        } else {
          routeToAuthenticatedRoute();
        }
      };

  Future<void> _sendReadReceipts(List<Message> messages) async {
    if (_currentUserId == null) return;
    final unreadMessageIds = messages
        .where((msg) => msg.senderId != _currentUserId)
        .map((msg) => msg.id)
        .toList();
    if (unreadMessageIds.isNotEmpty) {
      try {
        await WebSocketService().sendReadReceipt(unreadMessageIds);
        print('✅ Read receipts sent for messages: $unreadMessageIds');
      } catch (e) {
        print('❌ Error sending read receipts: $e');
      }
    }
  }

  // Connect to WebSocket
  Future<void> _connectToWebSocket() async {
    if (_chat != null) {
      try {
        // First initialize the connection if not already connected
        if (!WebSocketService().isConnected) {
          await WebSocketService().initializeConnection();
        }

        // Then connect to specific chat
        await WebSocketService().connectToChat(chatId: _chat!.id.toString());
        _isWebSocketConnected = WebSocketService().isConnected;

        print('WebSocket connected: $_isWebSocketConnected');
        _wsSubscription?.cancel();
        _notificationSubscription?.cancel();

        _wsSubscription =
            WebSocketService().messageStream.listen((messageData) {
          _handleIncomingMessage(messageData);
        });

        _notificationSubscription =
            WebSocketService().notificationStream.listen((notificationData) {
          _handleIncomingNotification(notificationData);
        });

        WebSocketService().connectionStatusStream.listen((isConnected) {
          if (mounted) {
            setState(() {
              _isWebSocketConnected = isConnected;
            });
          }
        });
      } catch (e) {
        print('Error connecting to WebSocket: $e');
        _isWebSocketConnected = false;
      }
    }
  }

  // Handle scroll events to detect when user reaches the top and update current day
  void _onScroll() {
    if (_scrollController.hasClients) {
      // Check if user has scrolled to the top (within 100 pixels from the top)
      if (_scrollController.position.pixels <= 100 && !_isLoadingAtTop) {
        print("At the top");
        _loadMoreMessagesAtTop();
      }
      
      // Show floating header while scrolling
      _showFloatingHeader();
      
      // Update the current day based on visible messages
      if (_messages.isNotEmpty) {
        // Estimate which message is at the top of the viewport
        double itemHeight = 70.0; // Approximate height of a message
        int visibleIndex = (_scrollController.position.pixels / itemHeight).floor();
        
        // Bound the index within the list range
        visibleIndex = visibleIndex.clamp(0, _messages.length - 1);
        
        // Update current day if it changed
        String newDay = _formatDaySeparator(_messages[visibleIndex].createdAt);
        if (currentDay != newDay) {
          setState(() {
            currentDay = newDay;
          });
        }
      }
    }
  }
  
  // Show floating header and set timer to hide it
  void _showFloatingHeader() {
    // Cancel any existing timer
    _headerVisibilityTimer?.cancel();
    
    // Show the header
    if (!_isShowingFloatingHeader) {
      setState(() {
        _isShowingFloatingHeader = true;
      });
    }
    
    // Set timer to hide header after 3 seconds
    _headerVisibilityTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _isShowingFloatingHeader = false;
        });
      }
    });
  }

  // Load more messages when user scrolls to top
  Future<void> _loadMoreMessagesAtTop() async {
    if (_isLoadingAtTop) return;

    setState(() {
      _isLoadingAtTop = true;
    });

    print("🔄 Loading more messages from top...");

    // Simulate loading delay (replace with actual API call)
    // await Future.delayed(const Duration(seconds: 2));
    var chatService = ChatService();
    final List<Message> messages =
        await chatService.loadPreviousMessages(_chat!.id, _messages.first.id);

    // Here you would typically load older messages from your API
    // For now, we'll just simulate the loading completion
    setState(() {
      _isLoadingAtTop = false;
      _messages.insertAll(0, messages);
    });

    print("✅ Finished loading messages from top");
  }

  // Handle incoming notifications
  Future<void> _handleIncomingNotification(
      Map<String, dynamic> notificationData) async {
    print('Handling incoming notification: $notificationData');
    final userData = await Auth.data();

    if (!mounted) return; // Don't update state if widget is disposed

    if (notificationData['action'] == 'user:disconnected') {
      // Handle chat update notifications
      if (_chat != null && _chat!.partner != null) {
        if (notificationData['userId'] == _chat!.partner!.id) {
          setState(() {
            _isOnline = false;
          });
        }
      }
    } else if (notificationData['action'] == 'user:connected') {
      // Handle user connected notification
      if (_chat != null && _chat!.partner != null) {
        if (notificationData['userId'] == _chat!.partner!.id) {
          setState(() {
            _isOnline = true;
          });
        }
      }
    } else if (notificationData['action'] == 'typing:start') {
      if (notificationData['chatId'] == _chat?.id &&
          notificationData['userId'] != userData?['id']) {
        final newTypingUsers = _typingUsers.toSet();
        newTypingUsers.add(notificationData['userId']);

        setState(() {
          _typingUsers = newTypingUsers;
        });
      }
    } else if (notificationData['action'] == 'typing:stop' &&
        notificationData['userId'] != userData?['id']) {
      if (notificationData['chatId'] == _chat?.id) {
        final newTypingUsers = _typingUsers.toSet();
        newTypingUsers.remove(notificationData['userId']);
        setState(() {
          _typingUsers = newTypingUsers;
        });
      }
    } else if (notificationData['action'] == "message:delivered") {
      // final List<int> ids = List<int>.from(notificationData['ids']);
      List<int> ids =
          (notificationData['ids'] as List?)?.cast<int>() ?? <int>[];

      setState(() {
        _messages = _messages.map((msg) {
          if (ids.contains(msg.id)) {
            msg.isDelivered = true;
          }
          return msg;
        }).toList();
      });
    } else if (notificationData['action'] == "message:read") {
      print(notificationData['ids']);
      final dynamic idsData = notificationData['ids'];
      final List<int> ids =
          (idsData as List<dynamic>).map((e) => e as int).toList();
      setState(() {
        _messages = _messages.map((msg) {
          if (ids.contains(msg.id)) {
            msg.isRead = true;
          }
          return msg;
        }).toList();
      });
    }
  }

  // Handle incoming WebSocket messages
  void _handleIncomingMessage(Map<String, dynamic> messageData) {
    // This runs on the main thread and won't block UI
    print('Handling incoming message: $messageData');
    print('Message ID: ${messageData['id']}');

    if (!mounted) return; // Don't update state if widget is disposed

    // Check if this message belongs to the current chat
    final messageChatId = messageData['chatId'];
    final currentChatId = _chat?.id;

    print('Message chat ID: $messageChatId, Current chat ID: $currentChatId');

    if (messageChatId != currentChatId) {
      print('❌ Message not for current chat, ignoring');
      return;
    }

    setState(() {
      final action = messageData['action'];

      if (action != null && action == 'delete') {
        final index =
            _messages.indexWhere((msg) => msg.id == messageData['id']);
        // Remove message if action is delete
        print("Message deleted: ${messageData['id']}");
        print("Removing message at index: $index");
        if (index != -1) {
          _messages.removeAt(index);
        }
      } else {
        Message newMessage = Message.fromJson(messageData);
        if (newMessage.referenceId != null) {
          final index = _messages
              .indexWhere((msg) => msg.referenceId == newMessage.referenceId);
          if (index != -1) {
            _messages[index] = newMessage;
            return;
          }
        }

        _messages.add(newMessage);
        if (newMessage.senderId != _currentUserId) {
          WebSocketService().sendReadReceipt([newMessage.id]);
        }
      }
    });
    _scrollToBottom();
  }

  void _onTextChanged() {
    bool hasText = _messageController.text.trim().isNotEmpty;

    if (hasText != _hasText) {
      print('Text changed: hasText=$hasText, _hasText=$_hasText'); // Debug

      // Only send typing indicator if chat is available and WebSocket is connected
      if (_chat != null && _isWebSocketConnected) {
        try {
          WebSocketService().sendTypingIndicator(
            hasText,
            _chat!.id,
          );
        } catch (e) {
          print('Error sending typing indicator: $e');
        }
      }

      setState(() {
        _hasText = hasText;
      });
    }
  }

  @override
  void dispose() {
    _messageController.removeListener(_onTextChanged);
    _scrollController.removeListener(_onScroll);
    _messageController.dispose();
    _scrollController.dispose();

    // Clean up WebSocket subscriptions but keep the service running
    // as it might be used by other screens
    _wsSubscription?.cancel();
    _notificationSubscription?.cancel();
    _recordingTimer?.cancel();
    _headerVisibilityTimer?.cancel(); // Dispose the header visibility timer
    _audioRecorder.dispose();
    _audioPlayer?.dispose();
    super.dispose();
  }

  Future<void> _playAudioMessage(Message message) async {
    try {
      // Stop any currently playing audio
      if (_audioPlayer != null) {
        await _audioPlayer!.stop();
        await _audioPlayer!.dispose();
      }
      
      _audioPlayer = AudioPlayer();

      setState(() {
        _playingMessageId = message.id;
        _isAudioPlaying = true;
        _audioPosition = Duration.zero;
        _audioDuration = Duration.zero;
      });

      // Listen to duration changes
      _audioPlayer!.onDurationChanged.listen((duration) {
        setState(() {
          _audioDuration = duration;
        });
      });

      // Listen to position changes
      _audioPlayer!.onPositionChanged.listen((position) {
        setState(() {
          _audioPosition = position;
        });
      });

      // Listen to completion
      _audioPlayer!.onPlayerComplete.listen((event) {
        setState(() {
          _isAudioPlaying = false;
          _playingMessageId = null;
          _audioPosition = Duration.zero;
        });
      });

      // Play the audio file
      // Assuming the audio file path is stored in message.text for audio messages
      
      if (message.fileId != null) {
            String audioUrl = '${getEnv("API_BASE_URL")}/uploads/${message.fileId}';
            print("Playing audio from URL: $audioUrl");
          await _audioPlayer!.play(UrlSource(audioUrl));
      }
    } catch (e) {
      print('Error playing audio: $e');
      setState(() {
        _isAudioPlaying = false;
        _playingMessageId = null;
      });
    }
  }

  Future<void> _pauseAudioMessage() async {
    if (_audioPlayer != null) {
      await _audioPlayer!.pause();
      setState(() {
        _isAudioPlaying = false;
      });
    }
  }

  Future<void> _stopAudioMessage() async {
    if (_audioPlayer != null) {
      await _audioPlayer!.stop();
      setState(() {
        _isAudioPlaying = false;
        _playingMessageId = null;
        _audioPosition = Duration.zero;
      });
    }
  }

  Future<void> _pickFileOnWeb() async {
    FilePickerResult? result =
        await FilePicker.platform.pickFiles(type: FileType.image);

    if (result != null) {
      String fileName = result.files.first.name;
      print(fileName);
      // Use fileName as needed
    }
    // Implement file picking for web
  }

  void _toggleMediaPicker() {
    if (kIsWeb) {
      _pickFileOnWeb();
      setState(() {
        _showMediaPicker = false;
      });
    } else {
      setState(() {
        _showMediaPicker = !_showMediaPicker;
      });
    }
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final XFile? image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );
      if (image != null) {
        setState(() {
          _pickedImage = image;
          _showMediaPicker = false;
        });
      }
    } catch (e) {
      print('Error picking image from gallery: $e');
    }
  }

  void _closeImagePreview() {
    setState(() {
      _pickedImage = null;
    });
  }

  void _sendMessage() async {

    if (_messageController.text.trim().isNotEmpty) {
      final messageText = _messageController.text.trim();
      print("Sending message: $messageText");
      print("WebSocket connected: $_isWebSocketConnected");
      print("Chat ID: ${_chat?.id}");
      print("Current User ID: $_pickedImage");

      // Add message to UI immediately for better UX
      final referenceId = DateTime.now().millisecondsSinceEpoch;
      final type = _pickedImage != null ? "PHOTO" : "TEXT";
      
      setState(() {
        final now = DateTime.now();
        final newMessage = Message(
          id: DateTime.now().millisecondsSinceEpoch, // Temporary ID
          senderId: _currentUserId ?? 0,
          chatId: _chat?.id ?? 0,
          type: type,
          text: messageText,
          caption: _pickedImage != null ? messageText : null,
          fileId: null,
          createdAt: now,
          updatedAt: now,
          sender: Sender(
            id: _currentUserId ?? 0,
            username: 'You',
            firstName: null,
            lastName: null,
          ),
          tempImagePath: _pickedImage?.path,
          referenceId: referenceId,
          isSent: false,
          statuses: [],
          isRead: false,
          isDelivered: false,
          isAudio: false,
          audioDuration: null,
        );
        // _pickedImage = null;
        _messages.add(newMessage);
        print('✅ Message added to list. Total messages: ${_messages.length}');
        print('Message text: "${newMessage.text}"');
      });

      _messageController.clear();
      _scrollToBottom();

      final shouldSendViaWebSocket =  WebSocketService().isConnected && _pickedImage == null;
      print('🔍 Should send via WebSocket: $shouldSendViaWebSocket');

      if (shouldSendViaWebSocket) {
        print('🚀 === SEND MESSAGE TRIGGERED ===');
        WebSocketService().sendMessage(messageText, _chat!.id, referenceId);
        print('✅ SendMessage method called');
      } else if (_chat != null) {
        try {
          
          apiService.sendMessage(
            chatId: _chat!.id,
            text: messageText,
            caption: messageText,
            filePath: _pickedImage?.path,
            referenceId: referenceId,
            type: "PHOTO",

          );
          setState(() {
            _pickedImage = null; // Clear the picked image after sending
          });
          
          // if (result != null) {}
        } catch (e) {
          print('Error sending message via API: $e');
        }
      } else {
        print(
            '⚠️ No WebSocket connection available, will retry in 1 second...');

        // Retry sending after a short delay in case WebSocket connects
        Future.delayed(const Duration(seconds: 1), () {
          if (WebSocketService().isConnected && mounted) {
            print('🔄 Retrying message send after WebSocket connection...');
            WebSocketService().sendMessage(messageText, _chat!.id, referenceId);
          } else {
            print('❌ WebSocket still not connected after retry');
          }
        });
      }
    }
  }

  Future<void> _sendAudioMessage(String audioPath) async {
    print("Sending audio message: $audioPath");
    
    if (_chat != null) {
      final referenceId = DateTime.now().millisecondsSinceEpoch;
      
      // Add audio message to UI immediately for better UX
      setState(() {
        final now = DateTime.now();
        final newMessage = Message(
          id: DateTime.now().millisecondsSinceEpoch, // Temporary ID
          senderId: _currentUserId ?? 0,
          chatId: _chat?.id ?? 0,
          type: 'AUDIO',
          text: null,
          // caption: 'Voice message',
          fileId: null,
          createdAt: now,
          updatedAt: now,
          sender: Sender(
            id: _currentUserId ?? 0,
            username: 'You',
            firstName: null,
            lastName: null,
          ),
          referenceId: referenceId,
          isSent: false,
          statuses: [],
          isRead: false,
          isDelivered: false,
          isAudio: true,
          audioDuration: _recordingDuration.toString(),
        );
        _messages.add(newMessage);
        print('✅ Audio message added to list. Total messages: ${_messages.length}');
      });
      
      _scrollToBottom();
      
      try {
        // Send audio file via API
        await apiService.sendMessage(
          chatId: _chat!.id,
          text: null,
          caption: 'Voice message',
          filePath: audioPath,
          referenceId: referenceId,
          type: "AUDIO",
        );
        
        print('✅ Audio message sent successfully');
      } catch (e) {
        print('Error sending audio message: $e');
      }
    }
  }

 void _scrollToBottom() {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && _scrollController.hasClients) {
      // Force scroll to the very bottom
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      
      // Then animate to ensure smooth scroll
      Future.delayed(const Duration(milliseconds: 50), () {
        if (mounted && _scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  });
}

  Future<void> _startRecording() async {
    try {
      // Request microphone permission
      var status = await Permission.microphone.request();
      if (status != PermissionStatus.granted) {
        print('Microphone permission denied');
        return;
      }

      // Check if recording is supported
      if (await _audioRecorder.hasPermission()) {
        // Get the documents directory
        Directory appDocDir = await getApplicationDocumentsDirectory();
        String recordingPath = '${appDocDir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.m4a';
        
        // Start recording
        await _audioRecorder.start(path: recordingPath);
        
        setState(() {
          _isRecording = true;
          _recordingDuration = 0;
          _recordedAudioPath = recordingPath;
        });
        
        // Start recording timer
        _recordingTimer = Timer.periodic(Duration(seconds: 1), (timer) {
          setState(() {
            _recordingDuration++;
          });
        });
        
        print('Recording started at: $recordingPath');
      }
    } catch (e) {
      print('Error starting recording: $e');
      setState(() {
        _isRecording = false;
      });
    }
  }

  Future<void> _stopRecording() async {
    try {
      _recordingTimer?.cancel();
      
      // Stop the actual recording
      String? recordingPath = await _audioRecorder.stop();
      
      setState(() {
        _isRecording = false;
      });
      
      print('Recording stopped. Duration: $_recordingDuration seconds');
      print('Recording saved at: $recordingPath');
      
      // Send the audio message if recording duration is sufficient
      if (_recordingDuration > 0 && recordingPath != null) {
        // Send audio message through chat API
        print("Recoding path: $recordingPath");
        await _sendAudioMessage(recordingPath);
      }
      
      setState(() {
        _recordingDuration = 0;
        _recordedAudioPath = null;
      });
    } catch (e) {
      print('Error stopping recording: $e');
    }
  }

  Future<void> _cancelRecording() async {
    try {
      _recordingTimer?.cancel();
      
      // Stop recording without saving
      await _audioRecorder.stop();
      
      setState(() {
        _isRecording = false;
        _recordingDuration = 0;
        _recordedAudioPath = null;
      });
      
      print('Recording cancelled');
    } catch (e) {
      print('Error cancelling recording: $e');
    }
  }

  void _toggleRecording() {
    if (_isRecording) {
      _stopRecording();
    } else {
      _startRecording();
    }
  }

  @override
  Widget view(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Full screen SVG background
          Positioned.fill(
            child: SvgPicture.asset(
              'public/images/chatBackround.svg',
              fit: BoxFit.cover,
            ),
          ),
          // Main content
          Column(
            children: [
              // AppBar with semi-transparent background
              Container(
                color: Color(0xFF1C212C).withOpacity(0.9),
                child: SafeArea(
                  bottom: false,
                  child: Container(
                    height: kToolbarHeight,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      children: [
                        IconButton(
                          icon: Container(
                            width: 18,
                            height: 18,
                            child: SvgPicture.asset(
                              'public/images/back_arrow.svg',
                              width: 18,
                              height: 18,
                              colorFilter: ColorFilter.mode(
                                Color(0xFFE8E7EA),
                                BlendMode.srcIn,
                              ),
                            ),
                          ),

                          onPressed: () => Navigator.pop(context),
                          // onPressed: () => routeToAuthenticatedRoute(),
                        ),
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.grey.shade700,
                          ),
                          child: ClipOval(
                            child: _userImage != null
                                ? Image.network(
                                    _userImage!,
                                    fit: BoxFit.cover,
                                  )
                                : Icon(
                                    Icons.person,
                                    color: Colors.grey.shade500,
                                    size: 20,
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment
                                .center, // This centers the column content
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _userName,
                                textAlign: TextAlign
                                    .center, // Add this to center the text horizontally
                                style: const TextStyle(
                                  color: Color(0xFFE8E7EA),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment
                                    .center, // This centers the row content
                                children: [
                                  if (_typingUsers.isEmpty)
                                    Container(
                                      width: 4,
                                      height: 4,
                                      decoration: BoxDecoration(
                                        color: _isOnline
                                            ? const Color(0xFF2ECC71)
                                            : Colors.grey.shade500,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _typingUsers.isNotEmpty
                                        ? 'Typing...'
                                        : (_isOnline ? 'Online' : 'Offline'),
                                    style: TextStyle(
                                      color: _typingUsers.isNotEmpty
                                          ? const Color(0xFF3498DB)
                                          : (_isOnline
                                              ? const Color(0xFF2ECC71)
                                              : Colors.grey.shade500),
                                      fontSize: 8,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onTap: () => routeTo(VideoCallPage.path, data: {
                                "partner": _chat?.partner?.toJson(),
                                "isGroup": _chat?.type == 'CHANNEL',
                                "chatId": _chat?.id,
                                "initiateCall": true,
                              }),
                              child: Container(
                                width: 18,
                                height: 18,
                                child: SvgPicture.asset(
                                  'public/images/video_call.svg',
                                  width: 18,
                                  height: 18,
                                  colorFilter: ColorFilter.mode(
                                    Color(0xFFE8E7EA),
                                    BlendMode.srcIn,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12), // Exact spacing you want
                            GestureDetector(
                              onTap: () => routeTo(VoiceCallPage.path, data: {
                                "partner": _chat?.partner?.toJson(),
                                "isGroup": _chat?.type == 'CHANNEL',
                                "chatId": _chat?.id,
                                "initiateCall": true,
                              }),
                              child: Container(
                                width: 18,
                                height: 18,
                                child: SvgPicture.asset(
                                  'public/images/voice_call.svg',
                                  width: 18,
                                  height: 18,
                                  colorFilter: ColorFilter.mode(
                                    Color(0xFFE8E7EA),
                                    BlendMode.srcIn,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),
                ),
              ),

              // Chat content with floating Today header
              Expanded(
                child: Stack(
                  children: [
                    // Messages with padding for floating header
                    GestureDetector(
                      onTap: () {
                        // Dismiss keyboard when tapping outside input
                        FocusScope.of(context).unfocus();
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(
                            top: 0,
                            bottom:
                                20), // Space for floating "Today" and input area
                        child: RefreshIndicator(
                          onRefresh: () async {
                            print('🔄 Pull to refresh triggered');
                            // await _loadPreviousMessages();
                          },
                          child: ListView.builder(
                            controller: _scrollController,
                            itemCount:
                                _messages.length + (_isLoadingAtTop ? 1 : 0),
                                padding: const EdgeInsets.only(bottom: 80),
                            itemBuilder: (context, index) {
                              // Show loading indicator at the top
                              if (index == 0 && _isLoadingAtTop) {
                                return Container(
                                  padding: const EdgeInsets.all(16),
                                  child: Center(
                                    child: Column(
                                      children: [
                                        CircularProgressIndicator(
                                          color: Color(0xFF3498DB),
                                          strokeWidth: 2,
                                        ),
                                        
                                      ],
                                    ),
                                  ),
                                );
                              }

                              // Adjust index if loading indicator is shown
                              final messageIndex =
                                  _isLoadingAtTop ? index - 1 : index;
                              return _buildMessageWithDateSeparator(messageIndex);
                            },
                          ),
                        ),
                      ),
                    ),

                    // Floating date header - only visible while scrolling
                    if (_isShowingFloatingHeader)
                      Positioned(
                        top: 8,
                        left: 0,
                        right: 0,
                        child: AnimatedOpacity(
                          opacity: _isShowingFloatingHeader ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 300),
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Color(0xFF1C212C).withOpacity(0.8),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                currentDay ?? (_messages.isNotEmpty 
                                    ? _formatDaySeparator(_messages[0].createdAt)
                                    : 'Today'),
                                style: const TextStyle(
                                  color: Color(0xFFE8E7EA),
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                    // Transparent input area with blur effect
                    if (!_showMediaPicker)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: ClipRRect(
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.2),
                                border: Border(
                                  top: BorderSide(
                                    color: Colors.white.withOpacity(0.1),
                                    width: 0.5,
                                  ),
                                ),
                              ),
                              child: SafeArea(
                                top: false,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Image preview above input
                                    if (_pickedImage != null)
                                      Container(
                                        margin: const EdgeInsets.only(bottom: 12),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(12),
                                          color: Colors.black.withOpacity(0.3),
                                        ),
                                        child: Stack(
                                          children: [
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(12),
                                              child: Image.file(
                                                File(_pickedImage!.path),
                                                height: 120,
                                                width: double.infinity,
                                                fit: BoxFit.cover,
                                              ),
                                            ),
                                            Positioned(
                                              top: 8,
                                              right: 8,
                                              child: GestureDetector(
                                                onTap: _closeImagePreview,
                                                child: Container(
                                                  padding: const EdgeInsets.all(4),
                                                  decoration: BoxDecoration(
                                                    color: Colors.black.withOpacity(0.7),
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: const Icon(
                                                    Icons.close,
                                                    color: Colors.white,
                                                    size: 16,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    // Recording indicator
                                    if (_isRecording)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                        margin: const EdgeInsets.only(bottom: 8),
                                        decoration: BoxDecoration(
                                          color: Colors.red.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(color: Colors.red.withOpacity(0.3)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              width: 8,
                                              height: 8,
                                              decoration: BoxDecoration(
                                                color: Colors.red,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Recording ${_recordingDuration}s',
                                              style: TextStyle(
                                                color: Colors.red,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            // Cancel button
                                            GestureDetector(
                                              onTap: _cancelRecording,
                                              child: Container(
                                                padding: const EdgeInsets.all(4),
                                                decoration: BoxDecoration(
                                                  color: Colors.red.withOpacity(0.2),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(
                                                  Icons.close,
                                                  color: Colors.red,
                                                  size: 16,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            // Stop button
                                            GestureDetector(
                                              onTap: _stopRecording,
                                              child: Container(
                                                padding: const EdgeInsets.all(4),
                                                decoration: BoxDecoration(
                                                  color: Colors.green.withOpacity(0.2),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(
                                                  Icons.stop,
                                                  color: Colors.green,
                                                  size: 16,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    // Input row
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        GestureDetector(
                                          onTap: _toggleMediaPicker,
                                          child: Container(
                                            width: 18,
                                            height: 18,
                                            margin: const EdgeInsets.only(bottom: 12),
                                            decoration: const BoxDecoration(
                                              color: Colors.transparent,
                                              shape: BoxShape.circle,
                                            ),
                                            child: SvgPicture.asset(
                                              'public/images/add.svg',
                                              width: 18,
                                              height: 18,
                                              colorFilter: ColorFilter.mode(
                                                Color(0xFFE8E7EA),
                                                BlendMode.srcIn,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Container(
                                            constraints: const BoxConstraints(
                                              maxHeight: 120,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Color(0xFF0F131B).withValues(alpha: .4),
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                            child: TextField(
                                              controller: _messageController,
                                              maxLines: null,
                                              keyboardType: TextInputType.multiline,
                                              textInputAction: TextInputAction.newline,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                                color: Color(0xFFE8E7EA),
                                              ),
                                              decoration: InputDecoration(
                                                hintText: 'Type a message...',
                                                hintStyle: TextStyle(
                                                  color: Color(0xFFE8E7EA).withOpacity(0.7),
                                                  fontSize: 16,
                                                ),
                                                border: InputBorder.none,
                                                contentPadding: EdgeInsets.symmetric(
                                                  horizontal: 16,
                                                  vertical: 10,
                                                ),
                                                suffixIcon: _hasText
                                                    ? GestureDetector(
                                                        onTap: _sendMessage,
                                                        child: Container(
                                                          width: 32,
                                                          height: 32,
                                                          margin: const EdgeInsets.only(bottom: 4),
                                                          decoration: const BoxDecoration(
                                                            color: Colors.transparent,
                                                            shape: BoxShape.circle,
                                                          ),
                                                          child: const Icon(
                                                            Icons.send,
                                                            color: Color(0xFFE8E7EA),
                                                            size: 20,
                                                          ),
                                                        ),
                                                      )
                                                    : GestureDetector(
                                                        onTap: _toggleRecording,
                                                        child: Container(
                                                          width: 32,
                                                          height: 32,
                                                          margin: const EdgeInsets.only(bottom: 4),
                                                          decoration: BoxDecoration(
                                                            color: _isRecording ? Colors.red.withOpacity(0.2) : Colors.transparent,
                                                            shape: BoxShape.circle,
                                                          ),
                                                          child: Icon(
                                                            _isRecording ? Icons.stop : Icons.mic,
                                                            color: _isRecording ? Colors.red : Color(0xFFE8E7EA),
                                                            size: 20,
                                                          ),
                                                        ),
                                                      ),
                                              ),
                                              onSubmitted: (_) => _sendMessage(),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        if (!_hasText)
                                          GestureDetector(
                                            onTap: () {},
                                            child: Container(
                                              width: 18,
                                              height: 18,
                                              margin: const EdgeInsets.only(bottom: 12),
                                              decoration: const BoxDecoration(
                                                color: Colors.transparent,
                                                shape: BoxShape.circle,
                                              ),
                                              child: SvgPicture.asset(
                                                'public/images/camera_icons.svg',
                                                width: 18,
                                                height: 18,
                                                colorFilter: ColorFilter.mode(
                                                  Color(0xFFE8E7EA),
                                                  BlendMode.srcIn,
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
                          ),
                        ),
                      ),

                    // Media picker overlay
                    if (_showMediaPicker)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: _buildMediaPicker(),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(Message message) {
    
    switch (message.type) {
      case "AUDIO":
      case "VOICE":
        return _buildAudioMessage(message);

      case "IMAGE":
      case "PHOTO":
        return _buildPhotoMessage(message);
      case "TEXT":
      default:
        return _buildTextMessage(message);
    }
  }
  
  /// Helper function to format the date for the day separator
  String _formatDaySeparator(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date).inDays;

    if (difference == 0) {
      return 'Today';
    } else if (difference == 1) {
      return 'Yesterday';
    } else if (difference < 7) {
      return ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][date.weekday - 1];
    } else {
      // Month names for better readability
      final months = [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
      ];
      return '${months[date.month - 1]} ${date.day}, ${date.year}';
    }
  }

  /// Function to build messages with day separators
  Widget _buildMessageWithDateSeparator(int index) {
    final message = _messages[index];
    final messageDate = message.createdAt;

    // Check if a day separator is needed
    if (index == 0 || messageDate.day != _messages[index - 1].createdAt.day) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Color(0xFF1C212C).withOpacity(0.8),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _formatDaySeparator(messageDate),
                style: const TextStyle(
                  color: Color(0xFFE8E7EA),
                  fontSize: 14,
                ),
              ),
            ),
          ),
          _buildMessage(message),
        ],
      );
    }

    return _buildMessage(message);
  }

  Widget _buildTextMessage(Message message) {
    // Determine if this message was sent by the current user
    final bool isSentByMe =
        _currentUserId != null && message.senderId == _currentUserId;

    // Check if this is the last message to add extra bottom spacing
    final bool isLastMessage =
        _messages.isNotEmpty && _messages.last == message;

    return Container(
      margin: EdgeInsets.fromLTRB(2, 0, 2,
          isLastMessage ? 20 : 4), // Extra bottom margin for last message
      child: Row(
        mainAxisAlignment:
            isSentByMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isSentByMe) const SizedBox(width: 10),
          Flexible(
            child: GestureDetector(
              onTapDown: (TapDownDetails details) {
                _showMessageContextMenu(context, message, details.globalPosition);
              },
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.7,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isSentByMe
                      ? const Color(0xFF18365B)
                      : const Color(0xFF404040),
                  borderRadius: isSentByMe
                      ? const BorderRadius.only(
                          topLeft: Radius.circular(18),
                          topRight: Radius.circular(18),
                          bottomLeft: Radius.circular(18),
                          bottomRight: Radius.circular(4),
                        )
                      : const BorderRadius.only(
                          topLeft: Radius.circular(4),
                          topRight: Radius.circular(18),
                          bottomLeft: Radius.circular(18),
                          bottomRight: Radius.circular(18),
                        ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (message.isAudio)
                      Row(
                        children: [
                          Icon(
                            Icons.play_arrow,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            message.audioDuration ?? '0:00',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      )
                    else
                      Text(
                        message.type == "TEXT"
                            ? (message.text ?? '')
                            : (message.caption ?? ''),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          message.createdAt.toIso8601String().substring(11, 16),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 12,
                          ),
                        ),
                        if (isSentByMe) ...[
                          const SizedBox(width: 4),
                          if (!message.isSent)
                            Icon(
                              Icons.schedule,
                              color: Colors.white.withOpacity(0.7),
                              size: 16,
                            ),
                          if (message.isSent &&
                              !message.isDelivered &&
                              !message.isRead)
                            Icon(
                              Icons.done,
                              color: Colors.white.withOpacity(0.7),
                              size: 16,
                            ),

                          // if (message.isDelivered)
                          //   Icon(
                          //     Icons.done,
                          //     color: Colors.white.withOpacity(0.7),
                          //     size: 16,
                          //   ),

                          if (message.isRead)
                            Icon(
                              Icons.done_all,
                              color: Colors.white.withOpacity(0.7),
                              size: 16,
                            ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (isSentByMe) const SizedBox(width: 10),
        ],
      ),
    );
  }

  Widget _buildAudioMessage(Message message) {
    final bool isCurrentlyPlaying = _playingMessageId == message.id && _isAudioPlaying;
    final bool isSentByMe = _currentUserId != null && message.senderId == _currentUserId;
    
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        mainAxisAlignment: isSentByMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isSentByMe) const SizedBox(width: 10),
          Flexible(
            child: GestureDetector(
              onTapDown: (TapDownDetails details) {
                _showMessageContextMenu(context, message, details.globalPosition);
              },
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.5,
                ),
                decoration: BoxDecoration(
                  color: isSentByMe
                      ? const Color(0xFF18365B)
                      : const Color(0xFF404040),
                  borderRadius: isSentByMe
                      ? const BorderRadius.only(
                          topLeft: Radius.circular(18),
                          topRight: Radius.circular(18),
                          bottomLeft: Radius.circular(18),
                          bottomRight: Radius.circular(4),
                        )
                      : const BorderRadius.only(
                          topLeft: Radius.circular(4),
                          topRight: Radius.circular(18),
                          bottomLeft: Radius.circular(18),
                          bottomRight: Radius.circular(18),
                        ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () {
                        if (isCurrentlyPlaying) {
                          _pauseAudioMessage();
                        } else if (_playingMessageId == message.id) {
                          _playAudioMessage(message);
                        } else {
                          _playAudioMessage(message);
                        }
                        HapticFeedback.lightImpact();
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        margin: EdgeInsets.only(bottom: 10, left: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isCurrentlyPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Audio waveform visualization
                          Container(
                            height:30,
                            margin: EdgeInsets.only(top: 8),
                            child: Row(
                              children: List.generate(15, (index) {
                                double height = [
                                  0.3, 0.7, 0.5, 0.9, 0.4, 0.8, 0.6, 0.3,
                                  0.7, 0.5, 0.9, 0.4, 0.8, 0.6, 0.3
                                ][index];
                                
                                // Animate waveform based on progress
                                double progress = _audioDuration.inMilliseconds > 0 
                                    ? _audioPosition.inMilliseconds / _audioDuration.inMilliseconds 
                                    : 0.0;
                                bool isActive = (index / 15) <= progress;
                                
                                return Container(
                                  width: 3,
                                  height: 30 * height,
                                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                                  decoration: BoxDecoration(
                                    color: isActive && isCurrentlyPlaying 
                                        ? Colors.white
                                        : Colors.white.withOpacity(0.5),
                                    borderRadius: BorderRadius.circular(1.5),
                                  ),
                                );
                              }),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _playingMessageId == message.id 
                                    ? _formatDuration(_audioPosition)
                                    : message.audioDuration ?? "0:00",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                              Row(
                                children: [
                                  Text(
                                    message.createdAt.toIso8601String().substring(11, 16),
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.7),
                                      fontSize: 12,
                                    ),
                                  ),
                                  if (isSentByMe) ...[
                                    const SizedBox(width: 4),
                                    Icon(
                                      message.isRead ? Icons.done_all : Icons.done,
                                      color: message.isRead 
                                          ? Colors.blue 
                                          : Colors.white.withOpacity(0.7),
                                      size: 16,
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (isSentByMe) const SizedBox(width: 10),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  Widget _buildPhotoMessage(Message message) {
    final bool isSentByMe =
        _currentUserId != null && message.senderId == _currentUserId;
    final bool isLastMessage =
        _messages.isNotEmpty && _messages.last == message;

    return Container(
      margin: EdgeInsets.fromLTRB(2, 0, 2,
          isLastMessage ? 20 : 4), // Extra bottom margin for last message
      child: Row(
        mainAxisAlignment:
            isSentByMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isSentByMe) const SizedBox(width: 10),
          Flexible(
            child: GestureDetector(
              onTapDown: (TapDownDetails details) {
                _showMessageContextMenu(context, message, details.globalPosition);
              },
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.7,
                ),
                decoration: BoxDecoration(
                  color: isSentByMe
                      ? const Color(0xFF18365B)
                      : const Color(0xFF404040),
                  borderRadius: isSentByMe
                      ? const BorderRadius.only(
                          topLeft: Radius.circular(18),
                          topRight: Radius.circular(18),
                          bottomLeft: Radius.circular(18),
                          bottomRight: Radius.circular(4),
                        )
                      : const BorderRadius.only(
                          topLeft: Radius.circular(4),
                          topRight: Radius.circular(18),
                          bottomLeft: Radius.circular(18),
                          bottomRight: Radius.circular(18),
                        ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Image display
                    ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(18),
                        topRight: Radius.circular(18),
                        bottomLeft: Radius.circular(4),
                        bottomRight: Radius.circular(4),
                      ),
                      child: GestureDetector(
                        onTap: () => _showImagePopup(context, message),
                        child: Container(
                          constraints: const BoxConstraints(
                            maxWidth: 200,
                            maxHeight: 200,
                          ),
                          child: AspectRatio(
                            aspectRatio: 1, // Square aspect ratio for smaller images
                            child: message.fileId != null
                              ? Image.network(
                                  '${getEnv("API_BASE_URL")}/uploads/${message.fileId}',
                                  fit: BoxFit.cover,
                                  
                                  loadingBuilder: (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return Container(
                                      color: Colors.grey.shade300,
                                      child: Center(
                                        child: CircularProgressIndicator(
                                          value: loadingProgress.expectedTotalBytes != null
                                              ? loadingProgress.cumulativeBytesLoaded /
                                                  loadingProgress.expectedTotalBytes!
                                              : null,
                                          color: const Color(0xFF3498DB),
                                        ),
                                      ),
                                    );
                                  },
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      color: Colors.grey.shade300,
                                      child: const Center(
                                        child: Icon(
                                          Icons.broken_image,
                                          color: Colors.grey,
                                          size: 20,
                                        ),
                                      ),
                                    );
                                  },
                                )
                              : message.tempImagePath != null
                                ? Image.file(
                                    File(message.tempImagePath!),
                                    fit: BoxFit.cover,
                                  )
                                : Container(
                                    color: Colors.grey.shade300,
                                    child: const Center(
                                      child: Icon(
                                        Icons.image,
                                        color: Colors.grey,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                    // Caption and timestamp
                    if (message.caption != null && message.caption!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              message.caption!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  message.createdAt.toIso8601String().substring(11, 16),
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.7),
                                    fontSize: 12,
                                  ),
                                ),
                                if (isSentByMe) ...[
                                  const SizedBox(width: 4),
                                  if (!message.isSent)
                                    Icon(
                                      Icons.schedule,
                                      color: Colors.white.withOpacity(0.7),
                                      size: 16,
                                    ),
                                  if (message.isSent &&
                                      !message.isDelivered &&
                                      !message.isRead)
                                    Icon(
                                      Icons.done,
                                      color: Colors.white.withOpacity(0.7),
                                      size: 16,
                                    ),
                                  if (message.isRead)
                                    Icon(
                                      Icons.done_all,
                                      color: Colors.white.withOpacity(0.7),
                                      size: 16,
                                    ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      )
                    else
                      // Just timestamp if no caption
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              message.createdAt.toIso8601String().substring(11, 16),
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 12,
                              ),
                            ),
                            if (isSentByMe) ...[
                              const SizedBox(width: 4),
                              if (!message.isSent)
                                Icon(
                                  Icons.schedule,
                                  color: Colors.white.withOpacity(0.7),
                                  size: 16,
                                ),
                              if (message.isSent &&
                                  !message.isDelivered &&
                                  !message.isRead)
                                Icon(
                                  Icons.done,
                                  color: Colors.white.withOpacity(0.7),
                                  size: 16,
                                ),
                              if (message.isRead)
                                Icon(
                                  Icons.done_all,
                                  color: Colors.white.withOpacity(0.7),
                                  size: 16,
                                ),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (isSentByMe) const SizedBox(width: 10),
        ],
      ),
    );
  }

  Widget _buildMediaPicker() {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
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
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade600,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header with title
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => _toggleMediaPicker(),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      color: Color(0xFFE8E7EA),
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const Spacer(),
                const Text(
                  'Recent',
                  style: TextStyle(
                    color: Color(0xFFE8E7EA),
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    // Handle manage action
                  },
                  child: const Text(
                    'Manage',
                    style: TextStyle(
                      color: Color(0xFF3498DB),
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Content area (takes most of the space)
          Expanded(
            child: _MediaPickerContent(),
          ),

          // Tab indicator at bottom
          Container(
            height: 2,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              color: Color(0xFF3498DB),
            ),
          ),
        ],
      ),
    );
  }

  // Show message context menu with comprehensive options
  void _showMessageContextMenu(BuildContext context, Message message, Offset tapPosition) {
    final bool isSentByMe = _currentUserId != null && message.senderId == _currentUserId;
    
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        tapPosition.dx,
        tapPosition.dy - 200,
        tapPosition.dx + 150,
        tapPosition.dy,
      ),
      color: const Color(0xFF2A2A2A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 8,
      items: [
        // Reply option
        // PopupMenuItem(
        //   value: 'reply',
        //   child: Row(
        //     children: [
        //       Icon(Icons.reply, color: Color(0xFFE8E7EA), size: 20),
        //       SizedBox(width: 12),
        //       Text(
        //         'Reply',
        //         style: TextStyle(color: Color(0xFFE8E7EA), fontSize: 16),
        //       ),
        //     ],
        //   ),
        // ),
        
        // Copy Media option (for image/audio messages)
        if (message.type == 'PHOTO' || message.type == 'AUDIO')
          PopupMenuItem(
            value: 'copy_media',
            child: Row(
              children: [
                Icon(Icons.copy, color: Color(0xFFE8E7EA), size: 20),
                SizedBox(width: 12),
                Text(
                  'Copy Media',
                  style: TextStyle(color: Color(0xFFE8E7EA), fontSize: 16),
                ),
              ],
            ),
          ),
        
        // Copy Text option (for text messages)
        if ((message.type == 'TEXT' || message.type == "PHOTO" ) && (message.text != null || message.caption != null))
          PopupMenuItem(
            value: 'copy_text',
            child: Row(
              children: [
                Icon(Icons.copy, color: Color(0xFFE8E7EA), size: 20),
                SizedBox(width: 12),
                Text(
                  'Copy Text',
                  style: TextStyle(color: Color(0xFFE8E7EA), fontSize: 16),
                ),
              ],
            ),
          ),
        
        // Save As option (for media messages)
        if (message.type == 'PHOTO' || message.type == 'AUDIO')
          PopupMenuItem(
            value: 'save_as',
            child: Row(
              children: [
                Icon(Icons.download, color: Color(0xFFE8E7EA), size: 20),
                SizedBox(width: 12),
                Text(
                  'Save As...',
                  style: TextStyle(color: Color(0xFFE8E7EA), fontSize: 16),
                ),
              ],
            ),
          ),
        
        // Pin option
        // PopupMenuItem(
        //   value: 'pin',
        //   child: Row(
        //     children: [
        //       Icon(Icons.push_pin, color: Color(0xFFE8E7EA), size: 20),
        //       SizedBox(width: 12),
        //       Text(
        //         'Pin',
        //         style: TextStyle(color: Color(0xFFE8E7EA), fontSize: 16),
        //       ),
        //     ],
        //   ),
        // ),
        
        // Forward option
        // PopupMenuItem(
        //   value: 'forward',
        //   child: Row(
        //     children: [
        //       Icon(Icons.forward, color: Color(0xFFE8E7EA), size: 20),
        //       SizedBox(width: 12),
        //       Text(
        //         'Forward',
        //         style: TextStyle(color: Color(0xFFE8E7EA), fontSize: 16),
        //       ),
        //     ],
        //   ),
        // ),
        
        // Select option
        // PopupMenuItem(
        //   value: 'select',
        //   child: Row(
        //     children: [
        //       Icon(Icons.check_circle_outline, color: Color(0xFFE8E7EA), size: 20),
        //       SizedBox(width: 12),
        //       Text(
        //         'Select',
        //         style: TextStyle(color: Color(0xFFE8E7EA), fontSize: 16),
        //       ),
        //     ],
        //   ),
        // ),
        
        // Edit option (only for own text messages)
        if (isSentByMe && message.type == 'TEXT')
          PopupMenuItem(
            value: 'edit',
            child: Row(
              children: [
                Icon(Icons.edit, color: Color(0xFFE8E7EA), size: 20),
                SizedBox(width: 12),
                Text(
                  'Edit',
                  style: TextStyle(color: Color(0xFFE8E7EA), fontSize: 16),
                ),
              ],
            ),
          ),
        
        // Delete option (only for own messages)
        if (isSentByMe)
          PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete, color: Color(0xFFE74C3C), size: 20),
                SizedBox(width: 12),
                Text(
                  'Delete',
                  style: TextStyle(color: Color(0xFFE74C3C), fontSize: 16),
                ),
              ],
            ),
          ),
      ],
    ).then((value) {
      if (value != null) {
        switch (value) {
          case 'reply':
            _replyToMessage(message);
            break;
          case 'copy_media':
            _copyMedia(message);
            break;
          case 'copy_text':
            _copyText(message);
            break;
          case 'save_as':
            _saveMediaAs(message);
            break;
          case 'pin':
            _pinMessage(message);
            break;
          case 'forward':
            _forwardMessage(message);
            break;
          case 'select':
            _selectMessage(message);
            break;
          case 'edit':
            _editMessage(message);
            break;
          case 'delete':
            _deleteMessage(message);
            break;
        }
      }
    });
  }

  // Reply to message functionality
  void _replyToMessage(Message message) {
    // Set the message to reply to and focus the text input
    setState(() {
      _replyingToMessage = message;
    });
    _textController.clear();
    FocusScope.of(context).requestFocus(_textFocusNode);
    _showSnackBar('Replying to message');
  }

  // Copy media to clipboard
  void _copyMedia(Message message) {
    if (message.type == 'PHOTO') {
      _showSnackBar('Image copied to clipboard');
      // TODO: Implement actual image copy to clipboard
    } else if (message.type == 'AUDIO') {
      _showSnackBar('Audio file copied to clipboard');
      // TODO: Implement actual audio copy to clipboard
    }
  }

  // Copy text to clipboard
  void _copyText(Message message) {
    if (message.text != null && message.text!.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: message.text!));
      _showSnackBar('Text copied to clipboard');
    }else{
      if(message.caption != null && message.caption!.isNotEmpty){
        Clipboard.setData(ClipboardData(text: message.caption!));
        _showSnackBar('Caption copied to clipboard');
      }
    }
  }

  // Save media as file
  void _saveMediaAs(Message message) {
    if (message.type == 'PHOTO') {
      _showSnackBar('Saving image...');
      // TODO: Implement image download and save
    } else if (message.type == 'AUDIO') {
      _showSnackBar('Saving audio file...');
      // TODO: Implement audio download and save
    }
  }

  // Pin message functionality
  void _pinMessage(Message message) {
    _showSnackBar('Message pinned');
    // TODO: Implement actual message pinning
  }

  // Forward message functionality
  void _forwardMessage(Message message) {
    _showSnackBar('Forward message (feature coming soon)');
    // TODO: Show contact/chat selection dialog for forwarding
  }

  // Select message functionality
  void _selectMessage(Message message) {
    setState(() {
      if (_selectedMessages.contains(message.id)) {
        _selectedMessages.remove(message.id);
      } else {
        _selectedMessages.add(message.id);
      }
      _isSelectionMode = _selectedMessages.isNotEmpty;
    });
    
    if (_selectedMessages.isNotEmpty) {
      _showSnackBar('${_selectedMessages.length} message(s) selected');
    }
  }

  // Edit message functionality
  void _editMessage(Message message) {
    // Only allow editing text messages
    if (message.type != 'TEXT') {
      _showSnackBar('Only text messages can be edited');
      return;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        final TextEditingController editController = TextEditingController(text: message.text);
        
        return AlertDialog(
          backgroundColor: const Color(0xFF2A2A2A),
          title: const Text(
            'Edit Message',
            style: TextStyle(color: Color(0xFFE8E7EA)),
          ),
          content: TextField(
            controller: editController,
            style: const TextStyle(color: Color(0xFFE8E7EA)),
            maxLines: null,
            decoration: InputDecoration(
              hintText: 'Type your message...',
              hintStyle: TextStyle(color: Colors.grey.shade400),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade600),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade600),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF3498DB)),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            TextButton(
              onPressed: () {
                if (editController.text.trim().isNotEmpty) {
                  _updateMessage(message, editController.text.trim());
                  Navigator.of(context).pop();
                } else {
                  _showSnackBar('Message cannot be empty');
                }
              },
              child: const Text(
                'Save',
                style: TextStyle(color: Color(0xFF3498DB)),
              ),
            ),
          ],
        );
      },
    );
  }

  // Delete message functionality
  void _deleteMessage(Message message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2A2A2A),
          title: const Text(
            'Delete Message',
            style: TextStyle(color: Color(0xFFE8E7EA)),
          ),
          content: const Text(
            'Are you sure you want to delete this message? This action cannot be undone.',
            style: TextStyle(color: Color(0xFFE8E7EA)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            TextButton(
              onPressed: () {
                _removeMessage(message);
                Navigator.of(context).pop();
              },
              child: const Text(
                'Delete',
                style: TextStyle(color: Color(0xFFE74C3C)),
              ),
            ),
          ],
        );
      },
    );
  }

  // Update message via API
  void _updateMessage(Message message, String newText) async {
    try {
      // Update UI immediately for better UX
      setState(() {
        final index = _messages.indexWhere((msg) => msg.id == message.id);
        if (index != -1) {
          // Create new Message object with updated text
          final updatedMessage = Message(
            id: message.id,
            senderId: message.senderId,
            chatId: message.chatId,
            type: message.type,
            text: newText,
            caption: message.caption,
            fileId: message.fileId,
            tempImagePath: message.tempImagePath,
            createdAt: message.createdAt,
            updatedAt: DateTime.now(),
            sender: message.sender,
            isSent: message.isSent,
            isDelivered: message.isDelivered,
            isRead: message.isRead,
            isAudio: message.isAudio,
            audioDuration: message.audioDuration,
            referenceId: message.referenceId,
            statuses: message.statuses,
          );
          _messages[index] = updatedMessage;
        }
      });

      _showSnackBar('Message updated locally (API integration needed)');
    } catch (e) {
      print('Error updating message: $e');
      _showSnackBar('Failed to update message');
      
      // Revert UI changes on error
      setState(() {
        final index = _messages.indexWhere((msg) => msg.id == message.id);
        if (index != -1) {
          _messages[index] = message; // Revert to original
        }
      });
    }
  }

  // Remove message via API
  void _removeMessage(Message message) async {
    try {
      // Remove from UI immediately for better UX
      setState(() {
        _messages.removeWhere((msg) => msg.id == message.id);
      });

      _showSnackBar('Message deleted locally (API integration needed)');
    } catch (e) {
      print('Error deleting message: $e');
      _showSnackBar('Failed to delete message');
      
      // Revert UI changes on error
      setState(() {
        _messages.add(message);
        _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      });
    }
  }

  // Show snackbar helper
  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF2A2A2A),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // Show image popup when an image is tapped
  void _showImagePopup(BuildContext context, Message message) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black87,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Stack(
            children: [
              // Image display
              Center(
                child: Container(
                  margin: const EdgeInsets.all(20),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: InteractiveViewer(
                      panEnabled: true,
                      boundaryMargin: const EdgeInsets.all(20),
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: message.fileId != null
                        ? Image.network(
                            '${getEnv("API_BASE_URL")}/uploads/${message.fileId}',
                            fit: BoxFit.contain,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Container(
                                width: 200,
                                height: 200,
                                color: Colors.grey.shade800,
                                child: Center(
                                  child: CircularProgressIndicator(
                                    value: loadingProgress.expectedTotalBytes != null
                                        ? loadingProgress.cumulativeBytesLoaded /
                                            loadingProgress.expectedTotalBytes!
                                        : null,
                                    color: const Color(0xFF3498DB),
                                  ),
                                ),
                              );
                            },
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                width: 200,
                                height: 200,
                                color: Colors.grey.shade800,
                                child: const Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.broken_image,
                                        color: Colors.grey,
                                        size: 50,
                                      ),
                                      SizedBox(height: 8),
                                      Text(
                                        'Failed to load image',
                                        style: TextStyle(
                                          color: Colors.grey,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          )
                        : message.tempImagePath != null
                          ? Image.file(
                              File(message.tempImagePath!),
                              fit: BoxFit.contain,
                            )
                          : Container(
                              width: 200,
                              height: 200,
                              color: Colors.grey.shade800,
                              child: const Center(
                                child: Icon(
                                  Icons.image,
                                  color: Colors.grey,
                                  size: 50,
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
              ),
              // Close button
              Positioned(
                top: 40,
                right: 20,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ),
              // Caption if available
              if (message.caption != null && message.caption!.isNotEmpty)
                Positioned(
                  bottom: 40,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          message.caption!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          message.createdAt.toIso8601String().substring(11, 16),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _MediaPickerContent extends StatefulWidget {
  @override
  _MediaPickerContentState createState() => _MediaPickerContentState();
}

class _MediaPickerContentState extends State<_MediaPickerContent> {
  int _selectedTabIndex = 0;

  final List<MediaTab> _tabs = [
    MediaTab(
      title: 'Gallery',
      icon: Icons.photo_library,
      content: _GalleryContent(),
    ),
    MediaTab(
      title: 'File',
      icon: Icons.folder,
      content: _FileContent(),
    ),
    MediaTab(
      title: 'Location',
      icon: Icons.location_on,
      content: _LocationContent(),
    ),
    MediaTab(
      title: 'Conversion',
      icon: Icons.transform,
      content: _ConversionContent(),
    ),
    MediaTab(
      title: 'Contact',
      icon: Icons.contact_phone,
      content: _ContactContent(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Tab content (takes most of the space)
        Expanded(
          child: _tabs[_selectedTabIndex].content,
        ),

        // Tab buttons at bottom
        Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: _tabs.asMap().entries.map((entry) {
              final index = entry.key;
              final tab = entry.value;
              final isSelected = index == _selectedTabIndex;

              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedTabIndex = index;
                    });
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: isSelected
                              ? const Color(0xFF3498DB)
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          tab.icon,
                          color: isSelected
                              ? const Color(0xFF3498DB)
                              : const Color(0xFF6E6E6E),
                          size: 20,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          tab.title,
                          style: TextStyle(
                            color: isSelected
                                ? const Color(0xFF3498DB)
                                : const Color(0xFF6E6E6E),
                            fontSize: 12,
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class MediaTab {
  final String title;
  final IconData icon;
  final Widget content;

  MediaTab({
    required this.title,
    required this.icon,
    required this.content,
  });
}

// Gallery Content Widget
class _GalleryContent extends StatefulWidget {
  @override
  _GalleryContentState createState() => _GalleryContentState();
}

class _GalleryContentState extends State<_GalleryContent> {
  List<AssetEntity> _galleryImages = [];
  bool _isLoading = true;
  bool _hasPermission = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _requestPermissionAndLoadGallery();
  }

  Future<void> _requestPermissionAndLoadGallery() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Request photo library permission
      if (kIsWeb) {
        FilePickerResult? result =
            await FilePicker.platform.pickFiles(type: FileType.image);

        if (result != null) {
          String fileName = result.files.first.name;
          print(fileName);
          // Use fileName as needed
        }
      } else {
        final permission = await Permission.photos.request();
        print("Permission status: $permission");

        if (permission.isGranted) {
          setState(() {
            _hasPermission = true;
          });
          await _loadGalleryImages();
        } else {
          setState(() {
            _hasPermission = false;
            _isLoading = false;
          });
          print('Photo library permission denied');
        }
      }
    } catch (e) {
      print('Error requesting permission: $e');
      setState(() {
        _hasPermission = false;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadGalleryImages() async {
    try {
      // Get the photo library
      final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        onlyAll: true,
      );

      if (albums.isNotEmpty) {
        // Get the first album (usually "All Photos")
        final AssetPathEntity album = albums.first;

        // Get assets from the album
        final List<AssetEntity> assets = await album.getAssetListRange(
          start: 0,
          end: 50, // Load first 50 images
        );

        setState(() {
          _galleryImages = assets;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
        print('No albums found');
      }
    } catch (e) {
      print('Error loading gallery images: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );

      if (image != null) {
        print('Selected image from gallery: ${image.path}');
        // Handle the selected image
        // You can send it to the chat or process it further
      }
    } catch (e) {
      print('Error picking image from gallery: $e');
    }
  }

  Future<void> _takePhotoWithCamera() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
      );

      if (photo != null) {
        print('Photo taken with camera: ${photo.path}');
        // Handle the captured photo
        // You can send it to the chat or process it further
      }
    } catch (e) {
      print('Error taking photo: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: const Color(0xFF3498DB),
            ),
            const SizedBox(height: 16),
            const Text(
              'Loading gallery...',
              style: TextStyle(
                color: Color(0xFFE8E7EA),
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    if (!_hasPermission) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.photo_library,
              color: Color(0xFF6E6E6E),
              size: 64,
            ),
            const SizedBox(height: 16),
            const Text(
              'Gallery Permission Required',
              style: TextStyle(
                color: Color(0xFFE8E7EA),
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please grant photo library access to view your gallery',
              style: TextStyle(
                color: Color(0xFF6E6E6E),
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _requestPermissionAndLoadGallery,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3498DB),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Grant Permission'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Gallery header with camera button
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Gallery (${_galleryImages.length})',
                  style: const TextStyle(
                    color: Color(0xFFE8E7EA),
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              GestureDetector(
                onTap: _takePhotoWithCamera,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3498DB),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.camera_alt,
                        color: Colors.white,
                        size: 16,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Camera',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
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

        // Gallery grid
        Expanded(
          child: _galleryImages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.photo_library,
                        color: Color(0xFF6E6E6E),
                        size: 64,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No Images Found',
                        style: TextStyle(
                          color: Color(0xFFE8E7EA),
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Your gallery appears to be empty',
                        style: TextStyle(
                          color: Color(0xFF6E6E6E),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                    childAspectRatio: 1,
                  ),
                  itemCount: _galleryImages.length,
                  itemBuilder: (context, index) {
                    final asset = _galleryImages[index];
                    return GestureDetector(
                      onTap: () async {
                        // Get file from asset and show preview in parent
                        final file = await asset.file;
                        if (file != null) {
                          // ignore: use_build_context_synchronously
                          final parentState = context.findAncestorStateOfType<_ChatScreenPageState>();
                          if (parentState != null) {
                            parentState.setState(() {
                              parentState._pickedImage = XFile(file.path);
                              parentState._showMediaPicker = false;
                            });
                          }
                        }
                      },
                      onLongPress: () {
                        _pickImageFromGallery();
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade700,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Stack(
                            children: [
                              // Real gallery image
                              FutureBuilder<Uint8List?>(
                                future: asset.thumbnailData,
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState ==
                                      ConnectionState.waiting) {
                                    return Container(
                                      color: Colors.grey.shade700,
                                      child: const Center(
                                        child: CircularProgressIndicator(
                                          color: Color(0xFF3498DB),
                                        ),
                                      ),
                                    );
                                  }

                                  if (snapshot.hasError || !snapshot.hasData) {
                                    return Container(
                                      color: Colors.grey.shade700,
                                      child: const Icon(
                                        Icons.broken_image,
                                        color: Colors.grey,
                                        size: 32,
                                      ),
                                    );
                                  }

                                  return Image.memory(
                                    snapshot.data!,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    height: double.infinity,
                                  );
                                },
                              ),
                              // Selection overlay
                              Positioned(
                                top: 4,
                                right: 4,
                                child: Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.5),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// File Content Widget
class _FileContent extends StatefulWidget {
  @override
  _FileContentState createState() => _FileContentState();
}

class _FileContentState extends State<_FileContent> {
  List<FileSystemEntity> _files = [];
  bool _isLoading = true;
  String _currentPath = '';
  List<String> _pathHistory = [];

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() {
      _isLoading = true;
    });

    try {
      if (kIsWeb) {
        // For web, show file picker instead of directory listing
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // Get appropriate directory based on platform
      Directory directory;
      if (Platform.isAndroid) {
        // Try to get external storage directory first
        try {
          directory = Directory('/storage/emulated/0/Download');
          if (!await directory.exists()) {
            directory = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
          }
        } catch (e) {
          directory = await getApplicationDocumentsDirectory();
        }
      } else if (Platform.isIOS) {
        directory = await getApplicationDocumentsDirectory();
      } else {
        directory = await getApplicationDocumentsDirectory();
      }

      if (_currentPath.isEmpty) {
        _currentPath = directory.path;
      }

      final currentDirectory = Directory(_currentPath);
      final entities = await currentDirectory.list().toList();

      // Filter and sort files
      final files = <FileSystemEntity>[];
      final directories = <FileSystemEntity>[];

      for (final entity in entities) {
        if (entity is Directory) {
          // Skip hidden directories
          if (!entity.path.split('/').last.startsWith('.')) {
            directories.add(entity);
          }
        } else if (entity is File) {
          // Skip hidden files and system files
          final fileName = entity.path.split('/').last;
          if (!fileName.startsWith('.') && !fileName.startsWith('~')) {
            files.add(entity);
          }
        }
      }

      // Sort directories and files separately
      directories.sort((a, b) => a.path.split('/').last.toLowerCase().compareTo(b.path.split('/').last.toLowerCase()));
      files.sort((a, b) => a.path.split('/').last.toLowerCase().compareTo(b.path.split('/').last.toLowerCase()));

      setState(() {
        _files = [...directories, ...files];
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading files: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _navigateToDirectory(String path) {
    _pathHistory.add(_currentPath);
    _currentPath = path;
    _loadFiles();
  }

  void _navigateBack() {
    if (_pathHistory.isNotEmpty) {
      _currentPath = _pathHistory.removeLast();
      _loadFiles();
    }
  }

  Future<void> _pickFileFromDevice() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        print('Selected file: ${file.name}, Path: ${file.path}');
        
        // Here you can handle the selected file
        // For example, send it through the chat
        if (file.path != null) {
          _showFileSelectedDialog(file.name, file.path!);
        }
      }
    } catch (e) {
      print('Error picking file: $e');
    }
  }

  void _showFileSelectedDialog(String fileName, String filePath) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2A2A2A),
          title: const Text(
            'Send File',
            style: TextStyle(color: Color(0xFFE8E7EA)),
          ),
          content: Text(
            'Do you want to send "$fileName"?',
            style: const TextStyle(color: Color(0xFFE8E7EA)),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _sendFile(filePath, fileName);
              },
              child: const Text(
                'Send',
                style: TextStyle(color: Color(0xFF3498DB)),
              ),
            ),
          ],
        );
      },
    );
  }

  void _sendFile(String filePath, String fileName) {
    // TODO: Implement file sending logic
    print('Sending file: $fileName from path: $filePath');
    // You can integrate this with your existing message sending logic
  }

  String _getFileIcon(String path) {
    final extension = path.split('.').last.toLowerCase();
    switch (extension) {
      case 'pdf':
        return '📄';
      case 'doc':
      case 'docx':
        return '📝';
      case 'xls':
      case 'xlsx':
        return '📊';
      case 'ppt':
      case 'pptx':
        return '📽️';
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return '🖼️';
      case 'mp4':
      case 'avi':
      case 'mov':
        return '🎥';
      case 'mp3':
      case 'wav':
      case 'm4a':
        return '🎵';
      case 'zip':
      case 'rar':
      case '7z':
        return '🗜️';
      case 'txt':
        return '📋';
      default:
        return '📁';
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.folder_open,
              color: Color(0xFF3498DB),
              size: 64,
            ),
            const SizedBox(height: 16),
            const Text(
              'Select File',
              style: TextStyle(
                color: Color(0xFFE8E7EA),
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Click below to choose a file from your device',
              style: TextStyle(
                color: Color(0xFF6E6E6E),
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _pickFileFromDevice,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3498DB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Choose File'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Header with path and back button
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: Color(0xFF2A2A2A),
            border: Border(
              bottom: BorderSide(color: Color(0xFF3A3A3A), width: 1),
            ),
          ),
          child: Row(
            children: [
              if (_pathHistory.isNotEmpty)
                GestureDetector(
                  onTap: _navigateBack,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3498DB).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.arrow_back,
                      color: Color(0xFF3498DB),
                      size: 20,
                    ),
                  ),
                ),
              if (_pathHistory.isNotEmpty) const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Current Folder',
                      style: TextStyle(
                        color: Color(0xFF6E6E6E),
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      _currentPath.split('/').last.isEmpty 
                          ? 'Root' 
                          : _currentPath.split('/').last,
                      style: const TextStyle(
                        color: Color(0xFFE8E7EA),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: _pickFileFromDevice,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3498DB),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.file_open,
                        color: Colors.white,
                        size: 16,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Pick File',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
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

        // File list
        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFF3498DB),
                  ),
                )
              : _files.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.folder_open,
                            color: Color(0xFF6E6E6E),
                            size: 64,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'No Files Found',
                            style: TextStyle(
                              color: Color(0xFFE8E7EA),
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'This directory appears to be empty',
                            style: TextStyle(
                              color: Color(0xFF6E6E6E),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _files.length,
                      itemBuilder: (context, index) {
                        final entity = _files[index];
                        final isDirectory = entity is Directory;
                        final name = entity.path.split('/').last;

                        return GestureDetector(
                          onTap: () {
                            if (isDirectory) {
                              _navigateToDirectory(entity.path);
                            } else {
                              _showFileSelectedDialog(name, entity.path);
                            }
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2A2A2A),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: isDirectory 
                                        ? const Color(0xFFF39C12).withOpacity(0.2)
                                        : const Color(0xFF3498DB).withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Center(
                                    child: isDirectory
                                        ? const Icon(
                                            Icons.folder,
                                            color: Color(0xFFF39C12),
                                            size: 24,
                                          )
                                        : Text(
                                            _getFileIcon(entity.path),
                                            style: const TextStyle(fontSize: 20),
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: const TextStyle(
                                          color: Color(0xFFE8E7EA),
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (!isDirectory) ...[
                                        const SizedBox(height: 4),
                                        FutureBuilder<FileStat>(
                                          future: entity.stat(),
                                          builder: (context, snapshot) {
                                            if (snapshot.hasData) {
                                              return Text(
                                                _formatFileSize(snapshot.data!.size),
                                                style: TextStyle(
                                                  color: Colors.grey.shade400,
                                                  fontSize: 14,
                                                ),
                                              );
                                            }
                                            return Text(
                                              'Loading...',
                                              style: TextStyle(
                                                color: Colors.grey.shade400,
                                                fontSize: 14,
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                if (isDirectory)
                                  const Icon(
                                    Icons.arrow_forward_ios,
                                    color: Color(0xFF6E6E6E),
                                    size: 16,
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

// Location Content Widget
class _LocationContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                Icons.location_on,
                color: const Color(0xFFE74C3C),
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Location ${index + 1}',
                      style: const TextStyle(
                        color: Color(0xFFE8E7EA),
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      '123 Main St, City, Country',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// Conversion Content Widget
class _ConversionContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 8,
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                Icons.transform,
                color: const Color(0xFFF39C12),
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Conversion ${index + 1}',
                      style: const TextStyle(
                        color: Color(0xFFE8E7EA),
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      'Currency, Unit, etc.',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// Contact Content Widget
class _ContactContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 6,
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.grey.shade700,
                ),
                child: ClipOval(
                  child: Image.asset(
                    'image${(index % 11) + 1}.png',
                    fit: BoxFit.cover,
                  ).localAsset(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Contact ${index + 1}',
                      style: const TextStyle(
                        color: Color(0xFFE8E7EA),
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      '+1 234 567 890${index + 1}',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
