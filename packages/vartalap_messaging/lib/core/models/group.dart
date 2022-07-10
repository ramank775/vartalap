import 'package:json_annotation/json_annotation.dart';

part 'group.g.dart';

@JsonSerializable()
class Group {
  @JsonKey(includeIfNull: false)
  late String? groupId;

  @JsonKey(includeIfNull: false)
  late String name;

  @JsonKey(includeIfNull: false)
  late List<String> members;

  @JsonKey(includeIfNull: false)
  late String profilePic;

  static Group fromJson(Map<String, dynamic> json) => _$GroupFromJson(json);

  Map<String, dynamic> toJson() => _$GroupToJson(this);
}
