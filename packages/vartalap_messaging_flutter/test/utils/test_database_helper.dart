import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap_messaging_flutter/db/chat_db.dart';

/// Simplified database helper for testing without Flutter widget dependencies
class TestDatabaseHelper {
  /// Creates a minimal in-memory database for testing
  static ChatDatabase createTestDatabase({String userId = "test_user"}) {
    // Use pure in-memory SQLite without Flutter dependencies
    return ChatDatabase(
      userId: userId,
      inMemory: true,
    );
  }

  /// Sets up Flutter test environment if needed
  static void setupTestEnvironment() {
    TestWidgetsFlutterBinding.ensureInitialized();

    // Mock platform channels that might be needed using current API
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('drift'),
      (call) async => null,
    );
  }

  /// Verifies basic database functionality
  static Future<void> verifyBasicFunctionality(ChatDatabase db) async {
    // Simple verification that doesn't require complex setup
    expect(db.channelDao, isNotNull);
    expect(db.chatDao, isNotNull);
  }

  /// Creates a database with minimal setup for DAO testing
  static Future<ChatDatabase> createAndSetupDatabase({
    String userId = "test_user",
  }) async {
    setupTestEnvironment();

    final db = createTestDatabase(userId: userId);
    await verifyBasicFunctionality(db);

    return db;
  }
}