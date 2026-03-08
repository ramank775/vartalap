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
  final String? cid;
  final int? taskId;
  final Map<String, dynamic>? extraData;
  final Map<String, dynamic> config;
  final bool muted;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  ChannelModel({
    required this.id,
    required this.type,
    this.cid,
    this.taskId,
    this.extraData,
    required this.config,
    required this.muted,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  factory ChannelModel.initial({
    required ChannelType type,
    Map<String, dynamic>? extraData,
  }) {
    return ChannelModel(
      id: 0,
      type: type,
      extraData: extraData,
      config: const {},
      muted: false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  String get displayName {
    if (extraData != null && extraData!['name'] != null) {
      return extraData!['name']! as String;
    }
    return "Unknown";
  }

  String? get displayImage {
    if (extraData != null) {
      if (extraData!['photo'] != null && extraData!['photo'].toString().isNotEmpty) {
        return extraData!['photo'] as String;
      }
      if (extraData!['image'] != null && extraData!['image'].toString().isNotEmpty) {
        return extraData!['image'] as String;
      }
    }
    return null;
  }

  ChannelConfig get channelConfig => ChannelConfig.fromJson(config);

  bool get isPinned => channelConfig.isPinned;
  bool get isArchived => channelConfig.isArchived;
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
