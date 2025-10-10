class LinkResponse {
  final int id;
  final int chatId;
  final String type;
  final String? text;
  final String? caption;
  final String? fileId;
  final DateTime createdAt;

  LinkResponse({
    required this.id,
    required this.chatId,
    required this.type,
    this.text,
    this.caption,
    this.fileId,
    required this.createdAt,
  });

  factory LinkResponse.fromJson(Map<String, dynamic> json) {
    return LinkResponse(
      id: json['id'] as int,
      chatId: json['chatId'] as int,
      type: json['type'] as String,
      text: json['text'] as String?,
      caption: json['caption'] as String?,
      fileId: json['fileId'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'chatId': chatId,
      'type': type,
      'text': text,
      'caption': caption,
      'fileId': fileId,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
