import 'package:flutter/material.dart';
import 'package:vartalap/widgets/Inherited/current_user.dart';
import 'package:vartalap/widgets/Inherited/vartalap_client_provider.dart';
import 'package:vartalap/widgets/avator.dart';
import 'package:vartalap_messaging/vartalap_messaging.dart';
import 'package:vartalap_messaging_flutter/models/models.dart';

class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  
  List<Contact> _contactResults = [];
  List<ChatMessage> _messageResults = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _contactResults = [];
          _messageResults = [];
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    final clientFlutter = VartalapClientProvider.of(context).client;
    
    final contacts = await clientFlutter.db.channelDao.searchContacts(query).get();
    final messages = await clientFlutter.db.chatDao.searchMessages(query).get();

    if (mounted) {
      setState(() {
        _contactResults = contacts;
        _messageResults = messages;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search contacts and messages...',
            border: InputBorder.none,
            hintStyle: TextStyle(color: Colors.white70),
          ),
          style: const TextStyle(color: Colors.white),
          onChanged: _performSearch,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () {
              _searchController.clear();
              _performSearch('');
            },
          )
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Contacts'),
            Tab(text: 'Messages'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildContactsTab(),
                _buildMessagesTab(),
              ],
            ),
    );
  }

  Widget _buildContactsTab() {
    if (_contactResults.isEmpty && _searchController.text.isNotEmpty) {
      return const Center(child: Text('No contacts found.'));
    }
    if (_searchController.text.isEmpty) {
      return const Center(child: Text('Type to search contacts.'));
    }

    return ListView.builder(
      itemCount: _contactResults.length,
      itemBuilder: (context, index) {
        final contact = _contactResults[index];
        return ListTile(
          leading: Avator(
            text: contact.displayName.isNotEmpty ? contact.displayName[0] : '?',
            image: contact.photo,
            width: 40,
            height: 40,
          ),
          title: Text(contact.displayName),
          subtitle: Text(contact.phone ?? contact.username ?? ''),
          onTap: () async {
            final currentUser = CurrentUser.of(context).user!;
            final clientFlutter = VartalapClientProvider.of(context).client;
            
            final channels = await clientFlutter.getChannels(
                filter: ChannelFilter(
              type: ChannelType.individual,
              memberIds: [contact.id],
            )).get();

            ChannelModel? channel;
            if (channels.isNotEmpty) {
              channel = channels.first;
            } else {
              final chatName = contact.id == currentUser.id ? 'Self' : contact.displayName;
              final newChannel = ChannelModel.initial(
                type: ChannelType.individual,
                extraData: {'name': chatName},
              );
              final members = [
                Member(user: contact, role: null, since: DateTime.now()),
              ];
              if (contact.id != currentUser.id) {
                members.add(Member(user: currentUser, role: null, since: DateTime.now()));
              }
              channel = await clientFlutter.createChannel(newChannel, members);
            }

            final chatClient = await clientFlutter.chat(channel: channel, currentUser: currentUser);

            if (mounted) {
              Navigator.of(context).pushReplacementNamed('/chat', arguments: chatClient);
            }
          },
        );
      },
    );
  }

  Widget _buildMessagesTab() {
    if (_messageResults.isEmpty && _searchController.text.isNotEmpty) {
      return const Center(child: Text('No messages found.'));
    }
    if (_searchController.text.isEmpty) {
      return const Center(child: Text('Type to search messages.'));
    }

    return ListView.builder(
      itemCount: _messageResults.length,
      itemBuilder: (context, index) {
        final message = _messageResults[index];
        final isText = message.type == MessageType.text;
        final content = isText ? (message.payload['text'] ?? '') : '[${message.type.name}]';

        return ListTile(
          leading: const Icon(Icons.message),
          title: Text(
            content.toString(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(message.timestamp.toString().substring(0, 16)),
          onTap: () async {
            final currentUser = CurrentUser.of(context).user!;
            final clientFlutter = VartalapClientProvider.of(context).client;
            
            // Look up the channel for this message
            final channelRecord = await (clientFlutter.db.select(clientFlutter.db.channels)
                  ..where((tbl) => tbl.id.equals(message.channelId)))
                .getSingleOrNull();

            if (channelRecord != null && mounted) {
              // Convert to ChannelModel
              final channelModel = ChannelModel(
                id: channelRecord.id,
                type: channelRecord.type,
                config: channelRecord.config,
                extraData: channelRecord.extraData,
                muted: channelRecord.muted,
                createdAt: channelRecord.createdAt,
                updatedAt: channelRecord.updatedAt,
              );
              
              final chatClient = await clientFlutter.chat(channel: channelModel, currentUser: currentUser);
              
              if (mounted) {
                Navigator.of(context).pushReplacementNamed('/chat', arguments: chatClient);
              }
            }
          },
        );
      },
    );
  }
}
