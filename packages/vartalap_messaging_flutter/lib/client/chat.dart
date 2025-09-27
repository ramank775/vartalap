import 'package:vartalap_messaging_flutter/dao/dao.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';

class ChatClient {
  final Contact currentUser;
  final VartalapChatClientFlutter client;
  final ChatDao chatDao;
  final ChannelModel channel;
  List<Member> _members = [];
  Stream<List<Member>>? _membersStream;
  Stream<List<ChatMessage>>? _messagesStream;
  ChatClient({
    required this.channel,
    required this.client,
    required this.chatDao,
    required this.currentUser,
  });

  get displayName {
    if (channel.type == ChannelType.individual) {
      final member = _members.firstWhere((m) => m.user.id != currentUser.id);
      return member.user.displayName;
    }
    if (channel.extraData['name'] != null) {
      return channel.extraData['name']!;
    }
    final groupName = _members.map((m) => m.user.displayName).join(', ');
    return groupName;
  }

  Future<void> init() async {
    _members = await chatDao.getMembers(channelId: channel.id).get();
  }

  void watch() {
    _membersStream = chatDao.getMembers(channelId: channel.id).watch();
    _messagesStream = chatDao.getMessages(channel: channel).watch();
  }

  dispose() {}

  Stream<List<Member>> get membersStream {
    return _membersStream!;
  }

  Stream<List<ChatMessage>> get messagesStream {
    return _messagesStream!;
  }

  Future<void> addMembers(List<Member> members) async {
    await chatDao.addMembers(members, channel);
  }

  Future<void> removeMember({
    Member? member,
    bool self = false,
  }) async {
    if (self) {
      member = _members.firstWhere(
        (m) => m.user.id == currentUser.id,
        orElse: () =>
            throw Exception('Current user not found in channel members'),
      );
    } else if (member == null) {
      return;
    }
    await chatDao.removeMember(member, channel);
  }

  Future<void> sendMessage(List<ChatMessage> msg) async {}

  Selectable<ChatMessage> getMessages({
    MessageFilter? filter,
  }) {
    return chatDao.getMessages(channel: channel, filter: filter);
  }

  bool hasSendMessagePermission() {
    return true;
  }
}
