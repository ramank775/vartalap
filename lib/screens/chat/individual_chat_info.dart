import 'package:flutter/material.dart';
import 'package:vartalap/widgets/avator.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';

class IndividualChatInfo extends StatelessWidget {
  final ChatClient chat;

  const IndividualChatInfo(this.chat, {super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        iconTheme: IconThemeData(color: Theme.of(context).primaryColor),
      ),
      extendBodyBehindAppBar: true,
      body: StreamBuilder<List<Member>>(
        stream: chat.membersStream,
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          final members = snapshot.data!;
          final otherMember = members.firstWhere(
              (m) => m.user.id != chat.currentUser.id,
              orElse: () => members.first);
          final contact = otherMember.user;

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: double.infinity,
                  color: Theme.of(context).scaffoldBackgroundColor,
                  padding: const EdgeInsets.only(top: 80, bottom: 30),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 70,
                        backgroundColor:
                            Theme.of(context).primaryColor.withOpacity(0.1),
                        child: Avator(
                          height: 140,
                          width: 140,
                          text: contact.displayName,
                          image: contact.photo,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        contact.displayName,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (contact.phone != null &&
                          contact.phone!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          contact.phone!,
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Action buttons removed
                const SizedBox(height: 30),
                if (contact.username != null && contact.username!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      child: ListTile(
                        leading:
                            Icon(Icons.alternate_email, color: Colors.grey.shade600),
                        title: const Text('Username'),
                        subtitle: Text(
                          '@${contact.username}',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          leading:
                              Icon(Icons.notifications_outlined, color: Colors.grey.shade600),
                          title: const Text('Mute notifications'),
                          trailing: Switch(
                            value: false,
                            onChanged: (val) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Muting not yet implemented')),
                              );
                            },
                          ),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading:
                              const Icon(Icons.block, color: Colors.red),
                          title: const Text(
                            'Block user',
                            style: TextStyle(color: Colors.red),
                          ),
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Blocking not yet implemented')),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

}
