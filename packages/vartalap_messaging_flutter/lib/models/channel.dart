import 'package:json_annotation/json_annotation.dart';

import 'package:vartalap_messaging/vartalap_messaging.dart';

part 'channel.g.dart';

@JsonSerializable()
class ChannelConfig {
  final bool isPublic;
  final bool isMuted;
  final bool isArchived;
  final bool isPinned;

  ChannelConfig({
    this.isPublic = false,
    this.isMuted = false,
    this.isArchived = false,
    this.isPinned = false,
  });

  factory ChannelConfig.fromJson(Map<String, dynamic> json) =>
      _$ChannelConfigFromJson(json);

  Map<String, dynamic> toJson() => _$ChannelConfigToJson(this);
}

class ChannelModel {
  final int id;
  final ChannelType type;
  bool isMuted = false;
  DateTime createdAt;
  DateTime updatedAt;
  ChannelConfig? config;
  Map<String, Object?> extraData;

  ChannelModel({
    required this.type,
    required this.id,
    required this.config,
    this.isMuted = false,
    this.extraData = const {},
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  String get displayName {
    if (extraData['name'] != null) {
      return extraData['name']! as String;
    }
    return "Unknown";
  }
}

class ChannelFilter {
  final ChannelType? type;
  final String? name;
  final List<int>? memberIds;

  ChannelFilter({
    this.type,
    this.name,
    this.memberIds,
  });
}
