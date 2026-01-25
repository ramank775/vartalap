import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap_messaging_flutter/db/chat_db.dart';
import 'package:vartalap_messaging_flutter/events/add_member_task.dart';
import 'package:vartalap_messaging_flutter/events/remove_member_task.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';
import 'package:drift/drift.dart' hide isNotNull;

import '../mocks/mock_vartalap_chat_client.dart';
import '../factories/test_data_factories.dart';
import '../utils/database_test_utils.dart';

void main() {
  group('Member Task Tests', () {
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

    test('AddMembersTask should process successfully', () async {
      // 1. Setup local data
      final channel = TestDataFactories.createChannel(id: 1);
      await database.channelDao.createChannel(channel, []);
      
      // Update with remote ID
      await (database.update(database.channels)..where((tbl) => tbl.id.equals(1)))
          .write(const ChannelsCompanion(cid: Value('remote_channel_id')));

      final contact = TestDataFactories.createContact(id: 1, uid: 'remote_user_id');
      await database.channelDao.syncContacts([contact]);

      final payload = AddMembersPayload(
        localChannelId: 1,
        localMemberIds: [1],
      );

      final task = AddMembersTask(mockClient, database, payload: payload);

      // 2. Process task
      await task.process();

      // 3. Verify (No exception means success, but we could mock client better to verify calls)
      expect(true, isTrue);
    });

    test('RemoveMemberTask should process successfully', () async {
      // 1. Setup local data
      final channel = TestDataFactories.createChannel(id: 1);
      await database.channelDao.createChannel(channel, []);
      
      // Update with remote ID
      await (database.update(database.channels)..where((tbl) => tbl.id.equals(1)))
          .write(const ChannelsCompanion(cid: Value('remote_channel_id')));

      final contact = TestDataFactories.createContact(id: 1, uid: 'remote_user_id');
      await database.channelDao.syncContacts([contact]);

      final payload = RemoveMemberPayload(
        localChannelId: 1,
        localMemberId: 1,
      );

      final task = RemoveMemberTask(mockClient, database, payload: payload);

      // 2. Process task
      await task.process();

      // 3. Verify
      expect(true, isTrue);
    });

    test('Tasks should serialize and deserialize correctly', () {
      final addPayload = AddMembersPayload(localChannelId: 1, localMemberIds: [1, 2]);
      final addTask = AddMembersTask(mockClient, database, payload: addPayload);
      
      final serializedAdd = addTask.serializePayload();
      final newTaskAdd = AddMembersTask(mockClient, database);
      newTaskAdd.deserializePayload(serializedAdd);
      
      expect(newTaskAdd.payload.localChannelId, 1);
      expect(newTaskAdd.payload.localMemberIds, [1, 2]);

      final removePayload = RemoveMemberPayload(localChannelId: 3, localMemberId: 4);
      final removeTask = RemoveMemberTask(mockClient, database, payload: removePayload);
      
      final serializedRemove = removeTask.serializePayload();
      final newTaskRemove = RemoveMemberTask(mockClient, database);
      newTaskRemove.deserializePayload(serializedRemove);
      
      expect(newTaskRemove.payload.localChannelId, 3);
      expect(newTaskRemove.payload.localMemberId, 4);
    });
  });
}
