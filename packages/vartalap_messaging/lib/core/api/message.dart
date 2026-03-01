import 'package:vartalap_messaging/core/api/base_api.dart';
import 'package:vartalap_messaging/core/api/response.dart';
import 'package:vartalap_messaging/core/http/http_client.dart';
import 'package:vartalap_messaging/core/models/event.dart';

class MessageApi extends BaseApi {
  MessageApi(HttpClient client) : super(client, 'messages');

  Future<List<RemoteMessage>> send(List<RemoteMessage> messages,
      {String format = 'json', bool ack = false}) async {
    final path = endpoint();
    final queryParams = <String, String>{};
    if (ack) queryParams['ack'] = 'true';
    if (format != 'json') queryParams['format'] = format;
    final response = await client.post(path,
        data: messages.map((m) => m.toJson()).toList(),
        queryParams: queryParams.isEmpty ? null : queryParams);
    if (!ack) return [];
    final acks = (response.data['acks'] as List?)
        ?.map(
            (msg) => RemoteMessage.fromJson(msg as Map<String, dynamic>))
        .toList();
    return acks ?? [];
  }

  Future<RemoteMessagesResponse> fetch() async {
    final path = endpoint();
    var response = await client.get(path);
    return RemoteMessagesResponse.fromJson(
        response.data as Map<String, dynamic>);
  }
}
