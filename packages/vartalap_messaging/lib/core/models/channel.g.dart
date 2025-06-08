// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'channel.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ChannelPayload _$ChannelPayloadFromJson(Map<String, dynamic> json) =>
    ChannelPayload()
      ..channelId = json['channelId'] as String?
      ..name = json['name'] as String
      ..type = json['type'] as String
      ..members =
          (json['members'] as List<dynamic>).map((e) => e as String).toList()
      ..profilePic = json['profilePic'] as String;

Map<String, dynamic> _$ChannelPayloadToJson(ChannelPayload instance) =>
    <String, dynamic>{
      if (instance.channelId case final value?) 'channelId': value,
      'name': instance.name,
      'type': instance.type,
      'members': instance.members,
      'profilePic': instance.profilePic,
    };
