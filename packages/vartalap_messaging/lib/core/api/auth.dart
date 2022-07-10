import 'package:vartalap_messaging/core/api/base_api.dart';
import 'package:vartalap_messaging/core/api/response.dart';
import 'package:vartalap_messaging/core/http/http_client.dart';

class AuthApi extends BaseApi {
  AuthApi(HttpClient client) : super(client);

  @override
  // ignore: overridden_fields
  final String baseUrl = 'login';
  Future<LoginResponse> get() async {
    final path = endpoint();
    final response = await client.get(path);
    return LoginResponse.fromJson(response.data);
  }
}
