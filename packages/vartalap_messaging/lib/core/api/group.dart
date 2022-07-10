import 'package:vartalap_messaging/core/api/base_api.dart';
import 'package:vartalap_messaging/core/api/response.dart';
import 'package:vartalap_messaging/core/http/http_client.dart';
import 'package:vartalap_messaging/core/models/group.dart';

class GroupApi extends BaseApi {
  GroupApi(HttpClient client) : super(client);

  @override
  // ignore: overridden_fields
  final String baseUrl = 'groups';
  Future<GroupsResponse> getAll() async {
    final path = endpoint(path: '');
    final response = await client.get(path);
    return GroupsResponse.fromJson(response.data);
  }

  Future<GroupResponse> getInfo(String groupId) async {
    final path = endpoint(path: '/$groupId');
    final response = await client.get(path);
    return GroupResponse.fromJson(response.data);
  }

  Future<CreateGroupResponse> create(Group group) async {
    final path = endpoint(path: '');
    final response = await client.post(path, data: group);
    return CreateGroupResponse.fromJson(response.data);
  }

  Future<EmptyResponse> addMembers(String groupId, List<String> members) async {
    final path = endpoint(path: '$groupId/members');
    final group = Group()..members = members;
    final response = await client.post(path, data: group);
    return EmptyResponse.fromJson(response.data);
  }

  Future<EmptyResponse> removeMember(String groupId, String member) async {
    final path = endpoint(path: '$groupId/members');
    final data = {"member": member};
    final response = await client.delete(path, data: data);
    return EmptyResponse.fromJson(response.data);
  }
}
