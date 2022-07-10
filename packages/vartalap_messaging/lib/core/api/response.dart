import 'package:json_annotation/json_annotation.dart';
import 'package:vartalap_messaging/core/models/group.dart';

part 'response.g.dart';

@JsonSerializable()
class ErrorResponse {
  /// The http error code
  int? code;

  /// The message associated to the error code
  String? message;

  /// The backend error code
  @JsonKey(name: 'StatusCode')
  int? statusCode;

  /// A detailed message about the error
  String? moreInfo;

  /// Create a new instance from a json
  static ErrorResponse fromJson(Map<String, dynamic> json) =>
      _$ErrorResponseFromJson(json);

  /// Serialize to json
  Map<String, dynamic> toJson() => _$ErrorResponseToJson(this);

  @override
  String toString() => 'ErrorResponse(code: $code, '
      'message: $message, '
      'statusCode: $statusCode, '
      'moreInfo: $moreInfo)';
}

@JsonSerializable(createToJson: false)
class EmptyResponse {
  static EmptyResponse fromJson(Map<String, dynamic> json) =>
      _$EmptyResponseFromJson(json);
}

@JsonSerializable(createToJson: false)
class LoginResponse {
  @JsonKey()
  late bool status;

  @JsonKey()
  late String username;

  @JsonKey(name: 'accesskey')
  late String accessKey;

  @JsonKey()
  late bool isNew;

  static LoginResponse fromJson(Map<String, dynamic> json) =>
      _$LoginResponseFromJson(json);
}

@JsonSerializable(createToJson: false)
class ProfileResponse {
  @JsonKey()
  late String name;

  @JsonKey()
  late String username;

  @JsonKey()
  late String? userId;

  static ProfileResponse fromJson(Map<String, dynamic> json) =>
      _$ProfileResponseFromJson(json);
}

@JsonSerializable(createToJson: false)
class GroupResponse {
  @JsonKey(includeIfNull: false)
  late String? groupId;

  @JsonKey()
  late String name;

  @JsonKey()
  late List<String> members;

  @JsonKey()
  late String profilePic;
  static GroupResponse fromJson(Map<String, dynamic> json) =>
      _$GroupResponseFromJson(json);
}

class GroupsResponse {
  @JsonKey(ignore: true)
  late List<Group> items;

  static GroupsResponse fromJson(List jsons) => GroupsResponse()
    ..items = jsons.map((json) => Group.fromJson(json)).toList();
}

@JsonSerializable(createToJson: false)
class CreateGroupResponse {
  @JsonKey()
  late String groupId;

  static CreateGroupResponse fromJson(Map<String, dynamic> json) =>
      _$CreateGroupResponseFromJson(json);
}

@JsonSerializable(createToJson: false)
class AssetPreSignedUrlResponse {
  @JsonKey()
  late String url;

  @JsonKey()
  late String? assetId;

  static AssetPreSignedUrlResponse fromJson(Map<String, dynamic> json) =>
      _$AssetPreSignedUrlResponseFromJson(json);
}

class ContactSyncResponse {
  @JsonKey(ignore: true)
  late Set<String> available;

  static ContactSyncResponse fromJson(Map<String, dynamic> json) =>
      ContactSyncResponse()..available = json.keys.toSet();
}
