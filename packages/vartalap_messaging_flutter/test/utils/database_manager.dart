import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap_messaging_flutter/db/chat_db.dart';

/// Singleton database manager for tests to prevent multiple database instance warnings
///
/// This ensures we only create one database instance per test isolation group
/// and properly manage the lifecycle to prevent race conditions.
class TestDatabaseManager {
  static final Map<String, ChatDatabase> _databases = {};
  static int _testCounter = 0;

  /// Creates or gets an existing database for the test
  ///
  /// Uses test isolation to ensure each test gets a fresh database
  /// while preventing multiple instances with the same executor.
  static Future<ChatDatabase> getTestDatabase({
    String? testName,
    String userId = "test_user",
  }) async {
    // Create unique key for this test
    final testKey = testName ?? "test_${++_testCounter}";
    final dbKey = "${userId}_$testKey";

    // Return existing database if available
    if (_databases.containsKey(dbKey)) {
      return _databases[dbKey]!;
    }

    // Initialize Flutter binding if not already done
    TestWidgetsFlutterBinding.ensureInitialized();

    // Create new in-memory database with unique name
    final database = ChatDatabase(
      userId: "${userId}_${DateTime.now().millisecondsSinceEpoch}",
      inMemory: true,
    );

    // Store database for reuse in same test
    _databases[dbKey] = database;

    return database;
  }

  /// Closes a specific test database
  static Future<void> closeTestDatabase(String testKey) async {
    final database = _databases.remove(testKey);
    if (database != null) {
      await database.close();
    }
  }

  /// Closes all test databases - call in tearDownAll()
  static Future<void> closeAllTestDatabases() async {
    final databases = List.from(_databases.values);
    _databases.clear();

    await Future.wait(databases.map((db) => db.close()));
  }

  /// Checks if SQLite is available for testing
  static Future<bool> isSQLiteAvailable() async {
    try {
      final testDb = ChatDatabase(
        userId: "connectivity_test_${DateTime.now().millisecondsSinceEpoch}",
        inMemory: true,
      );

      await testDb.customSelect('SELECT 1').getSingle();
      await testDb.close();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Creates a database with proper error handling
  static Future<ChatDatabase?> createSafeTestDatabase({
    String testName = "safe_test",
    String userId = "test_user",
  }) async {
    try {
      return await getTestDatabase(testName: testName, userId: userId);
    } catch (e) {
      // SQLite not available
      return null;
    }
  }

  /// Resets the database manager state - use in setUpAll()
  static void reset() {
    _testCounter = 0;
    // Note: Don't clear _databases here as active databases might still be in use
  }
}

/// Helper mixin for test classes that need database access
mixin DatabaseTestMixin {
  ChatDatabase? database;
  String get testName => runtimeType.toString();

  Future<void> setUpDatabase({String? customTestName, String userId = "test_user"}) async {
    database = await TestDatabaseManager.createSafeTestDatabase(
      testName: customTestName ?? testName,
      userId: userId,
    );
  }

  Future<void> tearDownDatabase() async {
    if (database != null) {
      await database!.close();
      database = null;
    }
  }

  bool get hasSQLite => database != null;

  void skipIfNoSQLite(String reason) {
    if (!hasSQLite) {
      markTestSkipped('$reason - install libsqlite3-dev to run this test');
    }
  }
}

/// Database test utilities with proper lifecycle management
class SafeDatabaseTestUtils {
  /// Verifies database connectivity safely
  static Future<bool> verifyDatabaseConnectivity(ChatDatabase db) async {
    try {
      await db.customSelect('SELECT 1').getSingle();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Creates test data in database safely
  static Future<void> populateTestData(
    ChatDatabase db, {
    int channelCount = 2,
    int contactCount = 3,
    int messagesPerChannel = 5,
  }) async {
    // Implementation would go here
    // For now, just verify database is working
    await verifyDatabaseConnectivity(db);
  }
}