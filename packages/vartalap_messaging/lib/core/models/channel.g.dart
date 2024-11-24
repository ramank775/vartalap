// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'channel.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ChannelModel _$ChannelFromJson(Map<String, dynamic> json) => ChannelModel()
  ..channelId = json['channelId'] as String?
  ..name = json['name'] as String
  ..type = json['type'] as String
  ..members =
      (json['members'] as List<dynamic>).map((e) => e as String).toList()
  ..profilePic = json['profilePic'] as String;

Map<String, dynamic> _$ChannelToJson(ChannelModel instance) {
  final val = <String, dynamic>{};

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('channelId', instance.channelId);
  val['name'] = instance.name;
  val['type'] = instance.type;
  val['members'] = instance.members;
  val['profilePic'] = instance.profilePic;
  return val;
}
