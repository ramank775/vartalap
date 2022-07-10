import 'package:vartalap_messaging/core/api/base_api.dart';
import 'package:vartalap_messaging/core/api/response.dart';
import 'package:vartalap_messaging/core/http/http_client.dart';

class UserApi extends BaseApi {
  UserApi(HttpClient client) : super(client);

  @override
  // ignore: overridden_fields
  final String baseUrl = 'profile';
  Future<ProfileResponse> get() async {
    final path = endpoint(path: '');
    final response = await client.post(path);
    return ProfileResponse.fromJson(response.data);
  }
}
