import 'package:vartalap_messaging/core/api/base_api.dart';
import 'package:vartalap_messaging/core/http/http_client.dart';

class MessageApi extends BaseApi {
  MessageApi(HttpClient client) : super(client);

  @override
  // ignore: overridden_fields
  final String baseUrl = 'messages';
  Future<void> send(List<String> messages) async {
    final path = endpoint();
    await client.post(path, data: messages);
  }
}
