import 'package:vartalap_messaging/core/api/base_api.dart';
import 'package:vartalap_messaging/core/api/response.dart';
import 'package:vartalap_messaging/core/http/http_client.dart';
import 'package:vartalap_messaging/core/models/credentail.dart';

class AuthApi extends BaseApi {
  AuthApi(HttpClient client) : super(client, 'login');

  Future<LoginResponse> login(Credential credentails) async {
    final path = endpoint();

    final response = await client.post(path, data: Credential);
    return LoginResponse.fromJson(response.data);
  }
}
