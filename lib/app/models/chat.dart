import 'package:flutter_app/app/models/participants.dart';

import 'message.dart';
import 'chat_partner.dart';

class Chat {
  final int id;
  final int creatorId;
  final String name;
  final String type;
  final bool isPublic;
  final int? partnerId;
  final String? inviteCode;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? description;
  Message? lastMessage;
  DateTime? lastMessageTime;

  int unreadCount;
  String? avatar;
  bool isOnline;
  bool isGroup;

  List<Participant> participants;
  List<Message> messages;
  Partner? partner;
  Set<int> typingUsers = {};

  Chat({
    required this.id,
    required this.name,
    required this.type,
    required this.creatorId,
    required this.isPublic,
    required this.createdAt,
    required this.updatedAt,
    this.partnerId,
    this.inviteCode,
    this.lastMessage,
    this.lastMessageTime,
    this.unreadCount = 0,
    this.avatar,
    this.description,
    this.isOnline = false,
    this.isGroup = false,
    this.participants = const [],
    this.messages = const [],
    this.partner,
  });

  factory Chat.fromJson(Map<String, dynamic> json) {
    return Chat(
      id: json['id'],
      creatorId: json['creatorId'],
      type: json['type'] ?? 'PRIVATE',
      isPublic: json['isPublic'] ?? false,
      description: json['description'],
      inviteCode: json['inviteCode'],
      partnerId: json['partnerId'] != null
          ? int.tryParse(json['partnerId'].toString())
          : null,
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
      name: (json['type'] == 'CHANNEL')
          ? (json['name'] ?? 'Unknown')
          : (json['partner'] != null && json['partner']['username'] != null
              ? json['partner']['username']
              : 'Unknown'),
      lastMessage:
          (json['messages'] != null && (json['messages'] as List).isNotEmpty)
              ? Message.fromJson((json['messages'] as List).last)
              : null,
      lastMessageTime: json['lastMessageTime'] != null
          ? DateTime.parse(json['lastMessageTime'])
          : null,
      unreadCount: json['unreadCount'] ?? 0,
      avatar: json['avatar'] != null ? json['avatar'] as String : null,
      isOnline: json['isOnline'] ?? false,
      isGroup: (json['type'] == 'CHANNEL'),
      participants: List<Participant>.from(
          (json['members'] as List).map((p) => Participant.fromJson(p))),
      messages: (json['messages'] != null)
          ? List<Message>.from(
              (json['messages'] as List).map((m) => Message.fromJson(m)))
          : [],
      partner:
          json['partner'] != null ? Partner.fromJson(json['partner']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'lastMessage': lastMessage?.toJson(),
      'lastMessageTime': lastMessageTime?.toIso8601String(),
      'unreadCount': unreadCount,
      'avatar': avatar,
      'isOnline': isOnline,
      'isGroup': isGroup,
      'participants': participants,
      'messages': messages.map((m) => m.toJson()).toList(),
      'partner': partner?.toJson(),
    };
  }

  Chat copyWith({
    int? id,
    String? name,
    Message? lastMessage,
    bool? isPublic,
    String? inviteCode,
    DateTime? lastMessageTime,
    int? unreadCount,
    String? avatar,
    bool? isOnline,
    bool? isGroup,
    List<Participant>? participants,
    List<Message>? messages,
    Partner? partner,
  }) {
    return Chat(
      id: id ?? this.id,
      name: name ?? this.name,
      type: this.type, // type is not nullable, so we keep it as is
      creatorId: this.creatorId,
      isPublic: this.isPublic,
      inviteCode: this.inviteCode,
      createdAt: this.createdAt,
      updatedAt: this.updatedAt,
      partnerId: this.partnerId,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
      avatar: avatar ?? this.avatar,
      isOnline: isOnline ?? this.isOnline,
      isGroup: isGroup ?? this.isGroup,
      participants: participants ?? this.participants,
      messages: messages ?? this.messages,
      partner: partner ?? this.partner,
    );
  }
}
