import 'package:vartalap_messaging/core/api/base_api.dart';
import 'package:vartalap_messaging/core/api/response.dart';
import 'package:vartalap_messaging/core/http/http_client.dart';

class UserApi extends BaseApi {
  UserApi(HttpClient client) : super(client, 'profile');

  Future<ProfileResponse> get(String? userId) async {
    final path = endpoint(path: '');
    final response = await client.get(path);
    return ProfileResponse.fromJson(response.data);
  }
}
