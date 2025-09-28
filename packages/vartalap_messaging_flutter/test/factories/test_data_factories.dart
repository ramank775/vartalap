import 'dart:typed_data';
import 'package:vartalap_messaging_flutter/models/models.dart';
import 'package:vartalap_messaging/vartalap_messaging.dart';

/// Test data factories for creating consistent mock data
/// 
/// Provides factory methods to generate realistic test data
/// for contacts, channels, messages, and other entities.
class TestDataFactories {
  static int _contactCounter = 1;
  static int _channelCounter = 1;
  static int _messageCounter = 1;

  /// Reset all counters for clean test isolation
  static void resetCounters() {
    _contactCounter = 1;
    _channelCounter = 1;
    _messageCounter = 1;
  }

  /// Creates a test contact with realistic data
  static Contact createContact({
    int? id,
    String? username,
    String? uid,
    String? name,
    String? phone,
    Uint8List? thumbnail,
    String? photo,
    ContactStatus? status,
    Map<String, dynamic>? extraData,
  }) {
    return Contact(
      id: id ?? _contactCounter++,
      username: username ?? "testuser$_contactCounter",
      uid: uid,
      name: name ?? "Test User $_contactCounter",
      phone: phone ?? "+1234567${_contactCounter.toString().padLeft(4, '0')}",
      thumbnail: thumbnail,
      photo: photo,
      status: status ?? ContactStatus.active,
      extraData: extraData,
    );
  }

  /// Creates multiple test contacts
  static List<Contact> createContacts(int count) {
    return List.generate(count, (index) => createContact());
  }

  /// Creates a test channel with realistic data
  static ChannelModel createChannel({
    int? id,
    ChannelType? type,
    bool? isMuted,
    ChannelConfig? config,
    Map<String, Object?>? extraData,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final channelConfig = config ?? ChannelConfig(
      isPublic: false,
      isMuted: isMuted ?? false,
    );
    
    final channelExtraData = extraData ?? {
      'name': 'Test Channel $_channelCounter',
      'description': 'Test channel description $_channelCounter',
    };

    return ChannelModel(
      id: id ?? _channelCounter++,
      type: type ?? ChannelType.group,
      config: channelConfig,
      isMuted: isMuted ?? false,
      extraData: channelExtraData,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// Creates multiple test channels
  static List<ChannelModel> createChannels(int count) {
    return List.generate(count, (index) => createChannel());
  }

  /// Creates a test member
  static Member createMember({
    Contact? user,
    DateTime? since,
    String? role,
  }) {
    return Member(
      user: user ?? createContact(),
      since: since ?? DateTime.now(),
      role: role ?? 'member',
    );
  }

  /// Creates multiple test members
  static List<Member> createMembers(int count) {
    return List.generate(count, (index) => createMember());
  }

  /// Creates a test text message
  static TextMessage createTextMessage({
    int? id,
    int? senderId,
    Contact? sender,
    String? text,
    MessageState? state,
    DateTime? ts,
    DateTime? updatedAt,
  }) {
    return TextMessage(
      id: id ?? _messageCounter++,
      senderId: senderId ?? 1,
      payload: {"text": text ?? "Test message $_messageCounter"},
      sender: sender,
      state: state ?? MessageState.sent,
      ts: ts ?? DateTime.now(),
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  /// Creates multiple test messages for a conversation
  static List<TextMessage> createConversation({
    int messageCount = 5,
    List<int>? senderIds,
  }) {
    final senders = senderIds ?? [1, 2];
    return List.generate(messageCount, (index) {
      final senderId = senders[index % senders.length];
      return createTextMessage(
        senderId: senderId,
        text: "Message ${index + 1} from sender $senderId",
        ts: DateTime.now().subtract(Duration(minutes: messageCount - index)),
      );
    });
  }

  /// Creates a test attachment
  static Attachment createAttachment({
    int? id,
    String? path,
    String? name,
    String? type,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Attachment(
      id: id ?? _messageCounter++,
      path: path ?? "/test/path/file.jpg",
      name: name ?? "test_file.jpg",
      type: type ?? "image",
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// Creates a test chat preview
  static ChatPreview createChatPreview({
    ChannelModel? channel,
    ChatMessage? lastMessage,
    int? unreadCount,
  }) {
    return ChatPreview(
      channel: channel ?? createChannel(),
      lastMessage: lastMessage ?? createTextMessage(),
      unreadCount: unreadCount ?? 0,
    );
  }

  /// Creates multiple test chat previews
  static List<ChatPreview> createChatPreviews(int count) {
    return List.generate(count, (index) => createChatPreview(
      unreadCount: index % 3, // Some chats have unread messages
    ));
  }

  /// Creates a complete test dataset with related entities
  static TestDataSet createCompleteDataSet({
    int contactCount = 5,
    int channelCount = 3,
    int messagesPerChannel = 10,
  }) {
    final contacts = createContacts(contactCount);
    final channels = createChannels(channelCount);
    
    // Create messages for each channel
    final allMessages = <TextMessage>[];
    for (int i = 0; i < channels.length; i++) {
      final channelMessages = createConversation(
        messageCount: messagesPerChannel,
        senderIds: contacts.take(2).map((c) => c.id).toList(),
      );
      allMessages.addAll(channelMessages);
    }

    // Create members for each channel
    final allMembers = <Member>[];
    for (int i = 0; i < channels.length; i++) {
      final channelMembers = contacts.take(3).map((contact) => 
        createMember(user: contact)
      ).toList();
      allMembers.addAll(channelMembers);
    }

    return TestDataSet(
      contacts: contacts,
      channels: channels,
      messages: allMessages,
      members: allMembers,
    );
  }
}

/// Container for a complete set of test data
class TestDataSet {
  final List<Contact> contacts;
  final List<ChannelModel> channels;
  final List<TextMessage> messages;
  final List<Member> members;

  const TestDataSet({
    required this.contacts,
    required this.channels,
    required this.messages,
    required this.members,
  });

  /// Get contacts by IDs
  List<Contact> getContactsByIds(List<int> ids) {
    return contacts.where((c) => ids.contains(c.id)).toList();
  }

  /// Get members for a specific channel  
  List<Member> getMembersForChannel(int channelId) {
    // For testing purposes, return first few members
    // In real implementation, we'd need proper channel-member mapping
    return members.take(3).toList();
  }
}

/// Quick access to commonly used test data
class QuickTestData {
  /// Standard test user ID used across tests
  static const int testUserId = 123;
  
  /// Standard test channel ID used across tests
  static const int testChannelId = 456;
  
  /// Creates a minimal test contact (current user)
  static Contact get testUser => TestDataFactories.createContact(
    id: testUserId,
    username: "testuser",
    name: "Test User",
  );

  /// Creates a minimal test channel
  static ChannelModel get testChannel => TestDataFactories.createChannel(
    id: testChannelId,
    extraData: {
      'name': 'Test Channel',
    },
  );

  /// Creates a simple test message
  static TextMessage get testMessage => TestDataFactories.createTextMessage(
    senderId: testUserId,
    text: "Hello, World!",
  );
}