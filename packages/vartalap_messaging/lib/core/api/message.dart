import 'package:vartalap_messaging/core/api/base_api.dart';
import 'package:vartalap_messaging/core/api/response.dart';
import 'package:vartalap_messaging/core/http/http_client.dart';
import 'package:vartalap_messaging/core/models/event.dart';

class MessageApi extends BaseApi {
  MessageApi(HttpClient client) : super(client, 'messages');

  Future<List<RemoteMessage>> send(List<RemoteMessage> messages,
      {String format = 'json', bool ack = false}) async {
    final path = endpoint();
    final response = await client.post(path, data: messages);
    RemoteMessagesResponse resp =
        RemoteMessagesResponse.fromJson(response.data);
    return resp.items;
  }

  Future<RemoteMessagesResponse> fetch() async {
    final path = endpoint();
    var response = await client.get(path);
    return RemoteMessagesResponse.fromJson(response.data);
  }
}
