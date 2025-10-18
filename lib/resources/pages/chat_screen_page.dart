import 'dart:ui';
import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
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
import '/resources/pages/profile_details_page.dart';
import 'package:file_picker/file_picker.dart';
import "../../app/utils/chat.dart";
import "../../app/utils.dart";
import "/app/services/chat_service.dart";
import 'package:audioplayers/audioplayers.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:open_filex/open_filex.dart';

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
  XFile? _pickedVideo;
  // Document selection
  String? _pickedDocumentPath;
  String? _pickedDocumentName;
  bool _isRecording = false;
  late Record _audioRecorder;
  Timer? _recordingTimer;
  int _recordingDuration = 0;

  // Chat data
  Chat? _chat;
  String _userName = 'Ahmad';
  String? _userImage;
  String? _description;
  bool _isOnline = false;
  Set<int> _typingUsers = {};

  String? currentDay; // Track current day for day separators
  bool _isShowingFloatingHeader = false; // Control visibility of the floating header
  Timer? _headerVisibilityTimer; // Timer to hide header after period of inactivity

  // WebSocket integration
  StreamSubscription<Map<String, dynamic>>? _wsSubscription;
  StreamSubscription<Map<String, dynamic>>? _notificationSubscription;
  StreamSubscription<bool>? _connectionStatusSubscription;

  bool _isWebSocketConnected = false;

  List<Message> _messages = [];
  int? _currentUserId;
  bool _isLoadingAtTop = false; // Track loading state when at top

  AudioPlayer? _audioPlayer;
  int? _playingMessageId;
  bool _isAudioPlaying = false;
  Duration _audioPosition = Duration.zero;
  Duration _audioDuration = Duration.zero;
  
  // Audio player subscriptions
  StreamSubscription<Duration>? _audioDurationSubscription;
  StreamSubscription<Duration>? _audioPositionSubscription;
  StreamSubscription<void>? _audioCompleteSubscription;

  // Message interaction state
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFocusNode = FocusNode();
  Set<int> _selectedMessages = {};

  // Media preview state
  bool _showFullscreenPreview = false;
  String? _previewMediaType; // 'image' or 'video'
  // Video preview controllers
  VideoPlayerController? _previewVideoController;
  ChewieController? _previewChewieController;
  bool _videoPreviewError = false;
  // Inline video message state
  // (Deprecated inline playback maps kept for potential future revert; currently fullscreen playback only)
  final Map<int, VideoPlayerController> _videoMsgControllers = {}; // unused now
  final Map<int, ChewieController> _videoMsgChewie = {}; // unused now
  final Set<int> _videoThumbInitializing = {};
  final Map<int, VideoPlayerController> _videoThumbControllers = {}; // lightweight controllers for thumbnails
  final Set<int> _videoThumbErrors = {};

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
          print("Description: ${navigationData['description']}");
          
          if (chatId != null) {
            _chat = await ChatService().getChatDetails(chatId);
            final messages = await ChatService().getChatMessages(chatId);
            
            _description  = navigationData['description'] as String? ?? '';
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
                // _isVerified = false; (flag removed)
                _typingUsers = _chat!.typingUsers;
              }
            }
            setState(() {
              _messages = messages;
            });

            // Use a more robust initial scroll to bottom
            _scrollToBottomInitial();
            await _connectToWebSocket();
            
            // Register this chat screen with ChatService to prevent message duplication
            if (_chat != null) {
              ChatService().registerActiveChatScreen(_chat!.id);
            }
            
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
          if (mounted) {
            _handleIncomingMessage(messageData);
          }
        });

        _notificationSubscription =
            WebSocketService().notificationStream.listen((notificationData) {
          if (mounted) {
            _handleIncomingNotification(notificationData);
          }
        });

        _connectionStatusSubscription = WebSocketService().connectionStatusStream.listen((isConnected) {
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

    if (mounted) {
      setState(() {
        _isLoadingAtTop = true;
      });
    }

    print("🔄 Loading more messages from top...");

    // Simulate loading delay (replace with actual API call)
    // await Future.delayed(const Duration(seconds: 2));
    var chatService = ChatService();
    final List<Message> messages =
        await chatService.loadPreviousMessages(_chat!.id, _messages.first.id);

    // Here you would typically load older messages from your API
    // For now, we'll just simulate the loading completion
    if (mounted) {
      setState(() {
        _isLoadingAtTop = false;
        _messages.insertAll(0, messages);
      });
    }

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
            print("Found reference message, updating: ${newMessage.referenceId}");
            _messages[index] = newMessage;
            
            // Update chat list when replacing a pending message
            ChatService().updateChatListWithMessage(_chat!.id, newMessage);
            return;
          }
        }
          print("Adding new message: ${newMessage.id}");
        _messages.add(newMessage);
        
        // Update chat list with the new message
        if (_chat != null) {
          ChatService().updateChatListWithMessage(_chat!.id, newMessage);
        }
        
        if (newMessage.senderId != _currentUserId) {
          WebSocketService().sendReadReceipt([newMessage.id]);
        }
      }
    });
    _scrollToBottomForNewMessage();
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
    // Unregister this chat screen from ChatService
    if (_chat != null) {
      ChatService().unregisterActiveChatScreen(_chat!.id);
    }
    
    _messageController.removeListener(_onTextChanged);
    _scrollController.removeListener(_onScroll);
    _messageController.dispose();
    _scrollController.dispose();

    // Clean up WebSocket subscriptions but keep the service running
    // as it might be used by other screens
    _wsSubscription?.cancel();
    _notificationSubscription?.cancel();
    _connectionStatusSubscription?.cancel();
    _recordingTimer?.cancel();
    _headerVisibilityTimer?.cancel(); // Dispose the header visibility timer
    _audioRecorder.dispose();
    
    // Cancel audio player subscriptions before disposing
    _audioDurationSubscription?.cancel();
    _audioPositionSubscription?.cancel();
    _audioCompleteSubscription?.cancel();
    _audioPlayer?.dispose();
    _previewChewieController?.dispose();
    _previewVideoController?.dispose();
    for (final c in _videoMsgChewie.values) { c.dispose(); }
    for (final vc in _videoMsgControllers.values) { vc.dispose(); }
    super.dispose();
  }

  Future<void> _playAudioMessage(Message message) async {
    try {
      // Stop any currently playing audio
      if (_audioPlayer != null) {
        await _audioPlayer!.stop();
        
        // Cancel existing subscriptions
        _audioDurationSubscription?.cancel();
        _audioPositionSubscription?.cancel();
        _audioCompleteSubscription?.cancel();
        
        await _audioPlayer!.dispose();
      }
      
      _audioPlayer = AudioPlayer();

      if (mounted) {
        setState(() {
          _playingMessageId = message.id;
          _isAudioPlaying = true;
          _audioPosition = Duration.zero;
          _audioDuration = Duration.zero;
        });
      }

      // Cancel any existing subscriptions
      _audioDurationSubscription?.cancel();
      _audioPositionSubscription?.cancel();
      _audioCompleteSubscription?.cancel();

      // Listen to duration changes
      _audioDurationSubscription = _audioPlayer!.onDurationChanged.listen((duration) {
        if (mounted) {
          setState(() {
            _audioDuration = duration;
          });
        }
      });

      // Listen to position changes
      _audioPositionSubscription = _audioPlayer!.onPositionChanged.listen((position) {
        if (mounted) {
          setState(() {
            _audioPosition = position;
          });
        }
      });

      // Listen to completion
      _audioCompleteSubscription = _audioPlayer!.onPlayerComplete.listen((event) {
        if (mounted) {
          setState(() {
            _isAudioPlaying = false;
            _playingMessageId = null;
            _audioPosition = Duration.zero;
          });
        }
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
      if (mounted) {
        setState(() {
          _isAudioPlaying = false;
        });
      }
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


  void _closeImagePreview() {
    setState(() {
      _pickedImage = null;
      _pickedVideo = null;
    });
  }

  void _showFullscreenMediaPreview() {
    setState(() {
      _showFullscreenPreview = true;
      _previewMediaType = _pickedImage != null ? 'image' : 'video';
    });

    if (_previewMediaType == 'video' && _pickedVideo != null) {
      _initializePreviewVideo(_pickedVideo!.path);
    }
  }

  void _closeFullscreenPreview() {
    setState(() {
      _showFullscreenPreview = false;
      _previewMediaType = null;
    });

    // Dispose preview controllers when closing
    _previewChewieController?.dispose();
    _previewVideoController?.dispose();
    _previewChewieController = null;
    _previewVideoController = null;
    _videoPreviewError = false;
  }

  Future<void> _initializePreviewVideo(String pathOrId) async {
    // Safely dispose any existing controllers
    try {
      _previewChewieController?.dispose();
      if (_previewVideoController != null) {
        await _previewVideoController!.dispose();
      }
    } catch (_) {}
    _previewChewieController = null;
    _previewVideoController = null;
    setState(() {
      _videoPreviewError = false;
    });
    // Defer actual initialization to next frame to ensure platform channel is ready
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        // Decide whether this is a local file path or an id referencing a remote file
        VideoPlayerController controller;
        String? resolvedInfo;

        bool looksLikeLocalPath = pathOrId.contains('/') || pathOrId.contains('.') || pathOrId.startsWith('file:');
        if (looksLikeLocalPath) {
          final file = File(pathOrId);
            if (!await file.exists()) {
            throw Exception('Video file missing at path: ' + pathOrId);
          }
          resolvedInfo = 'local:' + pathOrId;
          controller = VideoPlayerController.file(file);
        } else {
          // Treat as id - build network URL like other media (mirroring audio/photo logic)
          final baseUrl = getEnv("API_BASE_URL");
          if (baseUrl == null) {
            throw Exception('API_BASE_URL not set for video id: ' + pathOrId);
          }
          final url = baseUrl.endsWith('/') ? baseUrl + 'files/' + pathOrId : baseUrl + '/files/' + pathOrId;
          resolvedInfo = 'network:' + url;
          controller = VideoPlayerController.network(url);
        }

        debugPrint('Initializing preview video -> ' + resolvedInfo);

        _previewVideoController = controller;
        await controller.initialize();
        if (!mounted) return;
        
        _previewChewieController = ChewieController(
          videoPlayerController: controller,
          autoPlay: true,
          looping: false,
          allowFullScreen: false,
          allowMuting: true,
          materialProgressColors: ChewieProgressColors(
            playedColor: Colors.blueAccent,
            handleColor: Colors.blue,
            backgroundColor: Colors.white24,
            bufferedColor: Colors.blueGrey,
          ),
        );
        setState(() {});
      } catch (e) {
        debugPrint('Video preview init error: $e');
        if (mounted) {
          setState(() {
            _videoPreviewError = true;
          });
        }
      }
    });
  }


  void _sendMessage() async {
    // Allow sending if text OR any media/document selected
    if (_messageController.text.trim().isEmpty &&
        _pickedImage == null &&
        _pickedVideo == null &&
        _pickedDocumentPath == null) {
      return;
    }

    final messageText = _messageController.text.trim();
      print("Sending message: $messageText");
      print("WebSocket connected: $_isWebSocketConnected");
      print("Chat ID: ${_chat?.id}");
      print("Current User ID: $_pickedImage");

      // Add message to UI immediately for better UX
      final referenceId = DateTime.now().millisecondsSinceEpoch;
      final type = _pickedImage != null
          ? "PHOTO"
          : (_pickedVideo != null
              ? "VIDEO"
              : (_pickedDocumentPath != null ? "DOCUMENT" : "TEXT"));
      
      setState(() {
        final now = DateTime.now();
        final newMessage = Message(
          id: DateTime.now().millisecondsSinceEpoch, // Temporary ID
          senderId: _currentUserId ?? 0,
          chatId: _chat?.id ?? 0,
          type: type,
          // text: type == 'DOCUMENT' ? (_pickedDocumentName ?? 'Document') : messageText,
          caption: (type == 'PHOTO' || type == 'VIDEO' || type == 'DOCUMENT')
              ? (messageText.isNotEmpty ? messageText : null)
              : null,
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
          tempVideoPath: _pickedVideo?.path,
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
        
        // Update chat list with the pending message
        if (_chat != null) {
          ChatService().updateChatListWithMessage(_chat!.id, newMessage);
        }
        
        print('✅ Message added to list. Total messages: ${_messages.length}');
        print('Message text: "${newMessage.text}"');
      });

      _messageController.clear();
      _scrollToBottomForOwnMessage();

      final shouldSendViaWebSocket =  WebSocketService().isConnected && _pickedImage == null && _pickedVideo == null && _pickedDocumentPath == null;
      print('🔍 Should send via WebSocket: $shouldSendViaWebSocket');

      if (shouldSendViaWebSocket) {
        print('🚀 === SEND MESSAGE TRIGGERED ===');
        WebSocketService().sendMessage(messageText, _chat!.id, referenceId);
        print('✅ SendMessage method called');
      } else if (_chat != null) {
        try {
          
          await apiService.sendMessage(
            chatId: _chat!.id,
            text: (type == 'TEXT' ? messageText : messageText),
            caption: (type == 'PHOTO' || type == 'VIDEO' || type == 'DOCUMENT')
                ? (messageText.isNotEmpty ? messageText : null)
                : null,
            filePath: _pickedImage?.path ?? _pickedVideo?.path ?? _pickedDocumentPath,
            referenceId: referenceId,
            type: type,
          );
          print("Message sent via API");
          if (mounted) {
            setState(() {
              _pickedImage = null; // Clear the picked image after sending
              _pickedVideo = null; // Clear the picked video after sending
              _pickedDocumentPath = null;
              _pickedDocumentName = null;
            });
          }
          
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
        
        // Update chat list with the audio message
        if (_chat != null) {
          ChatService().updateChatListWithMessage(_chat!.id, newMessage);
        }
        
        print('✅ Audio message added to list. Total messages: ${_messages.length}');
      });
      
      _scrollToBottomForOwnMessage();
      
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

 /// Scroll to bottom specifically for new messages with proper timing
 void _scrollToBottomForNewMessage() {
   WidgetsBinding.instance.addPostFrameCallback((_) async {
     if (!mounted || !_scrollController.hasClients) return;
     
     // Check if user is near the bottom (within 150 pixels to account for padding)
     final currentPosition = _scrollController.position.pixels;
     final maxExtent = _scrollController.position.maxScrollExtent;
     final isNearBottom = (maxExtent - currentPosition) <= 150;
     
     if (!isNearBottom) {
       // User is scrolled up, don't disturb them
       return;
     }
     
     // Wait longer for the new message to be fully rendered
     await Future.delayed(const Duration(milliseconds: 300));
     
     if (mounted && _scrollController.hasClients) {
       try {
         // Get fresh max extent after delay
         final newMaxExtent = _scrollController.position.maxScrollExtent;
         
         // Animate to the very bottom
         await _scrollController.animateTo(
           newMaxExtent,
           duration: const Duration(milliseconds: 500),
           curve: Curves.easeOutCubic,
         );
         
         // Multiple verification attempts to ensure we reach the bottom
         for (int i = 0; i < 5; i++) {
           await Future.delayed(Duration(milliseconds: 150 * (i + 1)));
           if (mounted && _scrollController.hasClients) {
             final currentMaxExtent = _scrollController.position.maxScrollExtent;
             final currentPosition = _scrollController.position.pixels;
             
             // If we're not at the very bottom or extent changed, scroll again
             if (currentPosition < currentMaxExtent - 2 || currentMaxExtent != newMaxExtent) {
               await _scrollController.animateTo(
                 currentMaxExtent,
                 duration: const Duration(milliseconds: 300),
                 curve: Curves.easeOut,
               );
             } else {
               break; // We've reached the stable bottom
             }
           }
         }
       } catch (e) {
         // Fallback with multiple attempts
         for (int i = 0; i < 8; i++) {
           await Future.delayed(Duration(milliseconds: 200 * (i + 1)));
           if (mounted && _scrollController.hasClients) {
             try {
               _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
               break;
             } catch (e) {
               continue;
             }
           }
         }
       }
     }
   });
 }

 /// Force scroll to bottom for user's own messages (always scroll)
 void _scrollToBottomForOwnMessage() {
   WidgetsBinding.instance.addPostFrameCallback((_) async {
     // Wait longer for the new message to be fully rendered
     await Future.delayed(const Duration(milliseconds: 350));
     
     if (mounted && _scrollController.hasClients) {
       try {
         // Get the maximum scroll extent
         final maxExtent = _scrollController.position.maxScrollExtent;
         
         // Always animate to bottom for user's own messages
         await _scrollController.animateTo(
           maxExtent,
           duration: const Duration(milliseconds: 500),
           curve: Curves.easeOutCubic,
         );
         
         // Multiple verification attempts to ensure we reach the absolute bottom
         for (int i = 0; i < 6; i++) {
           await Future.delayed(Duration(milliseconds: 150 * (i + 1)));
           if (mounted && _scrollController.hasClients) {
             final currentMaxExtent = _scrollController.position.maxScrollExtent;
             final currentPosition = _scrollController.position.pixels;
             
             // If we're not at the very bottom or extent changed, scroll again
             if (currentPosition < currentMaxExtent - 2 || currentMaxExtent != maxExtent) {
               await _scrollController.animateTo(
                 currentMaxExtent,
                 duration: const Duration(milliseconds: 300),
                 curve: Curves.easeOut,
               );
             } else {
               break; // We've reached the stable bottom
             }
           }
         }
       } catch (e) {
         // Robust fallback with multiple attempts
         for (int i = 0; i < 10; i++) {
           await Future.delayed(Duration(milliseconds: 200 * (i + 1)));
           if (mounted && _scrollController.hasClients) {
             try {
               _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
               break;
             } catch (e) {
               continue;
             }
           }
         }
       }
     }
   });
 }

 /// Scroll to bottom for initial message load
 void _scrollToBottomInitial() {
   WidgetsBinding.instance.addPostFrameCallback((_) async {
     // Wait longer for initial render as there might be many messages
     await Future.delayed(const Duration(milliseconds: 400));
     
     if (mounted && _scrollController.hasClients) {
       try {
         // Jump to bottom immediately for initial load
         final maxExtent = _scrollController.position.maxScrollExtent;
         _scrollController.jumpTo(maxExtent);
         
         // Multiple verification attempts to ensure we reach the bottom
         for (int i = 0; i < 5; i++) {
           await Future.delayed(Duration(milliseconds: 150 * (i + 1)));
           if (mounted && _scrollController.hasClients) {
             final currentMaxExtent = _scrollController.position.maxScrollExtent;
             final currentPosition = _scrollController.position.pixels;
             
             // If not at bottom or extent changed, scroll again
             if (currentPosition < currentMaxExtent - 2 || currentMaxExtent != maxExtent) {
               _scrollController.jumpTo(currentMaxExtent);
             } else {
               break; // We've reached the stable bottom
             }
           }
         }
       } catch (e) {
         // Robust fallback with increasing delays
         for (int i = 0; i < 10; i++) {
           await Future.delayed(Duration(milliseconds: 200 * (i + 1)));
           if (mounted && _scrollController.hasClients) {
             try {
               _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
               break;
             } catch (e) {
               continue;
             }
           }
         }
       }
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
          // _recordedAudioPath = recordingPath; (removed field)
        });
        
        // Start recording timer
        _recordingTimer = Timer.periodic(Duration(seconds: 1), (timer) {
          if (mounted) {
            setState(() {
              _recordingDuration++;
            });
          } else {
            timer.cancel(); // Cancel timer if widget is disposed
          }
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
  // _recordedAudioPath = null; (removed field)
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
  // _recordedAudioPath = null; (removed field)
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
                        GestureDetector(
                          onTap: () => routeTo(ProfileDetailsPage.path, data: {
                            'partner': _chat?.partner,
                            'isGroup': _chat?.type == 'CHANNEL',
                            'chatId': _chat?.id,
                            'userId': _chat?.partner?.id,
                            'userName': _userName,
                            'userImage': _userImage,
                            'isOnline': _isOnline,
                            'description': _description,
                          }),
                          child: Container(
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
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => routeTo(ProfileDetailsPage.path, data: {
                              'partner': _chat?.partner,
                              'isGroup': _chat?.type == 'CHANNEL',
                              'chatId': _chat?.id,
                              'userId': _chat?.partner?.id,
                              'userName': _userName,
                              'userImage': _userImage,
                              'isOnline': _isOnline,
                              'description': _description,
                            }),
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
                              Builder(builder: (_) {
                                final isChannel = _chat?.type == 'CHANNEL';
                                if (isChannel) {
                                  final membersCount = _chat?.participants.length ?? 0;
                                  return Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        '$membersCount Members',
                                        style: TextStyle(
                                          color: Colors.grey.shade500,
                                          fontSize: 8,
                                        ),
                                      ),
                                    ],
                                  );
                                }
                                return Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
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
                                );
                              }),
                            ],
                            ),
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
                                    // Media / Document preview above input
                                    if (_pickedImage != null || _pickedVideo != null || _pickedDocumentPath != null)
                                      Container(
                                        margin: const EdgeInsets.only(bottom: 12),
                                        child: Builder(
                                          builder: (_) {
                                            if (_pickedDocumentPath != null) {
                                              return Container(
                                                padding: const EdgeInsets.all(12),
                                                decoration: BoxDecoration(
                                                  borderRadius: BorderRadius.circular(12),
                                                  color: Colors.orange.withOpacity(0.08),
                                                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                                                ),
                                                child: Row(
                                                  children: [
                                                    const Icon(Icons.insert_drive_file, color: Colors.orange, size: 24),
                                                    const SizedBox(width: 12),
                                                    Expanded(
                                                      child: Text(
                                                        _pickedDocumentName ?? 'Document selected',
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: const TextStyle(
                                                          color: Colors.orange,
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                      ),
                                                    ),
                                                    GestureDetector(
                                                      onTap: _clearPickedDocument,
                                                      child: Container(
                                                        padding: const EdgeInsets.all(4),
                                                        decoration: BoxDecoration(
                                                          color: Colors.red.withOpacity(0.1),
                                                          shape: BoxShape.circle,
                                                          border: Border.all(color: Colors.red.withOpacity(0.3)),
                                                        ),
                                                        child: const Icon(Icons.close, color: Colors.red, size: 16),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            }
                                            return GestureDetector(
                                              onTap: _showFullscreenMediaPreview,
                                              child: Container(
                                                padding: const EdgeInsets.all(12),
                                                decoration: BoxDecoration(
                                                  borderRadius: BorderRadius.circular(12),
                                                  color: Colors.green.withOpacity(0.1),
                                                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                                                ),
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      _pickedImage != null ? Icons.image : Icons.videocam,
                                                      color: Colors.green,
                                                      size: 24,
                                                    ),
                                                    const SizedBox(width: 12),
                                                    Expanded(
                                                      child: Text(
                                                        _pickedImage != null
                                                            ? 'Image selected - Tap to preview'
                                                            : 'Video selected - Tap to preview',
                                                        style: const TextStyle(
                                                          color: Colors.green,
                                                          fontWeight: FontWeight.w500,
                                                        ),
                                                      ),
                                                    ),
                                                    GestureDetector(
                                                      onTap: _closeImagePreview,
                                                      child: Container(
                                                        padding: const EdgeInsets.all(4),
                                                        decoration: BoxDecoration(
                                                          color: Colors.red.withOpacity(0.1),
                                                          shape: BoxShape.circle,
                                                          border: Border.all(color: Colors.red.withOpacity(0.3)),
                                                        ),
                                                        child: const Icon(
                                                          Icons.close,
                                                          color: Colors.red,
                                                          size: 16,
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
                                                suffixIcon: (_hasText || _pickedImage != null || _pickedVideo != null || _pickedDocumentPath != null)
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
          // Fullscreen media preview overlay
          if (_showFullscreenPreview)
            _buildFullscreenMediaPreview(),
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
      
      case "VIDEO":
        return _buildVideoMessage(message);
      case "DOCUMENT":
        return _buildDocumentMessage(message);
        
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
                    gradient: isSentByMe
                      ? const LinearGradient(
                        colors: [Color(0xFF18365B), Color(0xFF163863)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                      : const LinearGradient(
                        colors: [Color(0xFF3C434C), Color(0xFF262D35)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
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
                      TextUtils.buildTextWithLinks(
                        message.type == "TEXT"
                            ? (message.text ?? '')
                            : (message.caption ?? ''),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                        linkStyle: const TextStyle(
                          color: Colors.blue,
                          fontSize: 16,
                          decoration: TextDecoration.underline,
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
                            TextUtils.buildTextWithLinks(
                              message.caption!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                              linkStyle: const TextStyle(
                                color: Colors.blue,
                                fontSize: 14,
                                decoration: TextDecoration.underline,
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

  Widget _buildVideoMessage(Message message) {
    final bool isSentByMe = _currentUserId != null && message.senderId == _currentUserId;
  // fileId/tempVideoPath not needed in new thumbnail+fullscreen approach

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: isSentByMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isSentByMe) const SizedBox(width: 10),
          Flexible(
            child: GestureDetector(
              onTapDown: (TapDownDetails details) {
                _showMessageContextMenu(context, message, details.globalPosition);
              },
              onSecondaryTapDown: (TapDownDetails details) { // Desktop/web right-click
                _showMessageContextMenu(context, message, details.globalPosition);
              },
              onLongPress: () {
                final RenderBox renderBox = context.findRenderObject() as RenderBox;
                final position = renderBox.localToGlobal(Offset.zero);
                _showMessageContextMenu(context, message, position);
              },
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.6,
                  minWidth: 200,
                ),
                child: Column(
                  crossAxisAlignment: isSentByMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                     
                     
                    // Video content
                    Container(
                      decoration: BoxDecoration(
                        color: isSentByMe ? const Color(0xFF18365B) : const Color(0xFF404040),
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(20),
                          topRight: const Radius.circular(20),
                          bottomLeft: Radius.circular(isSentByMe ? 20 : 5),
                          bottomRight: Radius.circular(isSentByMe ? 5 : 20),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Video preview/thumbnail
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () async {
                              // Open fullscreen preview instead of inline playback
                              await _openFullscreenVideo(message);
                            },
                            child: Container(
                            width: double.infinity,
                            height: 200,
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(20),
                                topRight: const Radius.circular(20),
                                bottomLeft: Radius.circular(message.caption?.isNotEmpty == true ? 0 : (isSentByMe ? 20 : 5)),
                                bottomRight: Radius.circular(message.caption?.isNotEmpty == true ? 0 : (isSentByMe ? 5 : 20)),
                              ),
                            ),
                            child: Stack(
                              children: [
                                // Video area: if initialized show player else placeholder
                                ClipRRect(
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(20),
                                    topRight: const Radius.circular(20),
                                    bottomLeft: Radius.circular(message.caption?.isNotEmpty == true ? 0 : (isSentByMe ? 20 : 5)),
                                    bottomRight: Radius.circular(message.caption?.isNotEmpty == true ? 0 : (isSentByMe ? 5 : 20)),
                                  ),
                                  child: _buildVideoThumbnail(message),
                                ),
                                Center(
                                  child: Container(
                                    width: 60,
                                    height: 60,
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.55),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.play_arrow, color: Colors.white, size: 36),
                                  ),
                                ),
                                // Video duration indicator (top right)
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.7),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.videocam,
                                          color: Colors.white,
                                          size: 12,
                                        ),
                                        SizedBox(width: 2),
                                        Text(
                                          'VIDEO',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
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
            ),
                          // Caption
                          (message.caption?.isNotEmpty ?? false)
                              ? Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: TextUtils.buildTextWithLinks(
                                    message.caption!,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                    ),
                                    linkStyle: const TextStyle(
                                      color: Colors.blue,
                                      fontSize: 14,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ],
                      ),
                    ),
                    // Timestamp and status
                    Padding(
                      padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            message.createdAt.toIso8601String().substring(11, 16),
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.6),
                              fontSize: 11,
                            ),
                          ),
                          if (isSentByMe) ...[
                            const SizedBox(width: 4),
                            Icon(
                              message.isRead
                                  ? Icons.done_all
                                  : message.isDelivered
                                      ? Icons.done_all
                                      : Icons.done,
                              color: message.isRead ? Colors.blue : Colors.white.withOpacity(0.6),
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

  Widget _buildVideoThumbnail(Message message) {
    final id = message.id;
  // Unused locals removed (fileId/localPath)

    // Use existing thumb controller if initialized
    final existing = _videoThumbControllers[id];
    if (existing != null && existing.value.isInitialized) {
      // Expand to fill the container and crop with BoxFit.cover semantics
      return SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          alignment: Alignment.center,
          child: SizedBox(
            width: existing.value.size.width,
            height: existing.value.size.height,
            child: VideoPlayer(existing),
          ),
        ),
      );
    }

    if (_videoThumbErrors.contains(id)) {
      return Container(
        color: Colors.black87,
        child: const Center(
          child: Icon(Icons.broken_image, color: Colors.white54, size: 40),
        ),
      );
    }

    // Start initialization if not already
    if (!_videoThumbInitializing.contains(id)) {
      _videoThumbInitializing.add(id);
      _initVideoThumbController(message);
    }

    return Container(
      color: Colors.black87,
      child: const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
        ),
      ),
    );
  }

  Future<void> _initVideoThumbController(Message message) async {
    final id = message.id;
    try {
      VideoPlayerController controller;
      if (message.tempVideoPath != null) {
        final f = File(message.tempVideoPath!);
        if (!await f.exists()) throw Exception('Local video missing');
        controller = VideoPlayerController.file(f);
      } else if (message.fileId != null) {
        final base = getEnv("API_BASE_URL");
        if (base == null) throw Exception('API_BASE_URL not set');
        final url = base.endsWith('/') ? '${base}uploads/${message.fileId!}' : '$base/uploads/${message.fileId!}';
        controller = VideoPlayerController.network(url);
      } else {
        throw Exception('No video source');
      }
      await controller.initialize();
      controller.pause(); // keep first frame
      if (!mounted) { controller.dispose(); return; }
      setState(() {
        _videoThumbControllers[id] = controller;
      });
    } catch (e) {
      debugPrint('Video thumb error for $id: $e');
      if (mounted) {
        setState(() {
          _videoThumbErrors.add(id);
        });
      }
    } finally {
      _videoThumbInitializing.remove(id);
    }
  }

  Future<void> _openFullscreenVideo(Message message) async {
    // Dispose any existing preview controller
    _disposePreviewVideo();
    setState(() {
      _showFullscreenPreview = true;
      _previewMediaType = 'video';
      _videoPreviewError = false;
    });

    try {
      VideoPlayerController controller;
      if (message.tempVideoPath != null) {
        final f = File(message.tempVideoPath!);
        if (!await f.exists()) throw Exception('Local video missing');
        controller = VideoPlayerController.file(f);
      } else if (message.fileId != null) {
        final base = getEnv("API_BASE_URL");
        if (base == null) throw Exception('API_BASE_URL not set');
        final url = base.endsWith('/') ? '${base}uploads/${message.fileId!}' : '$base/uploads/${message.fileId!}';
        controller = VideoPlayerController.network(url);
      } else {
        throw Exception('No video source');
      }
      await controller.initialize();
      _previewVideoController = controller;
      _previewChewieController = ChewieController(
        videoPlayerController: controller,
        autoPlay: true,
        looping: false,
        allowFullScreen: false,
        allowMuting: true,
        materialProgressColors: ChewieProgressColors(
          playedColor: Colors.blueAccent,
          handleColor: Colors.blue,
          backgroundColor: Colors.white24,
          bufferedColor: Colors.blueGrey,
        ),
      );
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Fullscreen video error: $e');
      if (mounted) setState(() { _videoPreviewError = true; });
    }
  }

  void _disposePreviewVideo() {
    _previewChewieController?.dispose();
    _previewVideoController?.dispose();
    _previewChewieController = null;
    _previewVideoController = null;
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
            child: _MediaPickerContent(
              onFileSelected: _onDocumentSelected,
            ),
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
        
        // Copy Media option (for media messages)
        if (_isMediaMessage(message.type))
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
        if (_isMediaMessage(message.type))
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
    // Reply feature disabled: _replyingToMessage field removed
    setState(() { /* placeholder for future reply state */ });
    _textController.clear();
    FocusScope.of(context).requestFocus(_textFocusNode);
    _showSnackBar('Replying to message');
  }

  // Copy media to clipboard
  Future<void> _copyMedia(Message message) async {
    switch (message.type) {
      case 'PHOTO':
      case 'IMAGE':
        await _copyImageToClipboard(message);
        break;
      case 'AUDIO':
      case 'VOICE':
      case 'VOICE_NOTE':
        await _copyAudioToClipboard(message);
        break;
      case 'VIDEO':
        await _copyVideoToClipboard(message);
        break;
      case 'DOCUMENT':
      case 'FILE':
        await _copyDocumentToClipboard(message);
        break;
      default:
        _showSnackBar('Media type not supported for copying');
    }
  }

  // Copy image to clipboard (copy URL or file path)
  Future<void> _copyImageToClipboard(Message message) async {
    try {
      if (message.fileId != null) {
        final imageUrl = '${getEnv("API_BASE_URL")}/uploads/${message.fileId}';
        await Clipboard.setData(ClipboardData(text: imageUrl));
        _showSnackBar('Image URL copied to clipboard');
      } else if (message.tempImagePath != null) {
        await Clipboard.setData(ClipboardData(text: message.tempImagePath!));
        _showSnackBar('Image path copied to clipboard');
      } else {
        _showSnackBar('No image to copy');
      }
    } catch (e) {
      print('Error copying image: $e');
      _showSnackBar('Failed to copy image');
    }
  }

  // Copy audio to clipboard (copy URL)
  Future<void> _copyAudioToClipboard(Message message) async {
    try {
      if (message.fileId != null) {
        final audioUrl = '${getEnv("API_BASE_URL")}/uploads/${message.fileId}';
        await Clipboard.setData(ClipboardData(text: audioUrl));
        _showSnackBar('Audio URL copied to clipboard');
      } else {
        _showSnackBar('No audio to copy');
      }
    } catch (e) {
      print('Error copying audio: $e');
      _showSnackBar('Failed to copy audio');
    }
  }

  // Copy video to clipboard (copy URL)
  Future<void> _copyVideoToClipboard(Message message) async {
    try {
      if (message.fileId != null) {
        final videoUrl = '${getEnv("API_BASE_URL")}/uploads/${message.fileId}';
        await Clipboard.setData(ClipboardData(text: videoUrl));
        _showSnackBar('Video URL copied to clipboard');
      } else {
        _showSnackBar('No video to copy');
      }
    } catch (e) {
      print('Error copying video: $e');
      _showSnackBar('Failed to copy video');
    }
  }

  // Copy document to clipboard (copy URL)
  Future<void> _copyDocumentToClipboard(Message message) async {
    try {
      if (message.fileId != null) {
        final documentUrl = '${getEnv("API_BASE_URL")}/uploads/${message.fileId}';
        await Clipboard.setData(ClipboardData(text: documentUrl));
        _showSnackBar('Document URL copied to clipboard');
      } else {
        _showSnackBar('No document to copy');
      }
    } catch (e) {
      print('Error copying document: $e');
      _showSnackBar('Failed to copy document');
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
  Future<void> _saveMediaAs(Message message) async {
    switch (message.type) {
      case 'PHOTO':
      case 'IMAGE':
        await _saveImageToGallery(message);
        break;
      case 'AUDIO':
      case 'VOICE':
      case 'VOICE_NOTE':
        await _saveAudioToDevice(message);
        break;
      case 'VIDEO':
        await _saveVideoToGallery(message);
        break;
      case 'DOCUMENT':
      case 'FILE':
        await _saveDocumentToDevice(message);
        break;
      default:
        _showSnackBar('Media type not supported for saving');
    }
  }

  // Save image to gallery using saver_gallery
  Future<void> _saveImageToGallery(Message message) async {
    try {
      _showSnackBar('Saving image...');
      
      // Request storage permission
      final permission = await PhotoManager.requestPermissionExtend();
      if (permission.isAuth == false) {
        _showSnackBar('Storage permission denied');
        return;
      }

      if (message.fileId != null) {
        // Download image from network using HttpClient
        final imageUrl = '${getEnv("API_BASE_URL")}/uploads/${message.fileId}';
        
        final client = HttpClient();
        try {
          final request = await client.getUrl(Uri.parse(imageUrl));
          final response = await request.close();
          
          if (response.statusCode == 200) {
            final bytes = await consolidateHttpClientResponseBytes(response);
            
            // Save to gallery using photo_manager
            await PhotoManager.editor.saveImage(
              bytes,
              filename: "chat_image_${DateTime.now().millisecondsSinceEpoch}.jpg",
            );
            
            _showSnackBar('Image saved to gallery successfully');
          } else {
            _showSnackBar('Failed to download image');
          }
        } finally {
          client.close();
        }
      } else if (message.tempImagePath != null) {
        // Save local image file
        final file = File(message.tempImagePath!);
        if (await file.exists()) {
          await PhotoManager.editor.saveImageWithPath(
            message.tempImagePath!,
          );
          
          _showSnackBar('Image saved to gallery successfully');
        } else {
          _showSnackBar('Image file not found');
        }
      } else {
        _showSnackBar('No image to save');
      }
    } catch (e) {
      print('Error saving image: $e');
      _showSnackBar('Failed to save image: $e');
    }
  }

  // Save audio to device storage
  Future<void> _saveAudioToDevice(Message message) async {
    try {
      _showSnackBar('Saving audio...');
      
      // Request storage permission
      final permission = await Permission.storage.request();
      if (permission != PermissionStatus.granted) {
        _showSnackBar('Storage permission denied');
        return;
      }

      if (message.fileId != null) {
        // Download audio from network and save to temporary file first
        final audioUrl = '${getEnv("API_BASE_URL")}/uploads/${message.fileId}';
        
        
        try {
          
          var tempDir = await getTemporaryDirectory();
          String audioPath = "${tempDir.path}/${message.fileId}";
          await Dio().download(
            audioUrl,
            audioPath,
          );
    
          final result = await SaverGallery.saveFile(
            filePath: audioPath,
            skipIfExists: true,
            fileName: message.fileId!,
            // androidRelativePath: "Downloads",
          );
          print("Save result: $result");

        } finally {
          
            
        }
      } else {
        _showSnackBar('No audio file to save');
      }
    } catch (e) {
      print('Error saving audio: $e');
      _showSnackBar('Failed to save audio: $e');
    }
  }

  // Save video to device gallery
  Future<void> _saveVideoToGallery(Message message) async {
    try {
      _showSnackBar('Saving video...');
      
      // Request storage permission
      final permission = await PhotoManager.requestPermissionExtend();
      if (permission.isAuth == false) {
        _showSnackBar('Storage permission denied');
        return;
      }

      if (message.fileId != null) {
        // Download video from network using HttpClient
        final videoUrl = '${getEnv("API_BASE_URL")}/uploads/${message.fileId}';
        
        final client = HttpClient();
        try {
          final request = await client.getUrl(Uri.parse(videoUrl));
          final response = await request.close();
          
          if (response.statusCode == 200) {
            // Save to temporary file first
            final tempDir = await getTemporaryDirectory();
            final tempFilePath = '${tempDir.path}/chat_video_${DateTime.now().millisecondsSinceEpoch}.mp4';
            final tempFile = File(tempFilePath);
            
            // Write response to temporary file
            final sink = tempFile.openWrite();
            await sink.addStream(response);
            await sink.close();
            
            // Save video to gallery using photo_manager
            await PhotoManager.editor.saveVideo(
              tempFile,
            );
            
            _showSnackBar('Video saved to gallery successfully');
            
            // Clean up temporary file
            if (await tempFile.exists()) {
              await tempFile.delete();
            }
          } else {
            _showSnackBar('Failed to download video');
          }
        } finally {
          client.close();
        }
      } else {
        _showSnackBar('No video file to save');
      }
    } catch (e) {
      print('Error saving video: $e');
      _showSnackBar('Failed to save video: $e');
    }
  }

  // Save document to device storage
  Future<void> _saveDocumentToDevice(Message message) async {
    try {
      _showSnackBar('Saving document...');
      if (message.fileId == null) {
        _showSnackBar('No document to save');
        return;
      }

      // Android requires storage permission for public Downloads
      if (Platform.isAndroid) {
        final permission = await Permission.storage.request();
        if (permission != PermissionStatus.granted) {
          _showSnackBar('Storage permission denied');
          return;
        }
      }

      final documentUrl = '${getEnv("API_BASE_URL")}/uploads/${message.fileId}';
      final client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse(documentUrl));
        final response = await request.close();
        if (response.statusCode != 200) {
          _showSnackBar('Failed to download document');
          return;
        }

        Directory targetDir;
        if (Platform.isAndroid) {
          final publicDownloads = await _getAndroidPublicDownloadsDir();
          targetDir = publicDownloads ?? await getApplicationDocumentsDirectory();
        } else {
          Directory? downloadsDir;
          try { downloadsDir = await getDownloadsDirectory(); } catch (_) {}
          targetDir = downloadsDir ?? await getApplicationDocumentsDirectory();
        }

        if (!await targetDir.exists()) {
          await targetDir.create(recursive: true);
        }

        // Determine extension
        String fileExtension = _getFileExtension(documentUrl);
        if (fileExtension.isEmpty) {
          final name = message.text ?? '';
          final dot = name.lastIndexOf('.');
          if (dot != -1 && dot < name.length - 1) {
            fileExtension = name.substring(dot + 1);
          }
        }
        if (fileExtension.isEmpty) fileExtension = 'bin';

        final originalName = (message.text != null && message.text!.contains('.'))
            ? message.text!
            : 'chat_document_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
        final safeName = originalName.split('/').last.split('\\').last;
        final path = '${targetDir.path}/$safeName';

        final file = File(path);
        final sink = file.openWrite();
        await sink.addStream(response);
        await sink.close();

        _showSnackBar('File savedß');
      } finally {
        client.close();
      }
    } catch (e) {
      print('Error saving document: $e');
      _showSnackBar('Failed to save document: $e');
    }
  }

  Future<Directory?> _getAndroidPublicDownloadsDir() async {
    if (!Platform.isAndroid) return null;
    final candidates = [
      '/storage/emulated/0/Download',
      '/sdcard/Download',
      '/storage/self/primary/Download',
    ];
    for (final p in candidates) {
      final d = Directory(p);
      if (await d.exists()) return d;
    }
    // Try create first
    try {
      final fallback = Directory(candidates.first);
      if (!await fallback.exists()) await fallback.create(recursive: true);
      return fallback;
    } catch (_) {
      return null;
    }
  }

  // Helper method to extract file extension from URL
  String _getFileExtension(String url) {
    try {
      final uri = Uri.parse(url);
      final path = uri.path;
      final lastDotIndex = path.lastIndexOf('.');
      if (lastDotIndex != -1 && lastDotIndex < path.length - 1) {
        return path.substring(lastDotIndex + 1).toLowerCase();
      }
    } catch (e) {
      print('Error extracting file extension: $e');
    }
    return '';
  }

  // Helper method to check if message type is a media message
  bool _isMediaMessage(String messageType) {
    const mediaTypes = [
      'PHOTO', 'IMAGE',
      'AUDIO', 'VOICE', 'VOICE_NOTE',
      'VIDEO',
      'DOCUMENT', 'FILE'
    ];
    return mediaTypes.contains(messageType);
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
  // selection mode derived: _selectedMessages.isNotEmpty
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

  Widget _buildFullscreenMediaPreview() {
    return Positioned.fill(
      child: Container(
        color: Colors.black,
        child: Stack(
          children: [
            // Media content
            Center(
              child: () {
                // IMAGE PREVIEW (only for newly picked image before sending)
                if (_previewMediaType == 'image') {
                  if (_pickedImage != null) {
                    return InteractiveViewer(
                      child: Image.file(
                        File(_pickedImage!.path),
                        fit: BoxFit.contain,
                      ),
                    );
                  }
                  return const SizedBox();
                }

                // VIDEO PREVIEW (for either newly picked video OR existing chat video)
                if (_previewMediaType == 'video') {
                  if (_videoPreviewError) {
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.error_outline, color: Colors.red, size: 64),
                        SizedBox(height: 12),
                        Text('Unable to load video', style: TextStyle(color: Colors.white70)),
                      ],
                    );
                  }

                  // Show player once controller + chewie are ready & initialized
                  if (_previewVideoController != null &&
                      _previewChewieController != null &&
                      _previewVideoController!.value.isInitialized) {
                    final aspect = _previewVideoController!.value.aspectRatio == 0
                        ? 16 / 9
                        : _previewVideoController!.value.aspectRatio;
                    return AspectRatio(
                      aspectRatio: aspect,
                      child: Chewie(controller: _previewChewieController!),
                    );
                  }

                  // Loading placeholder while initializing
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 12),
                      Text('Loading video...', style: TextStyle(color: Colors.white70)),
                    ],
                  );
                }

                return const SizedBox();
              }(),
            ),
            // Top controls
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.7),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: _closeFullscreenPreview,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _previewMediaType == 'image' ? 'Image Preview' : 'Video Preview',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      const SizedBox(width: 40), // Balance the close button
                    ],
                  ),
                ),
              ),
            ),
            
          ],
        ),
      ),
    );
  }

  // ===== Document Support =====
  void _onDocumentSelected(String path, String name) {
    setState(() {
      _pickedDocumentPath = path;
      _pickedDocumentName = name;
      _showMediaPicker = false;
    });
  }

  void _clearPickedDocument() {
    setState(() {
      _pickedDocumentPath = null;
      _pickedDocumentName = null;
    });
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Widget _buildStatusIcon(Message message) {
    IconData icon;
    Color color;
    if (message.isRead) {
      icon = Icons.done_all; color = const Color(0xFF2F80ED);
    } else if (message.isDelivered) {
      icon = Icons.done_all; color = Colors.grey.shade500;
    } else if (message.isSent) {
      icon = Icons.done; color = Colors.grey.shade600;
    } else { icon = Icons.access_time; color = Colors.grey.shade600; }
    return Icon(icon, size: 14, color: color);
  }

  Widget _buildDocumentMessage(Message message) {
    final bool isSentByMe = _currentUserId != null && message.senderId == _currentUserId;
    final bool isLastMessage = _messages.isNotEmpty && _messages.last == message;
    final fileName = message.text ?? 'Document';
    final caption = message.caption;
    // Local cached path map key could be message.fileId or referenceId; we'll attempt to build deterministic temp path
    return Container(
      margin: EdgeInsets.fromLTRB(2, 0, 2, isLastMessage ? 20 : 4),
      child: Row(
        mainAxisAlignment: isSentByMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isSentByMe) const SizedBox(width: 10),
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.7,
                minWidth: 160,
              ),
              child: GestureDetector(
                onTapDown: (details) => _showMessageContextMenu(context, message, details.globalPosition),
                onLongPress: () {
                  final box = context.findRenderObject() as RenderBox?;
                  final pos = box?.localToGlobal(Offset.zero) ?? Offset.zero;
                  _showMessageContextMenu(context, message, pos);
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: isSentByMe
                        ? null
                        : const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFF18365B),
                              Color(0xFF163863),
                            ],
                          ),
                    color: isSentByMe ? const Color(0xFF18365B) : null,
                    borderRadius: isSentByMe
                        ? const BorderRadius.only(
                            topLeft: Radius.circular(16),
                            topRight: Radius.circular(4),
                            bottomLeft: Radius.circular(16),
                            bottomRight: Radius.circular(16),
                          )
                        : const BorderRadius.only(
                            topLeft: Radius.circular(4),
                            topRight: Radius.circular(16),
                            bottomLeft: Radius.circular(16),
                            bottomRight: Radius.circular(16),
                          ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Icon + action (download/open)
                          _buildDocumentActionIcon(message),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                GestureDetector(
                                  onTap: () => _openOrDownloadDocument(message),
                                  child: Text(
                                    fileName,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFFE8E7EA),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (caption != null && caption.isNotEmpty && caption != fileName)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4.0),
                                    child: GestureDetector(
                                      onTapDown: (d) => _showMessageContextMenu(context, message, d.globalPosition),
                                      child: TextUtils.buildTextWithLinks(
                                        caption,
                                        style: TextStyle(
                                          color: Colors.grey.shade300,
                                          fontSize: 13,
                                        ),
                                        linkStyle: TextStyle(
                                          color: Colors.blue,
                                          fontSize: 13,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _formatTime(message.createdAt),
                            style: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 11,
                            ),
                          ),
                          if (isSentByMe) ...[
                            const SizedBox(width: 4),
                            _buildStatusIcon(message),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (isSentByMe) const SizedBox(width: 10),
        ],
      ),
    );
  }

  // Builds the leading square icon that changes depending on download/open state
  Widget _buildDocumentActionIcon(Message message) {
    return FutureBuilder<bool>(
      future: _isDocumentCached(message),
      builder: (context, snapshot) {
        final cached = snapshot.data == true;
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        return GestureDetector(
          onTap: isLoading ? null : () => _openOrDownloadDocument(message),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.black.withOpacity(0.2), width: 0.5),
            ),
            child: Center(
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                    )
                  : Icon(
                      cached ? Icons.open_in_new : Icons.download_rounded,
                      size: 22,
                      color: const Color(0xFF3498DB),
                    ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openOrDownloadDocument(Message message) async {
    try {
      final cached = await _isDocumentCached(message);
      if (cached) {
        final path = await _localDocumentPath(message);
        if (path != null) {
          await OpenFilex.open(path);
        } else {
          _showSnackBar('File not found');
        }
        return;
      }
      // Not cached -> download
      _showSnackBar('Downloading document...');
      final saved = await _downloadAndCacheDocument(message);
      if (saved != null) {
        _showSnackBar('Download complete');
        await OpenFilex.open(saved);
      } else {
        _showSnackBar('Download failed');
      }
    } catch (e) {
      debugPrint('Open/download doc error: $e');
      _showSnackBar('Unable to open document');
    }
  }

  Future<bool> _isDocumentCached(Message message) async {
    final path = await _localDocumentPath(message);
    if (path == null) return false;
    return File(path).exists();
  }

  Future<String?> _localDocumentPath(Message message) async {
    final dir = await getTemporaryDirectory();
    final dynamic rawId = message.fileId ?? message.referenceId ?? message.id;
    final String id = rawId.toString();
    // Keep extension if present in original filename (message.text)
    String baseName = id;
    final name = message.text ?? '';
    final dot = name.lastIndexOf('.');
    if (dot != -1 && dot < name.length - 1) {
      final ext = name.substring(dot + 1);
      baseName = '$id.$ext';
    }
    return '${dir.path}/doc_$baseName';
  }

  Future<String?> _downloadAndCacheDocument(Message message) async {
    if (message.fileId == null) return null; // Can't download without remote id
    try {
      final url = '${getEnv("API_BASE_URL")}/uploads/${message.fileId}';
      final savePath = await _localDocumentPath(message);
      if (savePath == null) return null;
      await Dio().download(url, savePath);
      return savePath;
    } catch (e) {
      debugPrint('Download doc failed: $e');
      return null;
    }
  }
}

class _MediaPickerContent extends StatefulWidget {
  final void Function(String path, String name)? onFileSelected;
  const _MediaPickerContent({this.onFileSelected});
  @override
  _MediaPickerContentState createState() => _MediaPickerContentState();
}

class _MediaPickerContentState extends State<_MediaPickerContent> {
  int _selectedTabIndex = 0;

  late List<MediaTab> _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = [
      MediaTab(
        title: 'Gallery',
        icon: Icons.photo_library,
        content: _GalleryContent(),
      ),
      MediaTab(
        title: 'File',
        icon: Icons.folder,
        content: _FileContent(
          onPick: (p, n) => widget.onFileSelected?.call(p, n),
        ),
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
  }

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
            await FilePicker.platform.pickFiles(type: FileType.any);

        if (result != null) {
          String fileName = result.files.first.name;
          print(fileName);
          // Use fileName as needed
        }
      } else {
        final permission = await Permission.photos.request();
        await Permission.audio.request();
        await Permission.videos.request();
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
        type: RequestType.fromTypes(  [RequestType.image, RequestType.video, RequestType.common]),
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
                              // Check if the asset is a video or image
                              if (asset.type == AssetType.video) {
                                parentState._pickedVideo = XFile(file.path);
                                parentState._pickedImage = null;
                              } else {
                                parentState._pickedImage = XFile(file.path);
                                parentState._pickedVideo = null;
                              }
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
                              // Video indicator overlay
                              if (asset.type == AssetType.video)
                                Positioned(
                                  bottom: 4,
                                  right: 4,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.7),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.play_arrow,
                                          color: Colors.white,
                                          size: 12,
                                        ),
                                        const SizedBox(width: 2),
                                        FutureBuilder<Duration?>(
                                          future: Future.value(asset.videoDuration),
                                          builder: (context, snapshot) {
                                            if (snapshot.hasData && snapshot.data != null) {
                                              final duration = snapshot.data!;
                                              final minutes = duration.inMinutes;
                                              final seconds = duration.inSeconds % 60;
                                              return Text(
                                                '${minutes.toString().padLeft(1, '0')}:${seconds.toString().padLeft(2, '0')}',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              );
                                            }
                                            return const Text(
                                              '0:00',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
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
  final void Function(String path, String name)? onPick;
  const _FileContent({this.onPick});
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
        if (file.path != null && widget.onPick != null) {
          widget.onPick!(file.path!, file.name);
        }
      }
    } catch (e) {
      print('Error picking file: $e');
    }
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
                              if (widget.onPick != null) {
                                widget.onPick!(entity.path, name);
                              }
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
