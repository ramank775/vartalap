// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'event.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Head _$HeadFromJson(Map<String, dynamic> json) => Head(
      type: $enumDecode(_$ChannelTypeEnumMap, json['type']),
      to: json['to'] as String,
      from: json['from'] as String,
      category: json['category'] as String? ?? 'message',
      ephemeral: json['ephemeral'] as bool? ?? false,
    );

Map<String, dynamic> _$HeadToJson(Head instance) => <String, dynamic>{
      'type': _$ChannelTypeEnumMap[instance.type],
      'to': instance.to,
      'from': instance.from,
      'category': instance.category,
      'ephemeral': instance.ephemeral,
    };

const _$ChannelTypeEnumMap = {
  ChannelType.none: 'none',
  ChannelType.individual: 'individual',
  ChannelType.group: 'group',
  ChannelType.other: 'other',
};

Meta _$MetaFromJson(Map<String, dynamic> json) => Meta();

Map<String, dynamic> _$MetaToJson(Meta instance) => <String, dynamic>{};

RemoteMessage _$RemoteMessageFromJson(Map<String, dynamic> json) =>
    RemoteMessage()
      ..version = (json['_v'] as num).toDouble()
      ..id = json['id'] as String
      ..head = Head.fromJson(json['head'] as Map<String, dynamic>)
      ..meta = const _MetaJsonConverter()
          .fromJson(json['meta'] as Map<String, dynamic>)
      ..body = json['body'];

Map<String, dynamic> _$RemoteMessageToJson(RemoteMessage instance) =>
    <String, dynamic>{
      '_v': instance.version,
      'id': instance.id,
      'head': instance.head,
      'meta': const _MetaJsonConverter().toJson(instance.meta),
      'body': instance.body,
    };
