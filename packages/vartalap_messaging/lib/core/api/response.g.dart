// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ErrorResponse _$ErrorResponseFromJson(Map<String, dynamic> json) =>
    ErrorResponse()
      ..code = json['code'] as int?
      ..message = json['message'] as String?
      ..statusCode = json['StatusCode'] as int?
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
      ..userId = json['userId'] as String?;

GroupResponse _$GroupResponseFromJson(Map<String, dynamic> json) =>
    GroupResponse()
      ..groupId = json['groupId'] as String?
      ..name = json['name'] as String
      ..members =
          (json['members'] as List<dynamic>).map((e) => e as String).toList()
      ..profilePic = json['profilePic'] as String;

CreateGroupResponse _$CreateGroupResponseFromJson(Map<String, dynamic> json) =>
    CreateGroupResponse()..groupId = json['groupId'] as String;

AssetPreSignedUrlResponse _$AssetPreSignedUrlResponseFromJson(
        Map<String, dynamic> json) =>
    AssetPreSignedUrlResponse()
      ..url = json['url'] as String
      ..assetId = json['assetId'] as String?;
