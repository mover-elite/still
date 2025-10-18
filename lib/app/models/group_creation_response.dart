// /Users/mover/still/lib/app/models/group_creation_response.dart

import 'package:flutter_app/app/models/user_info.dart';

class GroupCreationResponse {
  final int id;
  final String? avatar;
  final int creatorId;
  final String name;
  final String? description;
  final String type;
  final bool isPublic;
  final int? partnerId;
  final String? inviteCode;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<UserInfo> members;
  final UserInfo creator;
  final bool? restrictContent; 
  
  GroupCreationResponse({
    required this.id,
    this.avatar,
    required this.creatorId,
    required this.name,
    this.description,
    required this.type,
    required this.isPublic,
    this.partnerId,
    this.inviteCode,
    this.restrictContent,
    required this.createdAt,
    required this.updatedAt,
    required this.members,
    required this.creator,
  });

  factory GroupCreationResponse.fromJson(Map<String, dynamic> json) {
    return GroupCreationResponse(
      id: json['id'] as int,
      avatar: json['avatar'] as String?,
      creatorId: json['creatorId'] as int,
      name: json['name'] as String,
      description: json['description'] as String?,
      type: json['type'] as String,
      isPublic: json['isPublic'] as bool,
      partnerId: json['partnerId'] as int?,
      restrictContent: json['restrictContent'] as bool?,
      inviteCode: json['inviteCode'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      members: (json['members'] as List<dynamic>? ?? [])
          .map((e) => UserInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
      creator: UserInfo.fromJson(json['creator'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'avatar': avatar,
      'creatorId': creatorId,
      'name': name,
      'description': description,
      'type': type,
      'isPublic': isPublic,
      'partnerId': partnerId,
      'inviteCode': inviteCode,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'members': members.map((m) => m.toJson()).toList(),
      'creator': creator.toJson(),
    };
  }
}

