import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vartalap/services/vartalap_authenticated_client.dart';
import 'package:vartalap_messaging/vartalap_messaging.dart' as messaging;
import 'package:vartalap_testing/vartalap_testing.dart';

/// A developer menu that only appears in Mock Mode to trigger server events.
class MockDeveloperMenu extends StatelessWidget {
  final Widget child;

  const MockDeveloperMenu({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned(
          bottom: 80,
          right: 16,
          child: FloatingActionButton.small(
            backgroundColor: Colors.red.withValues(alpha: 0.7),
            onPressed: () => _showMenu(context),
            child: const Icon(Icons.bug_report, color: Colors.white),
          ),
        ),
      ],
    );
  }

  void _showMenu(BuildContext context) {
    final authClient = Provider.of<VartalapAuthenticatedClient>(context, listen: false);
    final chatClient = authClient.client.client; // The VartalapChatClient

    if (chatClient is! MockVartalapChatClient) return;

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text('Mock Server Control', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.auto_awesome),
                title: const Text('Scenario: Happy Path (Auto)'),
                onTap: () {
                  chatClient.setScenario(DefaultHappyPathScenario());
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.pan_tool),
                title: const Text('Scenario: Manual Takeover'),
                onTap: () {
                  chatClient.setScenario(ManualTakeoverScenario());
                  Navigator.pop(context);
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.message),
                title: const Text('Inject Message from Alice'),
                onTap: () {
                  final msg = messaging.RemoteMessage()
                    ..id = 'manual_${DateTime.now().millisecondsSinceEpoch}'
                    ..head = messaging.Head(
                      type: messaging.ChannelType.individual,
                      to: chatClient.mockUserId,
                      from: '+9876543210', // Alice
                      category: 'message',
                    )
                    ..meta = messaging.Meta()
                    ..body = {'text': 'This is a manual injection!'};
                  
                  chatClient.injectMessage(msg);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.error),
                title: const Text('Inject Global Network Error'),
                onTap: () {
                  // TODO: Implement global error simulation
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
