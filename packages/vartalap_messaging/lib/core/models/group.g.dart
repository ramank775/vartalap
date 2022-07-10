// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'group.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Group _$GroupFromJson(Map<String, dynamic> json) => Group()
  ..groupId = json['groupId'] as String?
  ..name = json['name'] as String
  ..members =
      (json['members'] as List<dynamic>).map((e) => e as String).toList()
  ..profilePic = json['profilePic'] as String;

Map<String, dynamic> _$GroupToJson(Group instance) {
  final val = <String, dynamic>{};

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('groupId', instance.groupId);
  val['name'] = instance.name;
  val['members'] = instance.members;
  val['profilePic'] = instance.profilePic;
  return val;
}
