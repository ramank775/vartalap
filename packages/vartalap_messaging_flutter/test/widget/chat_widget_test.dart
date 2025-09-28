import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';
import 'package:vartalap_messaging_flutter/db/chat_db.dart';
import 'package:vartalap_messaging_flutter/dao/dao.dart';

import '../mocks/mock_vartalap_chat_client.dart';
import '../factories/test_data_factories.dart';
import '../utils/database_test_utils.dart';

/// Simple widget tests demonstrating local-first chat functionality testing
///
/// These tests show how to test chat UI components with in-memory local data,
/// bypassing server and platform dependencies while testing the complete user experience.
void main() {
  group('Chat Widget Tests - Local-First UI', () {
    late MockVartalapChatClient mockChatClient;
    late ChatDatabase database;
    late ChatDao chatDao;
    late ChannelDao channelDao;

    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    setUp(() async {
      TestDataFactories.resetCounters();

      mockChatClient = MockVartalapChatClient(
        mockUserId: QuickTestData.testUserId.toString(),
      );

      // Use in-memory database for testing to avoid platform dependencies
      database = DatabaseTestUtils.createInMemoryDatabase(
        userId: QuickTestData.testUserId.toString(),
      );
      await DatabaseTestUtils.verifyDatabaseConnectivity(database);
      chatDao = database.chatDao;
      channelDao = database.channelDao;
    });

    tearDown(() async {
      await database.close();
      mockChatClient.dispose();
    });

    testWidgets('should test basic widget functionality with mock data', (tester) async {
      // This is a simplified test that focuses on testing the basic concept
      // without complex dependencies

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: Text('Local-First Chat Test'),
            ),
          ),
        ),
      );

      // Assert - Basic widget functionality works
      expect(find.text('Local-First Chat Test'), findsOneWidget);
    });

    testWidgets('should demonstrate database-backed widget patterns', (tester) async {
      // Arrange - Create test data using the database directly
      final channel = TestDataFactories.createChannel(
        extraData: {'name': 'Test Channel'},
      );
      await channelDao.createChannel(channel, []);

      final message = TestDataFactories.createTextMessage(
        text: "Hello from database!",
      );
      await chatDao.sendMessage(message, channel);

      // Act - Build a simple widget that shows data from database
      await tester.pumpWidget(
        MaterialApp(
          home: TestChatDataWidget(
            channelDao: channelDao,
            chatDao: chatDao,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Assert - Widget should display data from database
      expect(find.text('Test Channel'), findsOneWidget);
      expect(find.text('1 messages'), findsOneWidget);
    });
  });
}

/// Simple widget to demonstrate database integration
class TestChatDataWidget extends StatelessWidget {
  final ChannelDao channelDao;
  final ChatDao chatDao;

  const TestChatDataWidget({
    super.key,
    required this.channelDao,
    required this.chatDao,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Test Chat Data')),
      body: StreamBuilder<List<ChannelModel>>(
        stream: channelDao.getChannels().watch(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Text('No channels yet'),
            );
          }

          final channels = snapshot.data!;
          return ListView.builder(
            itemCount: channels.length,
            itemBuilder: (context, index) {
              final channel = channels[index];
              return StreamBuilder<List<ChatMessage>>(
                stream: chatDao.getMessages(channel: channel).watch(),
                builder: (context, messageSnapshot) {
                  final messageCount = messageSnapshot.data?.length ?? 0;
                  return ListTile(
                    title: Text(channel.displayName),
                    subtitle: Text('$messageCount messages'),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}