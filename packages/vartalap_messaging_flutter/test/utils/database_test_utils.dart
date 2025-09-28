import 'package:vartalap_messaging_flutter/db/chat_db.dart';

/// Database testing utilities for local-first functionality testing
/// 
/// Provides helper methods to create and manage in-memory databases
/// for testing without server dependencies.
class DatabaseTestUtils {
  /// Creates a fresh in-memory database for testing
  /// 
  /// Each call returns a new, isolated database instance.
  /// Perfect for unit tests that need clean state.
  /// 
  /// Example:
  /// ```dart
  /// final db = DatabaseTestUtils.createInMemoryDatabase();
  /// // Use db for testing...
  /// await db.close(); // Clean up after test
  /// ```
  static ChatDatabase createInMemoryDatabase({
    String userId = "test_user",
  }) {
    return ChatDatabase(
      userId: userId,
      inMemory: true,
    );
  }

  /// Creates multiple isolated test databases
  /// 
  /// Useful for testing scenarios involving multiple users
  /// or concurrent database operations.
  /// 
  /// Example:
  /// ```dart
  /// final databases = DatabaseTestUtils.createMultipleTestDatabases(
  ///   userIds: ["user1", "user2", "user3"]
  /// );
  /// ```
  static List<ChatDatabase> createMultipleTestDatabases({
    required List<String> userIds,
  }) {
    return userIds
        .map((userId) => createInMemoryDatabase(userId: userId))
        .toList();
  }

  /// Closes all provided databases and cleans up resources
  /// 
  /// Should be called in test tearDown to prevent memory leaks.
  /// 
  /// Example:
  /// ```dart
  /// tearDown(() async {
  ///   await DatabaseTestUtils.closeAllDatabases(databases);
  /// });
  /// ```
  static Future<void> closeAllDatabases(List<ChatDatabase> databases) async {
    await Future.wait(databases.map((db) => db.close()));
  }

  /// Verifies that database is properly initialized and accessible
  /// 
  /// Runs basic connectivity tests to ensure the database is ready.
  /// Throws if database is not properly set up.
  /// 
  /// Example:
  /// ```dart
  /// final db = DatabaseTestUtils.createInMemoryDatabase();
  /// await DatabaseTestUtils.verifyDatabaseConnectivity(db);
  /// ```
  static Future<void> verifyDatabaseConnectivity(ChatDatabase db) async {
    // Ensure database is opened before running operations
    try {
      // This will ensure the database is properly initialized
      await db.customSelect('SELECT 1').getSingle();
    } catch (e) {
      // Database might need to be opened explicitly
      // The above query should trigger the opening process
      rethrow;
    }
  }

  /// Populates database with basic test data
  /// 
  /// Creates a minimal dataset for testing common scenarios:
  /// - Test contacts
  /// - Sample channels  
  /// - Basic messages
  /// 
  /// Returns the IDs of created test data for further testing.
  static Future<TestDataIds> populateWithTestData(
    ChatDatabase db, {
    String userId = "test_user",
  }) async {
    // This will be implemented when we create test data factories
    // For now, return empty IDs
    return TestDataIds(
      contactIds: [],
      channelIds: [],
      messageIds: [],
    );
  }
}

/// Container for test data IDs created during database population
class TestDataIds {
  final List<String> contactIds;
  final List<String> channelIds; 
  final List<int> messageIds;

  const TestDataIds({
    required this.contactIds,
    required this.channelIds,
    required this.messageIds,
  });
}

/// Test database configuration helper
/// 
/// Provides common database configurations for different test scenarios.
class TestDatabaseConfig {
  /// Configuration for unit tests - minimal setup
  static const unitTest = DatabaseTestConfig(
    userId: "unit_test_user",
    populateTestData: false,
    enableLogging: false,
  );

  /// Configuration for integration tests - more realistic setup
  static const integrationTest = DatabaseTestConfig(
    userId: "integration_test_user", 
    populateTestData: true,
    enableLogging: true,
  );

  /// Configuration for performance tests - large dataset
  static const performanceTest = DatabaseTestConfig(
    userId: "performance_test_user",
    populateTestData: true,
    enableLogging: false,
  );
}

/// Database test configuration
class DatabaseTestConfig {
  final String userId;
  final bool populateTestData;
  final bool enableLogging;

  const DatabaseTestConfig({
    required this.userId,
    required this.populateTestData,
    required this.enableLogging,
  });
}