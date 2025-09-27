import 'package:vartalap_messaging_flutter/dao/dao.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';

/// ChatClient - Per-Channel Chat Operations
///
/// SCOPE: Operations specific to a single channel/chat
///
/// RESPONSIBILITIES:
/// - Message operations (send, edit, delete, mark as read)
/// - Member management (add, remove members)
/// - Channel-specific data streaming
/// - Permission checking
///
/// DESIGN PRINCIPLES:
/// - Delegates all database operations to ChatDao
/// - Maintains channel context for all operations
/// - Provides reactive streams for UI binding
/// - Handles optimistic updates for instant UI feedback
///
/// LOCAL-FIRST BEHAVIOR:
/// - All operations update local database immediately
/// - UI gets instant feedback without waiting for server
/// - Background sync handles server communication
///
/// USAGE PATTERN:
/// ```dart
/// final chatClient = await mainClient.chat(channel: channel, currentUser: user);
///
/// // Send message (local-first)
/// await chatClient.sendMessage([textMessage]);
///
/// // Watch messages reactively
/// chatClient.messagesStream.listen((messages) {
///   // UI updates automatically
/// });
///
/// // Edit message
/// await chatClient.editMessage(messageId, "Updated text");
/// ```
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

  String get displayName {
    if (channel.type == ChannelType.individual) {
      final member = _members.firstWhere((m) => m.user.id != currentUser.id);
      return member.user.displayName;
    }
    if (channel.extraData['name'] != null) {
      return channel.extraData['name']! as String;
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

  void dispose() {}

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

  Future<void> sendMessage(List<ChatMessage> messages) async {
    for (var message in messages) {
      await chatDao.sendMessage(message, channel);
      message.updateState(MessageState.pending);
    }
  }

  Selectable<ChatMessage> getMessages({
    MessageFilter? filter,
  }) {
    return chatDao.getMessages(channel: channel, filter: filter);
  }

  Future<void> editMessage(int messageId, String newText) async {
    final existingMessage = await chatDao
        .getMessages(
          channel: channel,
          filter: MessageFilter(messageId: messageId),
        )
        .getSingleOrNull();

    if (existingMessage == null) {
      throw Exception('Message with ID $messageId not found');
    }

    if (existingMessage.type == MessageType.text) {
      final updatedMessage = TextMessage(
        senderId: existingMessage.senderId,
        payload: {"text": newText},
        id: existingMessage.id,
        state: existingMessage.state,
        ts: existingMessage.timestamp,
        updatedAt: DateTime.now(),
        sender: existingMessage.sender,
      );
      await chatDao.updateMessage(messageId, updatedMessage);
    } else {
      throw Exception('Cannot edit message of type ${existingMessage.type}');
    }
  }

  Future<void> deleteMessage(int messageId) async {
    await chatDao.deleteMessage(messageId);
  }

  Future<void> markAsRead({int? messageId}) async {
    if (messageId != null) {
      await chatDao.markMessagesAsRead([messageId]);
    } else {
      await chatDao.markChannelAsRead(channel.id);
    }
  }

  bool hasSendMessagePermission() {
    return true;
  }
}
