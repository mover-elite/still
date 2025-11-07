class UserCallsModel {
  final int id;
  final int senderId;
  final int chatId;
  final String? type;
  final String? text;
  final String? callId;
  final int? duration;
  final String? callStatus;
  final String? caption;
  final String? fileId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final CallChat chat;
  final Sender sender;

  UserCallsModel({
    required this.id,
    required this.senderId,
    required this.chatId,
    required this.type,
    this.text,
    required this.callId,
    this.duration,
    required this.callStatus,
    this.caption,
    this.fileId,
    required this.createdAt,
    required this.updatedAt,
    required this.chat,
    required this.sender,
  });

  factory UserCallsModel.fromJson(Map<String, dynamic> json) {
    return UserCallsModel(
      id: json['id'],
      senderId: json['senderId'],
      chatId: json['chatId'],
      type: json['type'],
      text: json['text'],
      callId: json['callId'],
      duration: json['duration'],
      callStatus: json['callStatus'],
      caption: json['caption'],
      fileId: json['fileId'],
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
      chat: CallChat.fromJson(json['Chat']),
      sender: Sender.fromJson(json['sender']),
    );
  }
}

class CallChat {
  final int id;
  final String? name;
  final String? type;
  final int creatorId;
  final String? partnerId;
  final Sender? creator;
  final Sender? partner;

  CallChat({
    required this.id,
    this.name,
    required this.type,
    required this.creatorId,
    required this.partnerId,
    this.creator,
    this.partner,
  });

  factory CallChat.fromJson(Map<String, dynamic> json) {
    return CallChat(
      id: json['id'],
      name: json['name'],
      type: json['type'],
      creatorId: json['creatorId'],
      partnerId: json['partnerId'],
      creator: json['creator'] != null ? Sender.fromJson(json['creator']) : null,
      partner: json['partner'] != null ? Sender.fromJson(json['partner']) : null,
    );
  }
}

class Sender {
  final int id;
  final String username;
  final String? firstName;
  final String? lastName;
  final String? avatar;

  Sender({
    required this.id,
    required this.username,
    this.firstName,
    this.lastName,
    required this.avatar,
  });

  factory Sender.fromJson(Map<String, dynamic> json) {
    return Sender(
      id: json['id'],
      username: json['username'],
      firstName: json['firstName'],
      lastName: json['lastName'],
      avatar: json['avatar'],
    );
  }
}