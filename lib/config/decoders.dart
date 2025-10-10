import 'package:flutter_app/app/models/chat_links_response.dart';
import 'package:flutter_app/app/models/media_response.dart';

import '/app/controllers/home_controller.dart';
import '/app/models/chat.dart';
import '/app/models/user.dart';
import '/app/models/chat_list_response.dart';
import '/app/models/chat_messages_response.dart';
import '/app/models/search_char_response.dart';
import '/app/models/chat_creation_response.dart';
import '/app/models/call_models.dart';
import '/app/networking/api_service.dart';
import '/app/networking/auth_api_service.dart';
import '/app/networking/chat_api_service.dart';

/* Model Decoders
|--------------------------------------------------------------------------
| Model decoders are used in 'app/networking/' for morphing json payloads
| into Models.
|
| Learn more https://nylo.dev/docs/6.x/decoders#model-decoders
|-------------------------------------------------------------------------- */

final Map<Type, dynamic> modelDecoders = {
  User: (data) => User.fromJson(data),
  Chat: (data) => Chat.fromJson(data),
  // Chat?: (data) => data != null ? Chat.fromJson(data) : null,

  List<Chat>: (data) =>
      List.from(data).map((json) => Chat.fromJson(json)).toList(),
  ChatListResponse: (data) => ChatListResponse.fromJson(data),
  List<Map<String, dynamic>>: (data) => List<Map<String, dynamic>>.from(data),
  SearchUser: (data) => SearchUser.fromJson(data),
  List<SearchUser>: (data) =>
      List.from(data).map((json) => SearchUser.fromJson(json)).toList(),
  ChatCreationResponse: (data) => ChatCreationResponse.fromJson(data),
  ChatMessagesResponse: (data) => ChatMessagesResponse.fromJson(data),
  CallResponse: (data) => CallResponse.fromJson(data),
  
  UploadAvatarResponse: (data) => UploadAvatarResponse.fromJson(data),
  List<MediaResponse>: (data) =>
    List.from(data).map((json) => MediaResponse.fromJson(json)).toList(),
  
  List<LinkResponse>: (data) =>
    List.from(data).map((json) => LinkResponse.fromJson(json)).toList(),
  
  // To handle nullable lists, decode as List<SearchUser> and handle nulls outside the decoder.
  // SearchCharResponse: (data) => SearchCharResponse.fromJson(data),
};

/* API Decoders
| -------------------------------------------------------------------------
| API decoders are used when you need to access an API service using the
| 'api' helper. E.g. api<MyApiService>((request) => request.fetchData());
|
| Learn more https://nylo.dev/docs/6.x/decoders#api-decoders
|-------------------------------------------------------------------------- */

final Map<Type, dynamic> apiDecoders = {
  ApiService: () => ApiService(),
  AuthApiService: () => AuthApiService(),
  ChatApiService: () => ChatApiService(),
  HomeController: () => HomeController(),
};

/* Controller Decoders
| -------------------------------------------------------------------------
| Controller are used in pages.
|
| Learn more https://nylo.dev/docs/6.x/controllers
|-------------------------------------------------------------------------- */
final Map<Type, dynamic> controllers = {
  HomeController: () => HomeController(),

  // ...
};
