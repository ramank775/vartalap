import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:vartalap_messaging_flutter/db/chat_db.dart';
import 'package:vartalap_messaging_flutter/events/asset_upload_task.dart';
import 'package:vartalap_messaging_flutter/events/message_task.dart';
import 'package:vartalap_messaging_flutter/events/sync_contact_task.dart';

import '../mocks/mock_vartalap_chat_client.dart';
import '../utils/database_test_utils.dart';

void main() {
  group('Task Serialization Tests', () {
    late MockVartalapChatClient mockClient;
    late ChatDatabase database;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

      mockClient = MockVartalapChatClient();
      database = DatabaseTestUtils.createInMemoryDatabase(userId: 'test_user');
      await DatabaseTestUtils.verifyDatabaseConnectivity(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('SendMessageTask should serialize and deserialize correctly', () {
      final payload = SendMessage(1, [10, 11, 12]);
      final task = SendMessageTask(mockClient, database, payload: payload);

      final serialized = task.serializePayload();
      final newTask = SendMessageTask(mockClient, database);
      newTask.deserializePayload(serialized);

      expect(newTask.payload.channelId, 1);
      expect(newTask.payload.messageIds, [10, 11, 12]);
    });

    test('AssetUploadTask should serialize and deserialize correctly', () {
      final task = AssetUploadTask(mockClient, database, payload: 42);

      final serialized = task.serializePayload();
      final newTask = AssetUploadTask(mockClient, database);
      newTask.deserializePayload(serialized);

      expect(newTask.payload, 42);
    });

    test('SyncContactsTask should serialize and deserialize without errors', () {
      final task = SyncContactsTask(mockClient, database);

      final serialized = task.serializePayload();
      final newTask = SyncContactsTask(mockClient, database);
      newTask.deserializePayload(serialized);

      expect(serialized, '');
      expect(newTask.serializePayload(), '');
    });
  });
}
