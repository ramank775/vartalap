import 'package:json_annotation/json_annotation.dart';

part 'credentail.g.dart';

@JsonSerializable()
class Credential {
  @JsonKey()
  String username;

  @JsonKey(name: "authToken")
  String externalAuthToken;

  @JsonKey(includeIfNull: true)
  String? notificationToken;

  String deviceId = "default";

  Credential({
    required this.username,
    required this.externalAuthToken,
    this.notificationToken,
    this.deviceId = "default",
  });

  static Credential fromJson(Map<String, dynamic> json) =>
      _$CredentialFromJson(json);

  Map<String, dynamic> toJson() => _$CredentialToJson(this);
}
