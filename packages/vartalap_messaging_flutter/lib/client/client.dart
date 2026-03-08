import 'dart:async';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:taskq/taskq.dart';
import 'package:vartalap_messaging/vartalap_messaging.dart' as messaging;
import 'package:vartalap_messaging/vartalap_messaging.dart'
    show VartalapChatClient, TokenManager, Credential, LoginResponse, Token;
import 'package:vartalap_messaging_flutter/client/chat.dart';
import 'package:vartalap_messaging_flutter/client/secure_token_manager.dart';
import 'package:vartalap_messaging_flutter/db/chat_db.dart';
import 'package:vartalap_messaging_flutter/events/events.dart';
import 'package:vartalap_messaging_flutter/models/models.dart';
import 'package:vartalap_messaging_flutter/auth/otp_provider.dart';
import 'package:vartalap_messaging_flutter/repository/auth_repository.dart';
import 'package:vartalap_messaging_flutter/taskq/chat_task_store.dart';

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
  late AuthRepository auth; // Auth Repository
  bool _isInitialized = false;
  final bool _inMemory;
  StreamSubscription? _eventStreamSubscription;
  final void Function()? onBackgroundTaskRequested;

  ChatDatabase get db => _db;

  // Internal event bus for ephemeral events (typing, status, etc.)
  final _eventBus = StreamController<messaging.RemoteMessage>.broadcast();

  VartalapChatClientFlutter({
    required String apiKey,
    String? apiBaseUrl,
    String? wsUrl,
    VartalapChatClient? client,
    TokenManager? tokenManager,
    bool inMemory = false,
    this.onBackgroundTaskRequested,
  }) : _inMemory = inMemory {
    // Priority: 1. Constructor param, 2. Provided client's manager, 3. Default secure storage
    _tokenManager =
        tokenManager ?? client?.tokenManager ?? SecureStorageTokenManager();

    this.client = client ??
        VartalapChatClient(
          apiKey: apiKey,
          apiBaseUrl: apiBaseUrl,
          wsUrl: wsUrl,
          tokenManager: _tokenManager,
        );
  }

  /// Initialize Auth Repository
  void initAuth(IOTPProvider otpProvider) {
    auth = AuthRepository(this, otpProvider);
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
      _db = ChatDatabase(userId: userId, inMemory: _inMemory);
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

      final taskStore = ChatTaskStore(_db);
      scheduler = TaskScheduler(factory, store: taskStore);
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
      _eventStreamSubscription = client.eventStream.listen(
        (msg) {
          _handleIncomingEvent(msg);
        },
        onError: (error) {
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

  /// Process incoming events from the server
  /// Translates backend RemoteMessage into local actions
  void _handleIncomingEvent(messaging.RemoteMessage msg) {
    debugPrint(
        '[EVENT] Received event: ${msg.head.category} (ephemeral: ${msg.head.ephemeral})');

    if (msg.head.ephemeral) {
      if (msg.head.category == 'typing') {
        _handleTypingEvent(msg);
      } else {
        // Broadcast other ephemeral events to the bus
        _eventBus.add(msg);
      }
    } else {
      if (msg.head.category == 'message') {
        _handleNewMessage(msg);
      } else if (msg.head.category == 'ack') {
        _handleAckEvent(msg);
      }
    }
  }

  /// Handle persistent messages from other users
  Future<void> _handleNewMessage(messaging.RemoteMessage remoteMsg) async {
    try {
      // 1. Resolve local channel ID
      final myUid = await getLoggedInUser();
      debugPrint(
          '[EVENT] Handling new message for $myUid, from ${remoteMsg.head.from}, to ${remoteMsg.head.to}');

      ChannelModel? channelRow;
      if (remoteMsg.head.to == myUid) {
        debugPrint('[EVENT] 1-1 message detected');
        // 1-1 message: find channel where members contain 'from'
        channelRow = await (_db.select(_db.channels).join([
          innerJoin(
              _db.members, _db.members.channelId.equalsExp(_db.channels.id)),
          innerJoin(
              _db.contacts, _db.contacts.id.equalsExp(_db.members.memberId)),
        ])
              ..where(_db.contacts.uid.equals(remoteMsg.head.from) &
                  _db.channels.type
                      .equals(messaging.ChannelType.individual.name)))
            .map((row) => row.readTable(_db.channels))
            .getSingleOrNull();
      } else {
        debugPrint('[EVENT] Group/Broadcast message detected');
        // Group message: 'to' is the Group CID
        channelRow = await (_db.select(_db.channels)
              ..where((tbl) => tbl.cid.equals(remoteMsg.head.to)))
            .getSingleOrNull();
      }

      if (channelRow == null) {
        debugPrint('[EVENT] Channel Row NOT found');
        if (remoteMsg.head.type == messaging.ChannelType.individual) {
          debugPrint(
              '[EVENT] 1-1 Channel not found, auto-creating for sender: ${remoteMsg.head.from}');
          // 1. Ensure sender contact exists (outside transaction so we can read it)
          final senderRow = await (_db.select(_db.contacts)
                ..where((tbl) => tbl.uid.equals(remoteMsg.head.from)))
              .getSingleOrNull();

          int contactId;
          String senderDisplayName;
          if (senderRow == null) {
            debugPrint('[EVENT] Sender contact NOT found, creating it');
            contactId =
                await _db.into(_db.contacts).insert(ContactsCompanion.insert(
                      uid: Value(remoteMsg.head.from),
                      username: Value(remoteMsg.head.from),
                      status: ContactStatus.active,
                    ));
            // Best name we have is the UID itself
            senderDisplayName = remoteMsg.head.from;
          } else {
            debugPrint('[EVENT] Sender contact found with ID: ${senderRow.id}');
            contactId = senderRow.id;
            senderDisplayName = senderRow.displayName;
          }

          // Prevent duplicates before transacting
          final existingMsg = await (_db.select(_db.messages)
                ..where((tbl) => tbl.rid.equals(remoteMsg.id)))
              .getSingleOrNull();
          if (existingMsg != null) return;

          // Create channel + member + message in one transaction
          debugPrint('[EVENT] Creating channel, member & message in transaction');
          await _db.transaction(() async {
            final newChannel = await _db
                .into(_db.channels)
                .insertReturning(ChannelsCompanion.insert(
                  type: messaging.ChannelType.individual,
                  cid: Value(remoteMsg.head.from),
                  extraData: Value({'name': senderDisplayName}),
                  config: Value(<String, dynamic>{}),
                ));

            await _db.into(_db.members).insert(MembersCompanion.insert(
                  channelId: newChannel.id,
                  memberId: contactId,
                ));

            await _db.into(_db.messages).insert(MessagesCompanion.insert(
                  rid: Value(remoteMsg.id),
                  type: remoteMsg.head.category == 'image'
                      ? MessageType.image
                      : MessageType.text,
                  state: MessageState.delivered,
                  payload: remoteMsg.body as Map<String, dynamic>,
                  channelId: newChannel.id,
                  senderId: contactId,
                  remoteCreatedAt: Value(DateTime.fromMillisecondsSinceEpoch(
                      remoteMsg.meta.createdAt)),
                  updatedAt: Value(DateTime.now()),
                ));
          });

          debugPrint('[EVENT] New message saved to local DB: ${remoteMsg.id}');
          return; // Early return — message was already inserted inside the transaction
        } else {
          debugPrint(
              '[EVENT] Channel not found for incoming message, ignoring');
          return;
        }
      } else {
        debugPrint('[EVENT] Found channel with ID: ${channelRow.id}');
      }

      // 2. Resolve local sender ID (channel already existed)
      final senderRow = await (_db.select(_db.contacts)
            ..where((tbl) => tbl.uid.equals(remoteMsg.head.from)))
          .getSingleOrNull();

      int localSenderId = senderRow!.id;

      // 3. Prevent duplicates
      final existingMsg = await (_db.select(_db.messages)
            ..where((tbl) => tbl.rid.equals(remoteMsg.id)))
          .getSingleOrNull();
      if (existingMsg != null) return;

      // 4. Insert to DB - triggers reactive UI
      await _db.into(_db.messages).insert(MessagesCompanion.insert(
            rid: Value(remoteMsg.id),
            type: remoteMsg.head.category == 'image'
                ? MessageType.image
                : MessageType.text,
            state: MessageState.delivered,
            payload: remoteMsg.body as Map<String, dynamic>,
            channelId: channelRow.id,
            senderId: localSenderId,
            remoteCreatedAt: Value(
                DateTime.fromMillisecondsSinceEpoch(remoteMsg.meta.createdAt)),
            updatedAt: Value(DateTime.now()),
          ));

      debugPrint('[EVENT] New message saved to local DB: ${remoteMsg.id}');
    } catch (e) {
      debugPrint('[EVENT] Error handling incoming message: $e');
    }
  }

  /// Handle message acknowledgments (delivery/read receipts)
  Future<void> _handleAckEvent(messaging.RemoteMessage ackMsg) async {
    try {
      final messageId = ackMsg.id; // Correlation ID
      final status = ackMsg.meta.raw['status'] as String?;

      MessageState newState;
      switch (status) {
        case 'delivered':
          newState = MessageState.delivered;
          break;
        case 'read':
          newState = MessageState.read;
          break;
        case 'sent':
          newState = MessageState.sent;
          break;
        default:
          newState = MessageState.sent;
      }

      // Update local message state by RID
      await (_db.update(_db.messages)
            ..where((tbl) => tbl.rid.equals(messageId)))
          .write(MessagesCompanion(
        state: Value(newState),
        updatedAt: Value(DateTime.now()),
      ));

      debugPrint('[EVENT] Updated message $messageId status to $newState');
    } catch (e) {
      debugPrint('[EVENT] Error handling ack: $e');
    }
  }

  /// Handle typing indicators
  void _handleTypingEvent(messaging.RemoteMessage typingMsg) {
    // Just broadcast it to the bus
    _eventBus.add(typingMsg);
  }

  /// Getter for the ephemeral event bus
  Stream<messaging.RemoteMessage> get ephemeralEvents => _eventBus.stream;

  /// Watch global typing events
  /// Emits Map containing channelId and a boolean indicating if someone is typing
  Stream<Map<String, dynamic>> watchTypingEvents() {
    return _eventBus.stream
        .where((event) => event.head.category == 'typing')
        .map((event) {
      final from = event.head.from;
      final to = event.head.to; // This is the channel ID for groups
      
      final isTyping = event.body is Map
          ? event.body['typing'] as bool? ?? false
          : false;
          
      return {
        'from': from,
        'to': to,
        'typing': isTyping,
      };
    });
  }

  /// Dispose resources
  void dispose() {
    _eventStreamSubscription?.cancel();
    _eventBus.close();
  }

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
      // Ensure contact row exists for current user
      await _db.channelDao.ensureContact(cachedProfile);
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

      // Ensure contact row exists for current user
      await _db.channelDao.ensureContact(userProfile);

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
    required int currentUserId,
    ChannelFilter? filter,
  }) {
    return _db.chatDao
        .getChatPreviews(currentUserId: currentUserId, filter: filter);
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
  Stream<List<ChatPreview>> watchChatPreviews(
    int currentUserId, {
    ChannelFilter? filter,
  }) {
    return _db.chatDao
        .getChatPreviews(currentUserId: currentUserId, filter: filter)
        .watch();
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
  Stream<Map<int, int>> watchUnreadCounts(int currentUserId) {
    // Use chat previews stream to extract unread counts efficiently
    return _db.chatDao
        .getChatPreviews(currentUserId: currentUserId)
        .watch()
        .map((previews) {
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
    final localChannel = await _db.channelDao.createChannel(channel, members);

    // Schedule remote creation task
    final task = factory.create(
      CreateChannelTask.name,
      payload: localChannel.id,
    );
    await scheduler.schedule(task);

    return localChannel;
  }

  Future<void> updateChannel(ChannelModel channel) async {
    return await _db.channelDao.updateChannel(channel);
  }

  Future<void> setChannelPinned(int channelId, bool isPinned) async {
    return await _db.channelDao.updateChannelConfig(channelId, {'isPinned': isPinned});
  }

  Future<void> setChannelArchived(int channelId, bool isArchived) async {
    return await _db.channelDao.updateChannelConfig(channelId, {'isArchived': isArchived});
  }

  Future<void> deleteChannel(int channelId) async {
    return await _db.channelDao.deleteChannel(channelId);
  }

  Future<void> clearChat(int channelId) async {
    return await _db.chatDao.clearChannelMessages(channelId);
  }

  Selectable<Contact> getContacts({
    ContactFilter? filter,
  }) {
    return _db.channelDao.getContacts(filter: filter);
  }

  /// Trigger a background synchronization of messages and contacts
  Future<void> triggerSync() async {
    if (!_isInitialized) return;

    // 1. Sync Contacts
    final contactTask = factory.create(SyncContactsTask.name);
    await scheduler.schedule(contactTask);

    // 2. Sync Messages
    final messageTask = factory.create(SyncMessageTask.name);
    await scheduler.schedule(messageTask);

    debugPrint('[CLIENT] Sync tasks scheduled');
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

  /// Send an attachment (image, video, document)
  Future<void> sendAttachment({
    required int channelId,
    required String path,
    required String category,
    required Contact currentUser,
  }) async {
    final fileName = path.split('/').last;
    final extension = fileName.split('.').last;

    await _db.transaction(() async {
      // 1. Create Local Asset
      final assetId =
          await _db.into(_db.assests).insert(AssestsCompanion.insert(
                type: Value(category),
                path: Value(path),
                mimeType: Value(extension), // Simplified
                createdAt: Value(DateTime.now()),
                updatedAt: Value(DateTime.now()),
              ));

      // 2. Create local message
      final msgId =
          await _db.into(_db.messages).insert(MessagesCompanion.insert(
                type: category == 'image'
                    ? MessageType.image
                    : category == 'video'
                        ? MessageType.video
                        : MessageType.attachment,
                state: MessageState.pending,
                payload: {'name': fileName, 'path': path},
                channelId: channelId,
                senderId: currentUser.id,
                localCreatedAt: Value(DateTime.now()),
                updatedAt: Value(DateTime.now()),
              ));

      // 3. Link Asset to Message
      await _db.into(_db.messageAssets).insert(MessageAssetsCompanion.insert(
            messageId: msgId,
            assetId: assetId,
          ));

      // 4. Schedule Task
      final task = factory.create(
        SendMessageTask.name,
        payload: SendMessage(channelId, [msgId]),
      );
      await scheduler.schedule(task);

      // 5. Trigger true background execution via callback
      onBackgroundTaskRequested?.call();
    });
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
