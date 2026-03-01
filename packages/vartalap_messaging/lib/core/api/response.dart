import 'package:json_annotation/json_annotation.dart';
import 'package:vartalap_messaging/core/models/channel.dart';
import 'package:vartalap_messaging/core/models/event.dart';

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

  @JsonKey(includeFromJson: false)
  String get userId => username;

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
  late String? email;

  @JsonKey()
  late String? image;

  @JsonKey(includeFromJson: false)
  String get userId => username;

  static ProfileResponse fromJson(Map<String, dynamic> json) =>
      _$ProfileResponseFromJson(json);
}

@JsonSerializable(createToJson: false)
class ChannelResponse {
  @JsonKey(includeIfNull: false)
  late String? channelId;

  @JsonKey()
  late String name;

  @JsonKey()
  late List<dynamic> members;

  @JsonKey()
  late String profilePic;
  static ChannelResponse fromJson(Map<String, dynamic> json) =>
      _$ChannelResponseFromJson(json);
}

class ChannelsResponse {
  @JsonKey(includeFromJson: false)
  late List<ChannelPayload> items;

  static ChannelsResponse fromJson(List jsons) => ChannelsResponse()
    ..items = jsons.map((json) => ChannelPayload.fromJson(json)).toList();
}

@JsonSerializable(createToJson: false)
class CreateChannelResponse {
  @JsonKey()
  late String channelId;

  static CreateChannelResponse fromJson(Map<String, dynamic> json) =>
      _$CreateChannelResponseFromJson(json);
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
  @JsonKey(includeFromJson: true, includeToJson: false)
  late Set<String> available;

  static ContactSyncResponse fromJson(Map<String, dynamic> json) =>
      ContactSyncResponse()..available = json.keys.toSet();
}

@JsonSerializable(createToJson: false, createFactory: false)
class RemoteMessagesResponse {
  @JsonKey(includeFromJson: false, includeToJson: false)
  late List<RemoteMessage> items;

  static RemoteMessagesResponse fromJson(Map<String, dynamic> json) =>
      RemoteMessagesResponse()
        ..items = (json['messages'] as List)
            .map((msg) => RemoteMessage.fromJson(msg as Map<String, dynamic>))
            .toList();
}
