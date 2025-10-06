// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:vartalap_messaging/client/client.dart';
import 'package:vartalap_messaging/core/api/response.dart';
import 'package:vartalap_messaging/core/models/channel.dart';
import 'package:vartalap_messaging/core/models/credentail.dart';
import 'package:vartalap_messaging/core/models/event.dart';

/// MockVartalapChatClient for offline-first local development with persistence
///
/// This mock client bypasses all server communication and provides
/// realistic fake responses for authentication and API calls. Perfect for:
/// - Local development without server dependencies
/// - UI/UX development and testing
/// - Offline functionality testing
/// - Fast iteration cycles
///
/// Features:
/// - **Persists data across app restarts** (channels, profiles, messages)
/// - Stores state in local JSON file
/// - Auto-saves on data changes
/// - Hot reload preserves mock data
///
/// Enable mock mode by running:
/// ```
/// flutter run --dart-define MOCK_MODE=true
/// ```
class MockVartalapChatClient extends VartalapChatClient {
  final String mockUserId;
  final StreamController<RemoteMessage> _eventController =
      StreamController<RemoteMessage>.broadcast();

  // Mock data storage
  final List<MockChannel> _channels = [];
  final Map<String, MockProfile> _profiles = {};
  final Map<String, List<Map<String, dynamic>>> _channelMessages = {};

  // Persistence
  static const String _stateFileName = 'mock_vartalap_state.json';
  bool _isInitialized = false;

  MockVartalapChatClient({
    this.mockUserId = "+1234567890",
    required super.tokenManager,
  }) : super(
          apiKey: "mock_api_key",
          apiBaseUrl: "http://localhost:3000",
          wsUrl: "ws://localhost:3000",
        );

  /// Initialize mock data - loads from persistence or creates default
  Future<void> initialize() async {
    if (_isInitialized) return;

    final loaded = await _loadState();
    if (!loaded) {
      _initializeDefaultMockData();
      await _saveState();
    }

    _isInitialized = true;
  }

  /// Get the state file path
  Future<File> _getStateFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_stateFileName');
  }

  /// Load state from local file
  Future<bool> _loadState() async {
    try {
      final file = await _getStateFile();
      if (!await file.exists()) {
        return false;
      }

      final jsonString = await file.readAsString();
      final Map<String, dynamic> state = jsonDecode(jsonString);

      // Load profiles
      final profilesMap = state['profiles'] as Map<String, dynamic>?;
      if (profilesMap != null) {
        profilesMap.forEach((key, value) {
          _profiles[key] = MockProfile.fromJson(value as Map<String, dynamic>);
        });
      }

      // Load channels
      final channelsList = state['channels'] as List<dynamic>?;
      if (channelsList != null) {
        for (var channelJson in channelsList) {
          _channels
              .add(MockChannel.fromJson(channelJson as Map<String, dynamic>));
        }
      }

      // Load messages
      final messagesMap = state['messages'] as Map<String, dynamic>?;
      if (messagesMap != null) {
        messagesMap.forEach((channelId, messages) {
          _channelMessages[channelId] =
              List<Map<String, dynamic>>.from(messages as List);
        });
      }

      print(
          '[MOCK] Loaded persisted state: ${_channels.length} channels, ${_profiles.length} profiles');
      return true;
    } catch (e) {
      print('[MOCK] Error loading state: $e');
      return false;
    }
  }

  /// Save state to local file
  Future<void> _saveState() async {
    try {
      final file = await _getStateFile();

      final state = {
        'version': '1.0',
        'mockUserId': mockUserId,
        'profiles':
            _profiles.map((key, value) => MapEntry(key, value.toJson())),
        'channels': _channels.map((c) => c.toJson()).toList(),
        'messages': _channelMessages,
        'lastUpdated': DateTime.now().toIso8601String(),
      };

      await file.writeAsString(jsonEncode(state));
      print(
          '[MOCK] Saved state: ${_channels.length} channels, ${_profiles.length} profiles');
    } catch (e) {
      print('[MOCK] Error saving state: $e');
    }
  }

  /// Initialize default mock data for first-time users
  void _initializeDefaultMockData() {
    // Create mock user profiles
    _profiles[mockUserId] = MockProfile(
      userId: mockUserId,
      name: "You (Test User)",
      email: "testuser@vartalap.dev",
    );

    // Add sample contacts
    final contacts = [
      MockProfile(
        userId: "+9876543210",
        name: "Alice Johnson",
        email: "alice@example.com",
      ),
      MockProfile(
        userId: "+1122334455",
        name: "Bob Smith",
        email: "bob@example.com",
      ),
      MockProfile(
        userId: "+5566778899",
        name: "Charlie Brown",
        email: "charlie@example.com",
      ),
      MockProfile(
        userId: "+9988776655",
        name: "Diana Prince",
        email: "diana@example.com",
      ),
      MockProfile(
        userId: "+4433221100",
        name: "Eve Martinez",
        email: "eve@example.com",
      ),
    ];

    for (var contact in contacts) {
      _profiles[contact.userId] = contact;
    }

    // Create sample 1-1 channels
    for (var i = 0; i < contacts.length && i < 3; i++) {
      final contact = contacts[i];
      final channelId = "channel_1on1_$i";
      _channels.add(MockChannel(
        id: channelId,
        type: 'individual',
        name: contact.name,
        members: [mockUserId, contact.userId],
        createdBy: mockUserId,
        createdAt: DateTime.now().subtract(Duration(days: 7 - i)),
      ));

      // Add some sample messages for each channel
      _channelMessages[channelId] = _generateSampleMessages(
        channelId: channelId,
        count: 5 + i * 2,
      );
    }

    // Create sample group channel
    final groupMembers = [mockUserId, ...contacts.take(3).map((c) => c.userId)];
    final groupChannelId = "channel_group_1";
    _channels.add(MockChannel(
      id: groupChannelId,
      type: 'group',
      name: "Team Vartalap",
      members: groupMembers.toList(),
      createdBy: mockUserId,
      createdAt: DateTime.now().subtract(const Duration(days: 14)),
    ));

    _channelMessages[groupChannelId] = _generateSampleMessages(
      channelId: groupChannelId,
      count: 10,
    );

    print('[MOCK] Initialized default mock data');
  }

  /// Generate sample messages for a channel
  List<Map<String, dynamic>> _generateSampleMessages({
    required String channelId,
    required int count,
  }) {
    final messages = <Map<String, dynamic>>[];
    final now = DateTime.now();

    final sampleTexts = [
      "Hey there! How are you?",
      "I'm doing great, thanks!",
      "Did you see the latest update?",
      "Yes! It looks amazing!",
      "We should meet up soon.",
      "Absolutely! How about next week?",
      "Sounds perfect!",
      "Great! I'll send you the details.",
      "Looking forward to it!",
      "Have a great day!",
    ];

    for (var i = 0; i < count; i++) {
      final text = sampleTexts[i % sampleTexts.length];
      final timestamp =
          now.subtract(Duration(hours: count - i, minutes: i * 5));

      messages.add({
        "id": "msg_${channelId}_$i",
        "channelId": channelId,
        "text": text,
        "timestamp": timestamp.toIso8601String(),
      });
    }

    return messages;
  }

  @override
  Stream<RemoteMessage> get eventStream => _eventController.stream;

  @override
  Future<String?> getLoggedInUser() async {
    await Future.delayed(const Duration(milliseconds: 100));
    // Delegate to parent class which checks token manager
    // This ensures logout works correctly in mock mode
    return await super.getLoggedInUser();
  }

  @override
  Future<LoginResponse> login(Credential creds) async {
    await initialize(); // Ensure data is loaded
    await Future.delayed(const Duration(milliseconds: 300));

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
    await Future.delayed(const Duration(milliseconds: 200));

    final profile = _profiles[userId] ??
        MockProfile(
          userId: userId,
          name: "Unknown User",
          email: "unknown@example.com",
        );

    return ProfileResponse.fromJson({
      "name": profile.name,
      "username": profile.userId,
      "email": profile.email,
      "image": profile.imageUrl,
    });
  }

  @override
  Future<CreateChannelResponse> createChannel(ChannelPayload channel) async {
    await Future.delayed(const Duration(milliseconds: 300));

    final channelId = "mock_channel_${DateTime.now().millisecondsSinceEpoch}";

    _channels.add(MockChannel(
      id: channelId,
      type: channel.type,
      name: channel.name,
      members: channel.members,
      createdBy: mockUserId,
      createdAt: DateTime.now(),
    ));

    // Save state after creating channel
    await _saveState();

    return CreateChannelResponse.fromJson({
      "channelId": channelId,
    });
  }

  @override
  Future<ChannelsResponse> queryChannels() async {
    await Future.delayed(const Duration(milliseconds: 250));

    final channelsJson = _channels
        .map((c) => {
              "id": c.id,
              "name": c.name,
              "type": c.type,
              "createdBy": c.createdBy,
              "createdAt": c.createdAt.toIso8601String(),
              "members": c.members,
            })
        .toList();

    return ChannelsResponse.fromJson(channelsJson);
  }

  @override
  Future<ChannelResponse> getChannelInfo(String channelId) async {
    await Future.delayed(const Duration(milliseconds: 150));

    final channel = _channels.firstWhere(
      (c) => c.id == channelId,
      orElse: () => MockChannel(
        id: channelId,
        type: 'individual',
        name: "Mock Channel",
        members: [mockUserId],
        createdBy: mockUserId,
        createdAt: DateTime.now(),
      ),
    );

    return ChannelResponse.fromJson({
      "status": true,
      "channel": {
        "id": channel.id,
        "name": channel.name,
        "type": channel.type,
        "createdBy": channel.createdBy,
        "createdAt": channel.createdAt.toIso8601String(),
        "members": channel.members,
      }
    });
  }

  @override
  Future<void> addChannelMembers(
      String channelId, List<String> memberIds) async {
    await Future.delayed(const Duration(milliseconds: 200));

    final index = _channels.indexWhere((c) => c.id == channelId);
    if (index != -1) {
      final channel = _channels[index];
      final updatedMembers = {...channel.members, ...memberIds}.toList();
      _channels[index] = MockChannel(
        id: channel.id,
        type: channel.type,
        name: channel.name,
        members: updatedMembers,
        createdBy: channel.createdBy,
        createdAt: channel.createdAt,
      );

      await _saveState();
    }
  }

  @override
  Future<void> removeChannelMember(String channelId, String member) async {
    await Future.delayed(const Duration(milliseconds: 200));

    final index = _channels.indexWhere((c) => c.id == channelId);
    if (index != -1) {
      final channel = _channels[index];
      final updatedMembers = channel.members.where((m) => m != member).toList();
      _channels[index] = MockChannel(
        id: channel.id,
        type: channel.type,
        name: channel.name,
        members: updatedMembers,
        createdBy: channel.createdBy,
        createdAt: channel.createdAt,
      );

      await _saveState();
    }
  }

  @override
  Future<void> sendMessage(
    List<RemoteMessage> messages, {
    bool sync = false,
    bool ack = true,
  }) async {
    await Future.delayed(const Duration(milliseconds: 100));

    // Store messages
    for (var message in messages) {
      final channelId = message.head.to;
      _channelMessages.putIfAbsent(channelId, () => []);
      _channelMessages[channelId]!.add(message.toJson());
    }

    // Save state after sending messages
    await _saveState();

    if (ack) {
      for (var message in messages) {
        final ackMessage = RemoteMessage.fromJson({
          ...message.toJson(),
          "meta": {
            ...message.meta.raw,
            "status": "sent",
          },
        });
        _eventController.add(ackMessage);
      }
    }
  }

  @override
  Future<List<RemoteMessage>> syncMessages({bool stream = false}) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return [];
  }

  @override
  Future<List<String>> syncContactBook(List<String> contacts) async {
    await Future.delayed(const Duration(milliseconds: 250));
    return contacts;
  }

  @override
  Future<AssetPreSignedUrlResponse> getUploadUrl(
    String ext,
    String category,
  ) async {
    await Future.delayed(const Duration(milliseconds: 200));

    return AssetPreSignedUrlResponse.fromJson({
      "status": true,
      "uploadUrl": "https://mock-storage.example.com/upload",
      "downloadUrl": "https://mock-storage.example.com/download/mock-file.$ext",
      "assetId": "mock_asset_${DateTime.now().millisecondsSinceEpoch}",
    });
  }

  @override
  Future<AssetPreSignedUrlResponse> getDownloadUrl(String assetId) async {
    await Future.delayed(const Duration(milliseconds: 150));

    return AssetPreSignedUrlResponse.fromJson({
      "status": true,
      "downloadUrl": "https://mock-storage.example.com/download/$assetId",
      "assetId": assetId,
    });
  }

  @override
  Future<void> markAssetAsUploaded(String assetId) async {
    await Future.delayed(const Duration(milliseconds: 100));
    // No-op for mock
  }

  @override
  Future<void> close() async {
    await _saveState(); // Save before closing
    await _eventController.close();
  }

  /// Utility method to simulate receiving messages for testing
  void simulateIncomingMessage(RemoteMessage message) {
    _eventController.add(message);
  }

  /// Clear all persisted mock data (useful for testing)
  Future<void> clearPersistedData() async {
    try {
      final file = await _getStateFile();
      if (await file.exists()) {
        await file.delete();
        print('[MOCK] Cleared persisted data');
      }

      // Clear in-memory data
      _channels.clear();
      _profiles.clear();
      _channelMessages.clear();
      _isInitialized = false;

      // Reinitialize with default data
      _initializeDefaultMockData();
      await _saveState();
    } catch (e) {
      print('[MOCK] Error clearing persisted data: $e');
    }
  }
}

/// Helper classes for mock data
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
