import 'dart:async';
import 'package:vartalap_messaging/vartalap_messaging.dart' as messaging;
import 'package:vartalap_messaging_flutter/dao/dao.dart';
import 'package:vartalap_messaging_flutter/events/events.dart';
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
  final _typingController = StreamController<bool>.broadcast();
  StreamSubscription? _ephemeralSub;

  ChatClient({
    required this.channel,
    required this.client,
    required this.chatDao,
    required this.currentUser,
  });

  String get displayName {
    if (channel.type == ChannelType.individual) {
      final member = _members.firstWhere((m) => m.user.id != currentUser.id, orElse: () => _members.first);
      return member.user.displayName;
    }
    if (channel.extraData != null && channel.extraData!['name'] != null) {
      return channel.extraData!['name']! as String;
    }
    final groupName = _members.map((m) => m.user.displayName).join(', ');
    return groupName;
  }

  Future<void> init() async {
    _members = await chatDao.getMembers(channelId: channel.id).get();
    
    // Fallback if no members in DB yet (e.g. newly created channel)
    if (_members.isEmpty && channel.extraData != null && channel.extraData!['members'] != null) {
      final memberUids = channel.extraData!['members'] as List;
      // Note: This is a shallow mock for the UI to not crash
      _members = memberUids.map((uid) => Member(
        user: Contact(id: 0, username: uid.toString(), status: ContactStatus.active, uid: uid.toString()),
        role: 'member',
        since: DateTime.now(),
        updatedAt: DateTime.now(),
      )).toList();
    }
    
    // Listen for ephemeral events filtered for this channel
    _ephemeralSub = client.ephemeralEvents.listen((event) {
      if (event.head.category == 'typing') {
        final from = event.head.from;
        // Don't show typing for self
        if (from == currentUser.uid) return;

        // Check if event is for this channel
        bool relevant = false;
        if (channel.type == ChannelType.individual) {
          relevant = (channel.extraData != null && from == channel.extraData!['uid']); 
        } else {
          relevant = (event.head.to == channel.cid);
        }

        if (relevant) {
          final isTyping = event.body is Map
              ? event.body['typing'] as bool? ?? false
              : false;
          updateRemoteTypingStatus(isTyping);
        }
      }
    });
  }

  void watch() {
    _membersStream = chatDao.getMembers(channelId: channel.id).watch();
    _messagesStream = chatDao.getMessages(channel: channel).watch();
  }

  void dispose() {
    _ephemeralSub?.cancel();
    _typingController.close();
  }

  Stream<List<Member>> get membersStream {
    return _membersStream!;
  }

  Stream<List<ChatMessage>> get messagesStream {
    return _messagesStream!;
  }

  Stream<bool> get typingStream => _typingController.stream;

  Future<void> sendTypingIndicator(bool isTyping) async {
    final myUid = currentUser.uid;
    if (myUid == null) return;

    final target = channel.type == ChannelType.individual
        ? (channel.extraData?['uid'] as String?)
        : channel.cid;

    if (target == null) return;

    final head = messaging.Head(
      type: channel.type,
      to: target,
      from: myUid,
      category: 'typing',
      ephemeral: true,
    );

    final remoteMsg = messaging.RemoteMessage()
      ..id = 'typing_${DateTime.now().millisecondsSinceEpoch}'
      ..head = head
      ..meta = messaging.Meta()
      ..body = {'typing': isTyping};

    // Send directly via websocket (ephemeral)
    await client.client.sendMessage([remoteMsg], sync: false, ack: false);
  }

  /// Internal method to update typing status from remote events
  void updateRemoteTypingStatus(bool isTyping) {
    if (!_typingController.isClosed) {
      _typingController.add(isTyping);
    }
  }

  Future<void> addMembers(List<Member> members) async {
    await chatDao.addMembers(members, channel);

    final task = client.factory.create(
      AddMembersTask.name,
      payload: AddMembersPayload(
        localChannelId: channel.id,
        localMemberIds: members.map((m) => m.user.id).toList(),
      ),
    );
    await client.scheduler.schedule(task);
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

    final task = client.factory.create(
      RemoveMemberTask.name,
      payload: RemoveMemberPayload(
        localChannelId: channel.id,
        localMemberId: member.user.id,
      ),
    );
    await client.scheduler.schedule(task);
  }

  Future<void> sendMessage(List<ChatMessage> messages) async {
    for (var message in messages) {
      final id = await chatDao.sendMessage(message, channel);
      message.updateState(MessageState.pending);

      // Schedule background sync task
      final task = client.factory.create(
        SendMessageTask.name,
        payload: SendMessage(channel.id, [id]),
      );
      await client.scheduler.schedule(task);
    }
  }

  Future<void> sendAttachment(String path, String category) async {
    await client.sendAttachment(
      channelId: channel.id,
      path: path,
      category: category,
      currentUser: currentUser,
    );
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
      final updatedMessage = ChatMessage.text(
        channelId: channel.id,
        senderId: existingMessage.senderId,
        text: newText,
        id: existingMessage.id,
        state: existingMessage.state,
        timestamp: existingMessage.timestamp,
      ).copyWith(sender: existingMessage.sender);
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
      await _sendReadReceipt(messageId: messageId);
    } else {
      await chatDao.markChannelAsRead(channel.id);
      await _sendReadReceipt();
    }
  }

  /// Sends a read receipt ack to the server
  Future<void> _sendReadReceipt({int? messageId}) async {
    final myUid = currentUser.uid;
    if (myUid == null) return;

    final target = channel.type == ChannelType.individual
        ? (channel.extraData?['uid'] as String?)
        : channel.cid;

    if (target == null) return;

    // If messageId provided, send ack for that specific message.
    // Otherwise, send ack for the channel (server handles resolving latest).
    String? remoteId;
    if (messageId != null) {
      final msg = await chatDao.getMessages(channel: channel, filter: MessageFilter(messageId: messageId)).getSingleOrNull();
      remoteId = msg?.rid;
    }

    final head = messaging.Head(
      type: channel.type,
      to: target,
      from: myUid,
      category: 'ack',
      ephemeral: true,
    );

    final remoteMsg = messaging.RemoteMessage()
      ..id = remoteId ?? 'channel_read_${channel.id}'
      ..head = head
      ..meta = messaging.Meta(hash: 'read') // Using meta to flag as read status
      ..body = {'status': 'read', 'channelId': channel.cid};

    await client.client.sendMessage([remoteMsg], sync: false, ack: false);
  }

  bool hasSendMessagePermission() {
    return true;
  }
}
