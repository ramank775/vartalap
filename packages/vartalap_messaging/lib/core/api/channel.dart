import 'package:vartalap_messaging/core/api/base_api.dart';
import 'package:vartalap_messaging/core/api/response.dart';
import 'package:vartalap_messaging/core/http/http_client.dart';
import 'package:vartalap_messaging/core/models/channel.dart';

class ChannelApi extends BaseApi {
  ChannelApi(HttpClient client) : super(client, 'channels');

  Future<ChannelsResponse> getAll() async {
    final path = endpoint(path: '');
    final response = await client.get(path);
    return ChannelsResponse.fromJson(response.data);
  }

  Future<CreateChannelResponse> create(ChannelPayload channel) async {
    final path = endpoint(path: '');
    final response = await client.post(path, data: channel);
    return CreateChannelResponse.fromJson(response.data);
  }

  Future<ChannelResponse> getInfo(String channelId) async {
    final path = endpoint(path: '/$channelId');
    final response = await client.get(path);
    return ChannelResponse.fromJson(response.data);
  }

  Future<EmptyResponse> addMembers(
      String channelId, List<String> members) async {
    final path = endpoint(path: '$channelId/members');
    final group = ChannelPayload()..members = members;
    final response = await client.post(path, data: group);
    return EmptyResponse.fromJson(response.data);
  }

  Future<EmptyResponse> removeMember(String channelId, String member) async {
    final path = endpoint(path: '$channelId/members');
    final data = {"member": member};
    final response = await client.delete(path, data: data);
    return EmptyResponse.fromJson(response.data);
  }
}
