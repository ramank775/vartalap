import 'dart:io';
import 'package:vartalap_messaging/core/api/base_api.dart';
import 'package:vartalap_messaging/core/api/response.dart';
import 'package:vartalap_messaging/core/http/http_client.dart';

class AssetApi extends BaseApi {
  AssetApi(HttpClient client) : super(client, 'assets');

  Future<void> uploadFile(String url, File file) async {
    await client.uploadFile(url, file);
  }

  Future<AssetPreSignedUrlResponse> uploadUrl(
      String extension, String category) async {
    final path = endpoint(
      path: '/upload/presigned_url',
    );
    final Map<String, String> queryParams = {
      'ext': extension,
      'category': category
    };
    final response = await client.get(path, queryParams: queryParams);
    return AssetPreSignedUrlResponse.fromJson(response.data);
  }

  Future<AssetPreSignedUrlResponse> downloadUrl(String assetId) async {
    final path = endpoint(
      path: '/download/$assetId/presigned_url',
    );
    final response = await client.get(path);
    return AssetPreSignedUrlResponse.fromJson(response.data);
  }

  Future<EmptyResponse> markAssetAsUploaded(String assetId) async {
    final path = endpoint(
      path: '$assetId/status',
    );

    final response = await client.put(path, data: {'status': true});
    return EmptyResponse.fromJson(response.data);
  }
}
