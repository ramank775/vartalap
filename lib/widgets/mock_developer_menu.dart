import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';
import 'package:vartalap_messaging_flutter/db/chat_db.dart' show ContactsCompanion;
import 'package:vartalap_messaging/vartalap_messaging.dart' as messaging;
import 'package:vartalap_testing/vartalap_testing.dart';

/// Ensure a mock contact exists in the DB with a proper name
Future<void> _ensureMockContact(
    VartalapChatClientFlutter client, String uid, String name, String phone) async {
  final existing = await (client.db.select(client.db.contacts)
        ..where((tbl) => tbl.uid.equals(uid)))
      .getSingleOrNull();
  if (existing != null) return;
  await client.db.into(client.db.contacts).insert(ContactsCompanion.insert(
        uid: Value(uid),
        username: Value(uid),
        name: Value(name),
        phone: Value(phone),
        status: ContactStatus.active,
      ));
}

/// A developer overlay that only appears in Mock Mode to trigger server events.
class MockDeveloperMenu extends StatelessWidget {
  final Widget child;
  final GlobalKey<NavigatorState>? navigatorKey;

  const MockDeveloperMenu({
    super.key,
    required this.child,
    this.navigatorKey,
  });

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
    final client = Provider.of<VartalapChatClientFlutter>(context, listen: false);
    final chatClient = client.client;

    if (chatClient is! MockVartalapChatClient) return;

    final navContext = navigatorKey?.currentContext ?? context;

    showModalBottomSheet(
      context: navContext,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (context) => _MockMenuSheet(chatClient: chatClient, client: client),
    );
  }
}

class _MockMenuSheet extends StatefulWidget {
  final MockVartalapChatClient chatClient;
  final VartalapChatClientFlutter client;
  const _MockMenuSheet({required this.chatClient, required this.client});

  @override
  State<_MockMenuSheet> createState() => _MockMenuSheetState();
}

class _MockMenuSheetState extends State<_MockMenuSheet> {
  String? _lastInjectedMessageId;

  /// Returns the most recent message ID — either manually injected or sent from chat UI
  String? get _activeMessageId =>
      _lastInjectedMessageId ??
      (widget.chatClient.sentMessageIds.isNotEmpty
          ? widget.chatClient.sentMessageIds.last
          : null);

  @override
  Widget build(BuildContext context) {
    final isManual = widget.chatClient.activeScenario is ManualTakeoverScenario;

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  const Icon(Icons.bug_report, size: 20),
                  const SizedBox(width: 8),
                  Text('Mock Server Control',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          )),
                  const Spacer(),
                  Text(
                    isManual ? 'MANUAL' : 'AUTO',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isManual ? Colors.orange : Colors.green,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),

            // --- Scenario switchers ---
            _SectionHeader('Scenarios'),
            ListTile(
              leading: Icon(
                Icons.auto_awesome,
                color: !isManual ? Colors.green : null,
              ),
              title: const Text('Happy Path (Auto)'),
              subtitle: const Text('Sent → Delivered → Read automatically'),
              selected: !isManual,
              onTap: () {
                widget.chatClient.setScenario(DefaultHappyPathScenario());
                setState(() {});
              },
            ),
            ListTile(
              leading: Icon(
                Icons.pan_tool,
                color: isManual ? Colors.orange : null,
              ),
              title: const Text('Manual Takeover'),
              subtitle: const Text('Messages stay pending until you ack'),
              selected: isManual,
              onTap: () {
                widget.chatClient.setScenario(ManualTakeoverScenario());
                setState(() {});
              },
            ),
            ListTile(
              leading: Icon(
                Icons.wifi_off,
                color: widget.chatClient.activeScenario is OfflineScenario ? Colors.red : null,
              ),
              title: const Text('Offline'),
              subtitle: const Text('No acks — messages stay pending forever'),
              selected: widget.chatClient.activeScenario is OfflineScenario,
              onTap: () {
                widget.chatClient.setScenario(OfflineScenario());
                setState(() {});
              },
            ),
            ListTile(
              leading: Icon(
                Icons.error_outline,
                color: widget.chatClient.activeScenario is NetworkErrorScenario ? Colors.red : null,
              ),
              title: const Text('Network Error'),
              subtitle: const Text('All messages fail with error'),
              selected: widget.chatClient.activeScenario is NetworkErrorScenario,
              onTap: () {
                widget.chatClient.setScenario(NetworkErrorScenario());
                setState(() {});
              },
            ),

            const Divider(),

            // --- Inject incoming message ---
            _SectionHeader('Inject Incoming Message'),
            ListTile(
              leading: const Icon(Icons.message),
              title: const Text('Message from Alice'),
              subtitle: const Text('Creates a 1:1 chat with Alice if needed'),
              onTap: () async {
                // Always use the real logged-in userId as the 'to' target
                final myUid = await widget.client.getLoggedInUser()
                    ?? widget.chatClient.mockUserId;
                final msgId = 'manual_${DateTime.now().millisecondsSinceEpoch}';
                // Ensure Alice contact exists with a proper name
                await _ensureMockContact(widget.client, 'alice_mock', 'Alice', '+1987654321');
                final msg = messaging.RemoteMessage()
                  ..id = msgId
                  ..head = messaging.Head(
                    type: messaging.ChannelType.individual,
                    to: myUid,
                    from: 'alice_mock',
                    category: 'message',
                  )
                  ..meta = messaging.Meta()
                  ..body = {'text': 'Hey! This is Alice 👋'};

                widget.chatClient.injectMessage(msg);
                setState(() => _lastInjectedMessageId = msgId);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Message injected — check the chats list'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                  Navigator.pop(context);
                }
              },
            ),

            // --- Manual ack controls (only in Manual mode) ---
            if (isManual) ...[
              const Divider(),
              _SectionHeader('Manual Message Acks'),
              if (_activeMessageId != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text(
                    'Last message: $_activeMessageId',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(fontFamily: 'monospace'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Wrap(
                  spacing: 8,
                  children: [
                    _AckChip(
                      label: '✓ Sent',
                      color: Colors.blue,
                      onTap: _activeMessageId == null
                          ? null
                          : () => widget.chatClient.simulateAck(
                              _activeMessageId!, 'sent'),
                    ),
                    _AckChip(
                      label: '✓✓ Delivered',
                      color: Colors.teal,
                      onTap: _activeMessageId == null
                          ? null
                          : () => widget.chatClient.simulateAck(
                              _activeMessageId!, 'delivered'),
                    ),
                    _AckChip(
                      label: '✓✓ Read',
                      color: Colors.green,
                      onTap: _activeMessageId == null
                          ? null
                          : () => widget.chatClient.simulateAck(
                              _activeMessageId!, 'read'),
                    ),
                    _AckChip(
                      label: '✗ Error',
                      color: Colors.red,
                      onTap: _activeMessageId == null
                          ? null
                          : () => widget.chatClient.simulateError(
                              _activeMessageId!, 'Mock error'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Send a message from the chat screen, then use these buttons to progress its status.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey),
                ),
              ),
            ],

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.grey,
              letterSpacing: 1.2,
            ),
      ),
    );
  }
}

class _AckChip extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _AckChip({required this.label, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      backgroundColor: onTap == null ? Colors.grey.shade200 : color.withValues(alpha: 0.15),
      side: BorderSide(color: onTap == null ? Colors.grey : color, width: 1),
      labelStyle: TextStyle(color: onTap == null ? Colors.grey : color),
      onPressed: onTap,
    );
  }
}
