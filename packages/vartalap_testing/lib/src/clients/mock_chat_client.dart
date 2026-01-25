import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:vartalap/config/app_config.dart';
import 'package:vartalap_messaging/vartalap_messaging.dart';
import 'package:vartalap_testing/src/engine/scenario.dart';

class MockVartalapChatClient extends VartalapChatClient
    implements SimulatorController {
  final String mockUserId;
  final StreamController<RemoteMessage> _eventController =
      StreamController<RemoteMessage>.broadcast();

  // Active Scenario
  MockScenario _scenario;

  // Public getter for the current scenario
  MockScenario get activeScenario => _scenario;

  // Mock data storage
  final Map<String, List<Map<String, dynamic>>> _channelMessages = {};

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

  /// Change the active scenario at runtime
  void setScenario(MockScenario scenario) {
    _scenario = scenario;
    debugPrint('[MOCK] Switched to scenario: ${scenario.runtimeType}');
  }

  @override
  String get currentUserId => mockUserId;

  @override
  Stream<RemoteMessage> get eventStream => _eventController.stream;

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
    debugPrint('[MOCK] Injecting manual error for $messageId: $errorMessage');
    // Error is handled by not sending an ack or sending a failure ack
    simulateAck(messageId, 'error');
  }

  // --- Client Overrides ---

  @override
  Future<void> sendMessage(List<RemoteMessage> messages,
      {bool sync = false, bool ack = true}) async {
    if (!AppConfig.isTesting) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    for (var message in messages) {
      final channelId = message.head.to;
      _channelMessages.putIfAbsent(channelId, () => []);
      _channelMessages[channelId]!.add(message.toJson());

      // Delegate to the current scenario
      unawaited(_scenario.onMessageSent(this, message));
    }
  }

  @override
  Future<LoginResponse> login(Credential creds) async {
    if (!AppConfig.isTesting) {
      await Future.delayed(const Duration(milliseconds: 300));
    }
    return LoginResponse.fromJson({
      "status": true,
      "username": creds.username,
      "accesskey": "mock_access_key_${DateTime.now().millisecondsSinceEpoch}",
      "isNew": false,
      "userId": mockUserId,
    });
  }

  @override
  Future<ProfileResponse> fetchProfile(String userId) async {
    if (!AppConfig.isTesting) {
      await Future.delayed(const Duration(milliseconds: 200));
    }

    return ProfileResponse.fromJson({
      "name": "Mock User",
      "username": userId,
      "email": "mock@example.com",
      "image": "",
    });
  }

  @override
  Future<void> close() async {
    await _eventController.close();
  }
}

/// The default "Happy Path" behavior
class DefaultHappyPathScenario extends MockScenario {
  @override
  Future<void> onMessageSent(
      SimulatorController controller, RemoteMessage message) async {
    // Progress: Sent -> Delivered -> Read
    await controller.simulateAck(message.id, 'sent',
        delay: const Duration(milliseconds: 500));
    await controller.simulateAck(message.id, 'delivered',
        delay: const Duration(seconds: 2));
    await controller.simulateAck(message.id, 'read',
        delay: const Duration(seconds: 5));
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
