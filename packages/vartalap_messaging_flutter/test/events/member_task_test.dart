import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap_messaging_flutter/db/chat_db.dart';
import 'package:vartalap_messaging_flutter/events/api_request_task.dart';
import 'package:drift/drift.dart' hide isNotNull;

import '../mocks/mock_vartalap_chat_client.dart';
import '../utils/database_test_utils.dart';

void main() {
  group('ApiRequestTask Tests', () {
    late MockVartalapChatClient mockClient;
    late ChatDatabase database;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      
      mockClient = MockVartalapChatClient();
      database = DatabaseTestUtils.createInMemoryDatabase(userId: "test_user");
      await DatabaseTestUtils.verifyDatabaseConnectivity(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('AddMembers via ApiRequestTask should process successfully', () async {
      final payload = ApiRequestPayload(
        method: VartalapApiMethod.addMembers,
        data: {
          'channelId': 'remote_channel_id',
          'memberIds': ['remote_user_id'],
        },
      );

      final task = VartalapApiRequestTask(mockClient, database, payload: payload);
      await task.process();
      expect(true, isTrue);
    });

    test('RemoveMember via ApiRequestTask should process successfully', () async {
      final payload = ApiRequestPayload(
        method: VartalapApiMethod.removeMember,
        data: {
          'channelId': 'remote_channel_id',
          'memberId': 'remote_user_id',
        },
      );

      final task = VartalapApiRequestTask(mockClient, database, payload: payload);
      await task.process();
      expect(true, isTrue);
    });

    test('VartalapApiRequestTask should serialize and deserialize correctly', () {
      final payload = ApiRequestPayload(
        method: VartalapApiMethod.addMembers,
        data: {
          'channelId': 'c1',
          'memberIds': ['u1', 'u2'],
        },
      );
      final task = VartalapApiRequestTask(mockClient, database, payload: payload);
      
      final serialized = task.serializePayload();
      final newTask = VartalapApiRequestTask(mockClient, database);
      newTask.deserializePayload(serialized);
      
      expect(newTask.payload.method, VartalapApiMethod.addMembers);
      expect(newTask.payload.data['channelId'], 'c1');
      expect(newTask.payload.data['memberIds'], ['u1', 'u2']);
    });
  });
}
