import 'package:json_annotation/json_annotation.dart';

part 'channel.g.dart';

@JsonSerializable()
class ChannelModel {
  @JsonKey(includeIfNull: false)
  late String? channelId;

  @JsonKey(includeIfNull: false)
  late String name;

  @JsonKey(includeIfNull: false)
  late String type;

  @JsonKey(includeIfNull: false)
  late List<String> members;

  @JsonKey(includeIfNull: false)
  late String profilePic;

  static ChannelModel fromJson(Map<String, dynamic> json) =>
      _$ChannelModelFromJson(json);

  Map<String, dynamic> toJson() => _$ChannelModelToJson(this);
}
