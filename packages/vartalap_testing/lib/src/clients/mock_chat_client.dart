import 'dart:async';

import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:vartalap_messaging/vartalap_messaging.dart';
import 'package:vartalap_testing/src/engine/scenario.dart';

class MockVartalapChatClient extends VartalapChatClient
    implements SimulatorController {
  String mockUserId;
  final StreamController<RemoteMessage> _eventController =
      StreamController<RemoteMessage>.broadcast();

  MockScenario _scenario;

  MockScenario get activeScenario => _scenario;

  // Mock data storage
  final Map<String, List<Map<String, dynamic>>> _channelMessages = {};
  final List<ChannelPayload> _channels = [];
  final Map<String, Map<String, dynamic>> _profiles = {};

  /// IDs of messages sent via sendMessage(), most recent last.
  /// The developer menu uses this to ack messages sent from the chat UI.
  final List<String> sentMessageIds = [];

  bool get _isTesting =>
      const bool.fromEnvironment('dart.library.io') &&
      Platform.environment.containsKey('FLUTTER_TEST');

  MockVartalapChatClient({
    this.mockUserId = "+1234567890",
    required super.tokenManager,
    MockScenario? initialScenario,
  })  : _scenario = initialScenario ?? DefaultHappyPathScenario(),
        super(
          apiKey: "mock_api_key",
          apiBaseUrl: "http://localhost:3000",
          wsUrl: "ws://localhost:3000",
        );

  void setScenario(MockScenario scenario) {
    _scenario = scenario;
    debugPrint('[MOCK] Switched to scenario: ${scenario.runtimeType}');
  }

  @override
  String get currentUserId => mockUserId;

  @override
  Stream<RemoteMessage> get eventStream => _eventController.stream;

  @override
  Future<String?> getLoggedInUser() async {
    final fromToken = await super.getLoggedInUser();
    return fromToken ?? mockUserId;
  }

  // --- SimulatorController Implementation ---

  @override
  void injectMessage(RemoteMessage message) {
    debugPrint('[MOCK] Injecting manual message: ${message.id}');
    _eventController.add(message);
  }

  @override
  Future<void> simulateAck(String messageId, String status,
      {Duration delay = Duration.zero}) async {
    if (delay != Duration.zero) {
      await Future.delayed(delay);
    }

    final ack = RemoteMessage()
      ..id = messageId
      ..head = Head(
        type: ChannelType.none,
        to: mockUserId,
        from: 'server',
        category: 'ack',
      )
      ..meta = Meta()
      ..body = {'status': status};

    ack.meta.raw['status'] = status;
    _eventController.add(ack);
    debugPrint('[MOCK] Emitted ack: $messageId -> $status');
  }

  @override
  void simulateError(String messageId, String errorMessage) {
    debugPrint('[MOCK] Injecting error for $messageId: $errorMessage');
    simulateAck(messageId, 'error');
  }

  // --- Client Overrides ---

  @override
  Future<void> sendMessage(List<RemoteMessage> messages,
      {bool sync = false, bool ack = true}) async {
    if (!_isTesting) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    for (var message in messages) {
      // Skip ephemeral messages (typing indicators etc.)
      if (message.head.ephemeral) continue;

      final channelId = message.head.to;
      _channelMessages.putIfAbsent(channelId, () => []);
      _channelMessages[channelId]!.add(message.toJson());
      sentMessageIds.add(message.id);
      unawaited(_scenario.onMessageSent(this, message));
    }
  }

  @override
  Future<LoginResponse> login(Credential creds) async {
    if (!_isTesting) {
      await Future.delayed(const Duration(milliseconds: 300));
    }
    mockUserId = creds.username;
    return LoginResponse.fromJson({
      "status": true,
      "username": creds.username,
      "accesskey": "mock_access_key_${DateTime.now().millisecondsSinceEpoch}",
      "isNew": false,
      "userId": creds.username,
    });
  }

  @override
  Future<ProfileResponse> fetchProfile(String userId) async {
    if (!_isTesting) {
      await Future.delayed(const Duration(milliseconds: 200));
    }
    await _scenario.onProfileRequested(this, userId);

    final stored = _profiles[userId];
    return ProfileResponse.fromJson(stored ?? {
      "name": "Mock User",
      "username": userId,
      "email": "mock@example.com",
      "image": "",
    });
  }

  @override
  Future<ProfileResponse> updateProfile(Map<String, dynamic> updates) async {
    if (!_isTesting) {
      await Future.delayed(const Duration(milliseconds: 200));
    }
    _profiles.putIfAbsent(mockUserId, () => {
      "name": "Mock User",
      "username": mockUserId,
      "email": "mock@example.com",
      "image": "",
    });
    _profiles[mockUserId]!.addAll(updates);
    await _scenario.onProfileUpdated(this, updates);
    return ProfileResponse.fromJson(_profiles[mockUserId]!);
  }

  @override
  Future<CreateChannelResponse> createChannel(ChannelPayload channel) async {
    if (!_isTesting) {
      await Future.delayed(const Duration(milliseconds: 200));
    }
    final channelId = 'mock_channel_${DateTime.now().millisecondsSinceEpoch}';
    channel.channelId = channelId;
    _channels.add(channel);
    await _scenario.onChannelCreated(this, channel);
    return CreateChannelResponse.fromJson({'channelId': channelId});
  }

  @override
  Future<ChannelsResponse> queryChannels() async {
    if (!_isTesting) {
      await Future.delayed(const Duration(milliseconds: 200));
    }
    return ChannelsResponse.fromJson(
        _channels.map((c) => c.toJson()).toList());
  }

  @override
  Future<ChannelResponse> getChannelInfo(String channelId) async {
    if (!_isTesting) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    final channel = _channels.cast<ChannelPayload?>().firstWhere(
        (c) => c?.channelId == channelId,
        orElse: () => null);
    if (channel == null) {
      throw Exception('Channel $channelId not found');
    }
    return ChannelResponse.fromJson({
      'channelId': channel.channelId,
      'name': channel.name,
      'members': channel.members,
      'profilePic': channel.profilePic,
    });
  }

  @override
  Future<ChannelResponse> updateChannel(
      String channelId, Map<String, dynamic> updates) async {
    if (!_isTesting) {
      await Future.delayed(const Duration(milliseconds: 200));
    }
    await _scenario.onChannelUpdated(this, channelId, updates);
    return ChannelResponse.fromJson({
      'channelId': channelId,
      'name': updates['name'] ?? 'Updated Channel',
      'members': [],
      'profilePic': updates['profilePic'] ?? '',
    });
  }

  @override
  Future<void> addChannelMembers(
      String channelId, List<String> memberIds) async {
    if (!_isTesting) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    await _scenario.onMembersAdded(this, channelId, memberIds);
  }

  @override
  Future<void> removeChannelMember(String channelId, String member) async {
    if (!_isTesting) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    await _scenario.onMemberRemoved(this, channelId, member);
  }

  @override
  Future<List<RemoteMessage>> syncMessages({bool stream = false}) async {
    return [];
  }

  @override
  Future<Map<String, String>> syncContactBook(List<String> contacts) async {
    return {for (var c in contacts) c: c};
  }

  @override
  Future<AssetPreSignedUrlResponse> getUploadUrl(
      String ext, String category) async {
    if (!_isTesting) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    return AssetPreSignedUrlResponse.fromJson({
      "url": "https://mock-storage.example.com/upload/${DateTime.now().millisecondsSinceEpoch}.$ext",
      "fileId": "mock_asset_${DateTime.now().millisecondsSinceEpoch}",
    });
  }

  @override
  Future<AssetPreSignedUrlResponse> getDownloadUrl(String assetId) async {
    return AssetPreSignedUrlResponse.fromJson({
      "url": "https://mock-storage.example.com/download/$assetId",
      "fileId": assetId,
    });
  }

  @override
  Future<void> markAssetAsUploaded(String assetId) async {}

  @override
  Future<void> uploadAsset(String url, File file) async {}

  @override
  Future<void> close() async {
    await _eventController.close();
  }
}

/// Configurable happy path scenario with adjustable delays
class DefaultHappyPathScenario extends MockScenario {
  final Duration sentDelay;
  final Duration deliveredDelay;
  final Duration readDelay;

  DefaultHappyPathScenario({
    this.sentDelay = const Duration(milliseconds: 500),
    this.deliveredDelay = const Duration(seconds: 2),
    this.readDelay = const Duration(seconds: 5),
  });

  /// Fast variant for unit tests — minimal delays
  factory DefaultHappyPathScenario.fast() => DefaultHappyPathScenario(
        sentDelay: const Duration(milliseconds: 10),
        deliveredDelay: const Duration(milliseconds: 50),
        readDelay: const Duration(milliseconds: 100),
      );

  @override
  Future<void> onMessageSent(
      SimulatorController controller, RemoteMessage message) async {
    await controller.simulateAck(message.id, 'sent', delay: sentDelay);
    await controller.simulateAck(message.id, 'delivered',
        delay: deliveredDelay);
    await controller.simulateAck(message.id, 'read', delay: readDelay);
  }
}

class MockChannel {
  final String id;
  final String type;
  final String name;
  final List<String> members;
  final String createdBy;
  final DateTime createdAt;

  MockChannel({
    required this.id,
    required this.type,
    required this.name,
    required this.members,
    required this.createdBy,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'name': name,
        'members': members,
        'createdBy': createdBy,
        'createdAt': createdAt.toIso8601String(),
      };

  factory MockChannel.fromJson(Map<String, dynamic> json) => MockChannel(
        id: json['id'] as String,
        type: json['type'] as String,
        name: json['name'] as String,
        members: List<String>.from(json['members'] as List),
        createdBy: json['createdBy'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

class MockProfile {
  final String userId;
  final String name;
  final String email;
  final String? imageUrl;

  MockProfile({
    required this.userId,
    required this.name,
    required this.email,
    this.imageUrl,
  });

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'name': name,
        'email': email,
        'imageUrl': imageUrl,
      };

  factory MockProfile.fromJson(Map<String, dynamic> json) => MockProfile(
        userId: json['userId'] as String,
        name: json['name'] as String,
        email: json['email'] as String,
        imageUrl: json['imageUrl'] as String?,
      );
}
