import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';
import 'package:vartalap/widgets/chat_preview.dart';
import 'package:vartalap/widgets/Inherited/vartalap_client_provider.dart';
import 'package:vartalap/widgets/Inherited/current_user.dart';

class ArchivedChatsScreen extends StatefulWidget {
  const ArchivedChatsScreen({Key? key}) : super(key: key);

  @override
  _ArchivedChatsScreenState createState() => _ArchivedChatsScreenState();
}

class _ArchivedChatsScreenState extends State<ArchivedChatsScreen> {
  @override
  Widget build(BuildContext context) {
    final client = VartalapClientProvider.of(context).client;
    final currentUser = Provider.of<CurrentUser>(context).user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Archived Chats'),
      ),
      body: currentUser == null
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<List<ChatPreview>>(
              stream: client.db.chatDao
                  .getArchivedChatPreviews(currentUserId: currentUser.id)
                  .watch(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(child: Text("Error: ${snapshot.error}"));
                }

                final chats = snapshot.data ?? [];

                if (chats.isEmpty) {
                  return const Center(
                    child: Text(
                      'No archived chats',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: chats.length,
                  itemBuilder: (context, index) {
                    final chat = chats[index];
                    return ChatPreviewWidget(
                      chat,
                      (ChatPreview selectedChat) async {
                        final chatClient = await client.chat(
                            channel: selectedChat.channel,
                            currentUser: currentUser);

                        if (context.mounted) {
                          Navigator.of(context).pushNamed(
                            '/chat',
                            arguments: chatClient,
                          );
                        }
                      },
                      (ChatPreview selectedChat) {
                        // Handle long press if needed
                      },
                    );
                  },
                );
              },
            ),
    );
  }
}

