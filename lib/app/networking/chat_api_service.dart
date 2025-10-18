import 'package:flutter/material.dart';
import 'package:flutter_app/app/models/chat_links_response.dart';
import 'package:flutter_app/app/models/chat_messages_response.dart';
import 'package:flutter_app/app/models/media_response.dart';
import 'package:flutter_app/app/models/user.dart';
import 'package:nylo_framework/nylo_framework.dart';
import '../models/group_creation_response.dart';
import '/app/models/chat.dart';
import '/app/networking/api_service.dart';
import "/app/models/chat_list_response.dart";
import "/app/models/search_char_response.dart";
import "/app/models/chat_creation_response.dart";
import "/app/models/call_models.dart";

class ChatApiService extends ApiService {
  ChatApiService({BuildContext? buildContext})
      : super(buildContext: buildContext);

  @override
  String get baseUrl => getEnv('API_BASE_URL');

  /// Get list of all chats for the current user
  Future<ChatListResponse?> getChatList() async {
    return await network<ChatListResponse>(
      request: (request) => request.get("/chat"),
    );
  }

  Future<List<SearchUser>?> searchChat({
    required String query,
    int? limit,
    int? offset,
  }) async {
    return await network<List<SearchUser>>(
      request: (request) => request.get(
        "/chat/search",
        queryParameters: {
          "query": query,
          "type": "user",
          if (limit != null) 'limit': limit,
          if (offset != null) 'offset': offset,
        },
      ),
    );
  }

  /// Create or get a private chat with a partner
  Future<Chat?> createPrivateChat({required int partnerId}) async {
    return await network<Chat?>(
      request: (request) => request.post(
        "/chat",
        data: {
          "type": "PRIVATE",
          "partnerId": partnerId.toString(),
        },
      ),
    );
  }

  Future<CallResponse?> initiateVoiceCall(int chatId) async {
    return await network<CallResponse>(
      request: (request) => request.post(
        "/call/voice-call",
        data: {
          "chatId": chatId,
        },
      ),
    );
  }

  Future<UploadAvatarResponse?> uploadAvatarImage(String filePath) async {
    return await network<UploadAvatarResponse>(
      request: (request) => request.put(
        "/user/avatar",
        data: FormData.fromMap({
          'avatar': MultipartFile.fromFileSync(filePath,
              filename: filePath.split('/').last),
        }),
      ),
    );
  }

  Future<CallResponse?> initiateVideoCall(int chatId) async {
    return await network<CallResponse>(
      request: (request) => request.post(
        "/call/video-call",
        data: {
          "chatId": chatId,
        },
      ),
    );
  }


  Future<CallResponse?> joinVoiceCall(int chatId) async {
    return await network<CallResponse>(
      request: (request) => request.post(
        "/call/voice-call/join",
        data: {
          "chatId": chatId,
        },
      ),
    );
  }

  Future<CallResponse?> joinVideoCall(int chatId) async {
    return await network<CallResponse>(
      request: (request) => request.post(
        "/call/video-call/join",
        data: {
          "chatId": chatId,
        },
      ),
    );
  }

  Future<List<MediaResponse>?> getChatMedia(int chatId) async {
    return await network<List<MediaResponse>>(
      request: (request) => request.get(
        "/chat/media",
        queryParameters: {
          "chatId": chatId,
        },
      ),
    );  
  }
  
  Future<List<MediaResponse>?> getChatFiles(int chatId) async {
    return await network<List<MediaResponse>>(
      request: (request) => request.get(
        "/chat/files",
        queryParameters: {
          "chatId": chatId,
        },
      ),
    );  
  }

  Future<GroupCreationResponse?> createGroupChat(
    String groupName, 
    String groupDescription, 
    List<int> memberIds,
    String? filePath,
    ) async {
    return await network<GroupCreationResponse>(
      request: (request) => request.post(
        "/chat/group",
        data: FormData.fromMap({
          "name": groupName,
          "description": groupDescription,
          "members": memberIds,
          if (filePath != null) "avatar": MultipartFile.fromFileSync(
            filePath,
            filename: filePath.split('/').last,
          ),
        }),
      ),
    );
  }

  Future<List<LinkResponse>?> getChatLinks(int chatId) async {
    
    return await network<List<LinkResponse>>(
      request: (request) => request.get(
        "/chat/links",
        queryParameters: {
          "chatId": chatId,
        },
      ),
    );
  }
  

  /// Get chat with previous messages (using the /chat endpoint)
  Future<ChatCreationResponse?> getChatWithMessages({
    required String type,
    String? partnerId,
  }) async {
    try {
      print('🔍 Loading chat with messages...');
      print('🔍 Type: $type, Partner ID: $partnerId');

      final response = await network<ChatCreationResponse>(
        request: (request) => request.post(
          "/chat",
          data: {
            "type": type,
            if (partnerId != null) "partnerId": partnerId,
          },
        ),
      );

      print('✅ Chat with messages loaded: ${response?.toJson()}');
      return response;
    } catch (e) {
      print('❌ Error loading chat with messages: $e');
      return null;
    }
  }

  /// Get chat messages (for loading previous messages)
  Future<ChatMessagesResponse?> getChatMessages(
      {required int chatId, int? limit = 50, int? messageId}) async {
    return await network<ChatMessagesResponse>(
      request: (request) => request.get(
        "/chat/$chatId/messages",
        queryParameters: {
          if (limit != null) 'pageSize': limit,
          if (messageId != null) 'messageId': messageId,
        },
      ),
    );
  }



  /// Send a message to a chat (fallback when WebSocket is not available)
  Future<void> sendMessage({
    required int chatId,
    required String type,
    String? text,
    String? caption,
    String? filePath,
    int? referenceId,
    

  }) async {
      await network(
      request: (request) {
        
          // Send with file attachment using FormData
          return request.post(
            "/message",
            data: filePath != null
              ? FormData.fromMap({
                "chatId": chatId,
                if (text != null) "text": text,
                if (caption != null) "caption": caption,
                if (referenceId != null) "referenceId": referenceId,
                "type": type,
                "file": MultipartFile.fromFileSync(
                  filePath,
                  filename: filePath.split('/').last,
                ),
                })
              : {
                "chatId": chatId,
                if (text != null) "text": text,
                if (caption != null) "caption": caption,
                if (referenceId != null) "referenceId": referenceId,
                "type": type,
                },
          );
      },
    );
  }

  /// Mark messages as read
  Future<bool?> markMessagesAsRead({
    required int chatId,
    List<String>? messageIds,
  }) async {
    return await network<bool>(
      request: (request) => request.post(
        "/chat/$chatId/read",
        data: {
          if (messageIds != null) "messageIds": messageIds,
        },
      ),
    );
  }

  /// Get chat details
  Future<Chat?> getChatDetails({required int chatId}) async {
    return await network<Chat>(
      request: (request) => request.get("/chat/$chatId"),
    );
  }

  /// Delete a chat
  Future<bool?> deleteChat({required int chatId}) async {
    return await network<bool>(
      request: (request) => request.delete("/chat/$chatId"),
    );
  }

  /// Search chats
  Future<List<Chat>?> searchChats({required String query}) async {
    return await network<List<Chat>>(
      request: (request) => request.get(
        "/chat/search",
        queryParameters: {"q": query},
      ),
    );
  }

  /// Get recent chats with pagination
  Future<Map<String, dynamic>?> getRecentChats({
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final response = await network(
        request: (request) => request.get(
          "/chat",
          queryParameters: {
            "page": page,
            "pageSize": pageSize,
          },
        ),
      );

      if (response != null && response is Map<String, dynamic>) {
        return response;
      }

      return null;
    } catch (e) {
      print('Error fetching recent chats: $e');
      return null;
    }
  }

  /// Search users
  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    try {
      final response = await network(
        request: (request) => request.get(
          "/chat/search",
          queryParameters: {
            "type": "user",
            "query": query,
          },
        ),
      );

      if (response != null && response is List) {
        return List<Map<String, dynamic>>.from(response);
      }

      return [];
    } catch (e) {
      print('Error searching users: $e');
      return [];
    }
  }

  /// Create or get existing chat
  Future<Map<String, dynamic>?> createOrGetChat({
    required String type,
    String? partnerId,
  }) async {
    try {
      print('=== CHAT CREATION API CALL ===');
      print('URL: ${baseUrl}/chat');
      print('Method: POST');
      print('Data: {"type": "$type", "partnerId": "$partnerId"}');

      final response = await network(
        request: (request) => request.post(
          "/chat",
          data: {
            "type": type,
            if (partnerId != null) "partnerId": partnerId,
          },
        ),
      );

      print('API response type: ${response.runtimeType}');
      print('API response: $response');

      if (response != null && response is Map<String, dynamic>) {
        print('✅ Chat creation successful');
        return response;
      }

      print('❌ Response is null or not a Map');
      return null;
    } catch (e) {
      print('❌ Error creating/getting chat: $e');
      print('Error stack trace: ${e.toString()}');
      return null;
    }
  }
}
