import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:taskq/storage/database.dart';
import 'package:taskq/taskq.dart';
import 'package:vartalap_messaging/vartalap_messaging.dart'
    show VartalapChatClient, TokenManager, Credential, LoginResponse, Token;
import 'package:vartalap_messaging_flutter/client/chat.dart';
import 'package:vartalap_messaging_flutter/client/secure_token_manager.dart';
import 'package:vartalap_messaging_flutter/db/chat_db.dart';
import 'package:vartalap_messaging_flutter/events/events.dart';
import 'package:vartalap_messaging_flutter/models/models.dart';

/// Custom exception for VartalapChatClientFlutter initialization failures
///
/// Provides detailed error information including the original error for debugging
class VartalapInitializationException implements Exception {
  final String message;
  final Object? originalError;
  final StackTrace? stackTrace;

  const VartalapInitializationException(
    this.message, {
    this.originalError,
    this.stackTrace,
  });

  @override
  String toString() {
    if (originalError != null) {
      return 'VartalapInitializationException: $message\nCaused by: $originalError';
    }
    return 'VartalapInitializationException: $message';
  }
}

/// VartalapChatClientFlutter - Local-First Core Client
///
/// ARCHITECTURE PRINCIPLES:
/// 1. LOCAL-FIRST: All operations work locally first, sync happens in background
/// 2. DAO PATTERN: All database operations are delegated to DAO classes
/// 3. NO HARDCODED DATA: UI layer provides all external data (contacts, etc.)
/// 4. CLEAN INTERFACES: Methods don't expose implementation details
///
/// LAYER RESPONSIBILITIES:
/// - This Client Layer: Business logic, orchestration, initialization
/// - DAO Layer: All database CRUD operations
/// - UI Layer: User interactions, device contacts, permissions
///
/// DATABASE OPERATIONS FLOW:
/// UI -> VartalapChatClientFlutter -> ChannelDao/ChatDao -> Database
///
/// SYNC STRATEGY:
/// - Optimistic updates: Local changes applied immediately
/// - Background sync: Tasks scheduled for server synchronization
/// - Conflict resolution: Server state takes precedence (future implementation)
///
/// IMPORTANT: DO NOT add direct database operations to this class.
/// All database operations MUST go through DAO classes for consistency.
class VartalapChatClientFlutter {
  late VartalapChatClient client;
  late TaskScheduler scheduler;
  late VartalapTaskFactory factory;
  late ChatDatabase _db;
  late TokenManager _tokenManager;
  bool _isInitialized = false;

  VartalapChatClientFlutter({
    required String apiKey,
    String? apiBaseUrl,
    String? wsUrl,
    VartalapChatClient? client,
  }) {
    // Create token manager that will be shared
    _tokenManager = SecureStorageTokenManager();

    this.client = client ??
        VartalapChatClient(
          apiKey: apiKey,
          apiBaseUrl: apiBaseUrl,
          wsUrl: wsUrl,
          tokenManager: _tokenManager,
        );
  }

  /// Initializes the VartalapChatClientFlutter with robust error handling
  ///
  /// This method performs the following initialization steps:
  /// 1. Validates user authentication status
  /// 2. Initializes the local database connection
  /// 3. Sets up the task factory and scheduler for background operations
  /// 4. Establishes event stream handling
  ///
  /// This method is idempotent - calling it multiple times is safe and will
  /// only initialize once.
  ///
  /// Throws [VartalapInitializationException] if initialization fails
  Future<void> init() async {
    // Skip if already initialized
    if (_isInitialized) {
      debugPrint('[CLIENT] Already initialized, skipping');
      return;
    }

    try {
      // Step 1: Validate user authentication
      final userId = await _validateUserAuthentication();

      // Step 2: Initialize database connection
      await _initializeDatabase(userId);

      // Step 3: Set up task management system
      await _initializeTaskSystem();

      // Step 4: Set up event stream handling
      await _initializeEventStreaming();

      _isInitialized = true;
    } catch (e) {
      if (e is VartalapInitializationException) {
        rethrow;
      }
      // Wrap unexpected errors with context
      throw VartalapInitializationException(
        'Unexpected error during initialization: ${e.toString()}',
        originalError: e,
      );
    }
  }

  /// Validates that a user is logged in and returns the user ID
  Future<String> _validateUserAuthentication() async {
    try {
      final userId = await client.getLoggedInUser();
      if (userId == null || userId.isEmpty) {
        throw const VartalapInitializationException(
          'Cannot initialize VartalapChatClientFlutter: No user is currently logged in. '
          'Please log in before calling init().',
        );
      }
      return userId;
    } catch (e) {
      if (e is VartalapInitializationException) {
        rethrow;
      }
      throw VartalapInitializationException(
        'Failed to verify user authentication status: ${e.toString()}',
        originalError: e,
      );
    }
  }

  /// Initializes the local database connection
  Future<void> _initializeDatabase(String userId) async {
    try {
      _db = ChatDatabase(userId: userId);
      // Database will open automatically on first query (driftDatabase uses DatabaseConnection.delayed)
    } catch (e) {
      throw VartalapInitializationException(
        'Failed to initialize local database for user $userId: ${e.toString()}',
        originalError: e,
      );
    }
  }

  /// Sets up the task factory and scheduler for background operations
  Future<void> _initializeTaskSystem() async {
    try {
      factory = VartalapTaskFactory(client, _db);

      final taskDb = TaskQDatabase.withQueryExectutor(_db.executor);
      scheduler = TaskScheduler(factory, db: taskDb);
    } catch (e) {
      if (e is VartalapInitializationException) {
        rethrow;
      }
      throw const VartalapInitializationException(
        'Failed to initialize task management system. This may be due to database connection issues or task factory configuration problems.',
      );
    }
  }

  /// Sets up event stream handling with error recovery
  Future<void> _initializeEventStreaming() async {
    try {
      // Set up event stream with error handling
      client.eventStream.listen(
        (msg) {
          // Process events - implementation can be expanded here
        },
        onError: (error) {
          // Log event stream errors but don't fail initialization
          // This allows the client to continue functioning even if WebSocket has issues
          debugPrint('Event stream error: $error');
        },
        onDone: () {
          debugPrint('Event stream closed - will attempt to reconnect');
        },
      );
    } catch (e) {
      throw VartalapInitializationException(
        'Failed to initialize event streaming: ${e.toString()}',
        originalError: e,
      );
    }
  }

  /// Get the logged-in user ID
  ///
  /// This method works offline by checking the stored token.
  /// Returns the userId if a valid token exists, null otherwise.
  ///
  /// NOTE: This does NOT require database initialization and can be called
  /// before init() to check authentication status.
  Future<String?> getLoggedInUser() async {
    // Directly check token manager (offline-first)
    final token = await _tokenManager.fetchActiveToken();
    return token?.userId;
  }

  /// Login with credentials
  ///
  /// This method handles the complete login flow with client-side token management:
  /// 1. Calls the server client's login method to authenticate
  /// 2. Manages token storage on the client side using the token manager
  ///
  /// This approach keeps VartalapChatClient as a pure server client without
  /// client-side logic, while VartalapChatClientFlutter handles all client-side
  /// concerns including token persistence.
  ///
  /// NOTE: After successful login, you must call init() to initialize the database
  /// and other components before using other methods.
  ///
  /// Returns: LoginResponse containing user details and access key
  Future<LoginResponse> login(Credential creds) async {
    // Call the pure server client login (no client-side logic)
    final resp = await client.login(creds);

    // Handle token management on client side for consistency
    final token = Token(userId: resp.userId, accesskey: resp.accessKey);
    await _tokenManager.setToken(token);

    return resp;
  }

  /// Get the logged-in user profile
  ///
  /// This method works offline-first:
  /// 1. Retrieves the cached profile from the local database
  /// 2. Falls back to fetching from server if not cached (requires network)
  ///
  /// IMPORTANT: Requires database to be initialized via init() first.
  /// Returns null if no user is logged in or profile not found.
  Future<Profile?> getLoggedInUserProfile() async {
    // Use this class's getLoggedInUser (checks token manager directly)
    final userId = await getLoggedInUser();
    if (userId == null) return null;

    // Try to get profile from local database first (offline-first)
    final cachedProfile = await _db.userProfileDao.getProfile(userId);
    if (cachedProfile != null) {
      return cachedProfile;
    }

    // If not in database, fetch from server and cache it
    try {
      final profile = await client.fetchProfile(userId);
      final userProfile = Profile(
        userId: profile.userId,
        name: profile.name,
        email: profile.email ?? '',
        image: profile.image ?? '',
      );

      // Cache the profile for offline access
      await _db.userProfileDao.saveProfile(userProfile);

      return userProfile;
    } catch (e) {
      // If we can't fetch from server and don't have cache, return null
      debugPrint('Failed to fetch user profile: $e');
      return null;
    }
  }

  /// Save the user profile to local database
  ///
  /// This should be called after successful login to enable offline authentication
  Future<void> saveUserProfile(Profile profile) async {
    await _db.userProfileDao.saveProfile(profile);
  }

  Selectable<ChatPreview> getChatPreviews({
    ChannelFilter? filter,
  }) {
    return _db.chatDao.getChatPreviews(filter: filter);
  }

  /// Watch all channels with real-time updates
  ///
  /// Returns a reactive stream of all channels with optional filtering.
  /// The stream automatically updates when channels are created, updated, or deleted.
  ///
  /// Usage:
  /// ```dart
  /// client.watchAllChannels().listen((channels) {
  ///   // UI updates automatically when channels change
  /// });
  /// ```
  ///
  /// Parameters:
  /// - [filter]: Optional filter to apply to channels (type, name, memberIds)
  ///
  /// Returns: Stream&lt;List&lt;ChannelModel&gt;&gt; - Reactive stream for UI binding
  Stream<List<ChannelModel>> watchAllChannels({
    ChannelFilter? filter,
  }) {
    return _db.channelDao.getChannels(filter: filter).watch();
  }

  /// Watch chat previews with real-time updates
  ///
  /// Returns a reactive stream of chat previews including last message and unread counts.
  /// The stream automatically updates when messages are sent, received, or marked as read.
  ///
  /// Usage:
  /// ```dart
  /// client.watchChatPreviews().listen((previews) {
  ///   // UI updates automatically when chat state changes
  /// });
  /// ```
  ///
  /// Parameters:
  /// - [filter]: Optional filter to apply to channels
  ///
  /// Returns: Stream&lt;List&lt;ChatPreview&gt;&gt; - Reactive stream for UI binding
  Stream<List<ChatPreview>> watchChatPreviews({
    ChannelFilter? filter,
  }) {
    return _db.chatDao.getChatPreviews(filter: filter).watch();
  }

  /// Watch unread message counts for all channels
  ///
  /// Returns a reactive stream of unread counts per channel.
  /// The stream automatically updates when messages are marked as read or new messages arrive.
  ///
  /// Usage:
  /// ```dart
  /// client.watchUnreadCounts().listen((unreadCounts) {
  ///   final channelUnreadCount = unreadCounts[channelId] ?? 0;
  ///   // Update UI badges with unread counts
  /// });
  /// ```
  ///
  /// Returns: Stream&lt;Map&lt;int, int&gt;&gt; - Map of channelId to unreadCount
  Stream<Map<int, int>> watchUnreadCounts() {
    // Use chat previews stream to extract unread counts efficiently
    return _db.chatDao.getChatPreviews().watch().map((previews) {
      return Map.fromEntries(
        previews.map(
            (preview) => MapEntry(preview.channel.id, preview.unreadCount)),
      );
    });
  }

  /// Watch contacts with real-time updates
  ///
  /// Returns a reactive stream of all contacts with optional filtering.
  /// The stream automatically updates when contacts are added, updated, or synchronized.
  ///
  /// Usage:
  /// ```dart
  /// client.watchContacts().listen((contacts) {
  ///   // UI updates automatically when contacts change
  /// });
  /// ```
  ///
  /// Parameters:
  /// - [filter]: Optional filter to apply to contacts (name, phone, status, username)
  ///
  /// Returns: Stream&lt;List&lt;Contact&gt;&gt; - Reactive stream for UI binding
  Stream<List<Contact>> watchContacts({
    ContactFilter? filter,
  }) {
    return _db.channelDao.getContacts(filter: filter).watch();
  }

  Future<ChatClient> chat({
    required ChannelModel channel,
    required Contact currentUser,
  }) async {
    final chatClient = ChatClient(
      channel: channel,
      client: this,
      chatDao: _db.chatDao,
      currentUser: currentUser,
    );
    await chatClient.init();
    return chatClient;
  }

  Selectable<ChannelModel> getChannels({
    ChannelFilter? filter,
  }) {
    return _db.channelDao.getChannels(filter: filter);
  }

  Future<ChannelModel> createChannel(
      ChannelModel channel, List<Member> members) async {
    return await _db.channelDao.createChannel(channel, members);
  }

  Future<void> updateChannel(ChannelModel channel) async {
    return await _db.channelDao.updateChannel(channel);
  }

  Future<void> deleteChannel(int channelId) async {
    return await _db.channelDao.deleteChannel(channelId);
  }

  Selectable<Contact> getContacts({
    ContactFilter? filter,
  }) {
    return _db.channelDao.getContacts(filter: filter);
  }

  Future<void> syncChannels() async {
    return;
    // final channels = await client.queryChannels();
    // await _db.transaction(() async {
    //   await _db.delete(_db.channels).go();
    //   await _db.batch((batch) {
    //     batch.insertAll(
    //       _db.channels,
    //       channels.items
    //           .map((channel) => ChannelsCompanion.insert(
    //                 type: ChannelType.values.byName(channel.type),
    //                 config: Value(Map<String, dynamic>.from({})),
    //                 extraData: Value({
    //                   "name": channel.name,
    //                   "image": channel.profilePic,
    //                 }),
    //               ))
    //           .toList(),
    //     );
    //   });
    // });
  }

  Future<void> syncContacts(List<Contact> contacts) async {
    return await _db.channelDao.syncContacts(contacts);
  }

  Future<void> addContacts(List<Contact> contacts) async {
    return await _db.channelDao.addContacts(contacts);
  }

  Future<void> syncMessages() async {
    await _db.transaction(() async {
      // SyncMessageTask task =
      //     factory.create(SyncMessageTask.name) as SyncMessageTask;
      // await scheduler.schedule(task);
    });
  }

  /// Logout and clear all data
  ///
  /// This method performs a complete logout by:
  /// 1. Clearing the authentication token from secure storage
  /// 2. Closing the database connection
  /// 3. Closing network connections
  /// 4. Resetting the initialization state
  ///
  /// Note: This does NOT delete the database file. The database is user-specific
  /// and will be reused if the same user logs in again.
  Future<void> logout() async {
    try {
      // Clear the authentication token directly from token manager
      await _tokenManager.clearToken();
      debugPrint('[CLIENT] Token cleared');

      // Close database connection if initialized
      if (_isInitialized) {
        await _db.close();
        debugPrint('[CLIENT] Database connection closed');
      }

      // Close network connections
      await client.close();

      // Reset initialization state so a new login requires re-init
      _isInitialized = false;

      debugPrint('[CLIENT] Logout completed successfully');
    } catch (e) {
      debugPrint('[CLIENT] Error during logout: $e');
      // Still reset initialization state even if there was an error
      _isInitialized = false;
      rethrow;
    }
  }
}
