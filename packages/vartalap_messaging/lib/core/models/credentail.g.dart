// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'credentail.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Credential _$CredentialFromJson(Map<String, dynamic> json) => Credential(
      username: json['username'] as String,
      externalAuthToken: json['authToken'] as String,
      notificationToken: json['notificationToken'] as String?,
      deviceId: json['deviceId'] as String? ?? "default",
    );

Map<String, dynamic> _$CredentialToJson(Credential instance) =>
    <String, dynamic>{
      'username': instance.username,
      'authToken': instance.externalAuthToken,
      'notificationToken': instance.notificationToken,
      'deviceId': instance.deviceId,
    };
