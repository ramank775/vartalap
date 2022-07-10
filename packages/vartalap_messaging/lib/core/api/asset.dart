import 'package:vartalap_messaging/core/api/base_api.dart';
import 'package:vartalap_messaging/core/api/response.dart';
import 'package:vartalap_messaging/core/http/http_client.dart';

class AssetApi extends BaseApi {
  AssetApi(HttpClient client) : super(client);

  @override
  // ignore: overridden_fields
  final String baseUrl = 'assets';

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

    final response = await client.post(path, data: {'status': true});
    return EmptyResponse.fromJson(response.data);
  }
}
