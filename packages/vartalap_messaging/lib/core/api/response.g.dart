// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ErrorResponse _$ErrorResponseFromJson(Map<String, dynamic> json) =>
    ErrorResponse()
      ..code = (json['code'] as num?)?.toInt()
      ..message = json['message'] as String?
      ..statusCode = (json['StatusCode'] as num?)?.toInt()
      ..moreInfo = json['moreInfo'] as String?;

Map<String, dynamic> _$ErrorResponseToJson(ErrorResponse instance) =>
    <String, dynamic>{
      'code': instance.code,
      'message': instance.message,
      'StatusCode': instance.statusCode,
      'moreInfo': instance.moreInfo,
    };

EmptyResponse _$EmptyResponseFromJson(Map<String, dynamic> json) =>
    EmptyResponse();

LoginResponse _$LoginResponseFromJson(Map<String, dynamic> json) =>
    LoginResponse()
      ..status = json['status'] as bool
      ..username = json['username'] as String
      ..accessKey = json['accesskey'] as String
      ..isNew = json['isNew'] as bool;

ProfileResponse _$ProfileResponseFromJson(Map<String, dynamic> json) =>
    ProfileResponse()
      ..name = json['name'] as String
      ..username = json['username'] as String
      ..email = json['email'] as String?
      ..image = json['image'] as String?;

ChannelResponse _$ChannelResponseFromJson(Map<String, dynamic> json) =>
    ChannelResponse()
      ..channelId = json['channelId'] as String?
      ..name = json['name'] as String
      ..members = json['members'] as List<dynamic>
      ..profilePic = json['profilePic'] as String;

CreateChannelResponse _$CreateChannelResponseFromJson(
        Map<String, dynamic> json) =>
    CreateChannelResponse()..channelId = json['channelId'] as String;

AssetPreSignedUrlResponse _$AssetPreSignedUrlResponseFromJson(
        Map<String, dynamic> json) =>
    AssetPreSignedUrlResponse()
      ..url = json['url'] as String
      ..assetId = json['assetId'] as String?;
