class MediaResponse {
  final int id;
  final int chatId;
  final String fileId;
  final String type;

  MediaResponse({
    required this.id,
    required this.chatId,
    required this.fileId,
    required this.type,
  });

  factory MediaResponse.fromJson(Map<String, dynamic> json) {
    return MediaResponse(
      id: json['id'] as int,
      chatId: json['chatId'] as int,
      fileId: json['fileId'] as String,
      type: json['type'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'chatId': chatId,
      'fileId': fileId,
      'type': type,
    };
  }
}
