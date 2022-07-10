import 'package:vartalap_messaging/core/api/base_api.dart';
import 'package:vartalap_messaging/core/api/response.dart';
import 'package:vartalap_messaging/core/http/http_client.dart';

class ContactBookApi extends BaseApi {
  ContactBookApi(HttpClient client) : super(client);

  @override
  // ignore: overridden_fields
  final String baseUrl = 'contactbook';
  Future<ContactSyncResponse> sync(List<String> contacts) async {
    final path = endpoint(path: 'sync');
    final data = {
      'users': contacts,
    };
    final response = await client.post(path, data: data);
    return ContactSyncResponse.fromJson(response.data);
  }
}
