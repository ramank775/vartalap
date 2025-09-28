import 'dart:async';

import 'package:vartalap_messaging/vartalap_messaging.dart';

/// MockVartalapChatClient for testing local-first functionality
/// 
/// This mock client bypasses all server communication and provides
/// fake responses for authentication and API calls. Perfect for testing
/// local database operations and business logic without server dependencies.
class MockVartalapChatClient extends VartalapChatClient {
  final String mockUserId;
  final StreamController<RemoteMessage> _eventController = 
      StreamController<RemoteMessage>.broadcast();

  MockVartalapChatClient({
    this.mockUserId = "test_user_123",
  }) : super(
          apiKey: "mock_api_key",
          tokenManager: MockTokenManager(),
          apiBaseUrl: "http://localhost:3000",
          wsUrl: "ws://localhost:3000",
        );

  @override
  Stream<RemoteMessage> get eventStream => _eventController.stream;

  @override
  Future<String?> getLoggedInUser() async {
    // Always return a mock logged-in user for local testing
    return mockUserId;
  }

  @override
  Future<LoginResponse> login(Credential creds) async {
    // Simulate successful login without server call
    return LoginResponse.fromJson({
      "status": true,
      "username": creds.username,
      "accesskey": "mock_access_key",
      "isNew": false,
      "userId": mockUserId,
    });
  }

  @override
  Future<ProfileResponse> fetchProfile(String userId) async {
    // Return mock profile data with correct field names
    return ProfileResponse.fromJson({
      "name": "Test User",
      "username": userId,
      "email": "test@example.com",
      "image": "https://example.com/avatar.png"
    });
  }

  @override
  Future<CreateChannelResponse> createChannel(ChannelPayload channel) async {
    // Simulate channel creation without server call
    return CreateChannelResponse.fromJson({
      "channelId": "mock_channel_${DateTime.now().millisecondsSinceEpoch}",
    });
  }

  @override
  Future<ChannelsResponse> queryChannels() async {
    // Return empty channels list for local testing
    return ChannelsResponse.fromJson([]);
  }

  @override
  Future<ChannelResponse> getChannelInfo(String channelId) async {
    // Return mock channel info
    return ChannelResponse.fromJson({
      "status": true,
      "channel": {
        "id": channelId,
        "name": "Mock Channel",
        "type": "group",
        "createdBy": mockUserId,
        "createdAt": DateTime.now().toIso8601String(),
        "members": [mockUserId],
      }
    });
  }

  @override
  Future<void> addChannelMembers(String channelId, List<String> memberIds) async {
    // Simulate successful member addition
    return;
  }

  @override
  Future<void> removeChannelMember(String channelId, String member) async {
    // Simulate successful member removal
    return;
  }

  @override
  Future<void> sendMessage(
    List<RemoteMessage> messages, {
    bool sync = false,
    bool ack = true,
  }) async {
    // Simulate message sending without WebSocket
    if (ack) {
      for (var message in messages) {
        // Simulate acknowledgment
        final ackMessage = RemoteMessage.fromJson({
          ...message.toJson(),
          "status": "sent",
          "timestamp": DateTime.now().toIso8601String(),
        });
        _eventController.add(ackMessage);
      }
    }
  }

  @override
  Future<List<RemoteMessage>> syncMessages({bool stream = false}) async {
    // Return empty message list for local testing
    return [];
  }

  @override
  Future<List<String>> syncContactBook(List<String> contacts) async {
    // Simulate all contacts are available for local testing
    return contacts;
  }

  @override
  Future<AssetPreSignedUrlResponse> getUploadUrl(
    String ext,
    String category,
  ) async {
    // Return mock upload URL
    return AssetPreSignedUrlResponse.fromJson({
      "status": true,
      "uploadUrl": "https://mock-storage.example.com/upload",
      "downloadUrl": "https://mock-storage.example.com/download/mock-file.$ext",
      "assetId": "mock_asset_${DateTime.now().millisecondsSinceEpoch}",
    });
  }

  // Utility method to simulate receiving messages for testing
  void simulateIncomingMessage(RemoteMessage message) {
    _eventController.add(message);
  }

  // Clean up resources
  void dispose() {
    _eventController.close();
  }
}

/// Mock TokenManager for testing
class MockTokenManager implements TokenManager {
  Token? _token;

  @override
  Future<Token?> fetchActiveToken() async {
    return _token;
  }

  @override
  Future<Token?> fetchToken(String userId) async {
    return _token?.userId == userId ? _token : null;
  }

  @override
  Future<void> setToken(Token token) async {
    _token = token;
  }
}