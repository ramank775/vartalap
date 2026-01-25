import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:vartalap/config/app_config.dart';
import 'package:vartalap_messaging_flutter/repository/auth_repository.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/Inherited/current_user.dart';
import 'package:vartalap/widgets/Inherited/vartalap_client_provider.dart';
import 'package:vartalap/widgets/chat_preview.dart';
import 'package:flutter/material.dart';
import 'package:vartalap/utils/url_helper.dart';
import 'package:vartalap/widgets/app_logo.dart';
import 'package:vartalap/widgets/rich_message.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';

class Chats extends StatefulWidget {
  const Chats({super.key});

  @override
  ChatsState createState() => ChatsState();
}

class ChatsState extends State<Chats> {
  List<ChatPreview> _selectedChats = [];

  @override
  void initState() {
    super.initState();
    _selectedChats = [];
  }

  @override
  Widget build(BuildContext context) {
    final client = VartalapClientProvider.of(context).client;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          AppConfig.packageInfo.appName,
          style: VartalapTheme.theme.appTitleStyle.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        actions: getActions(),
      ),
      body: Container(
        padding: EdgeInsets.fromLTRB(5, 5, 5, 0),
        child: StreamBuilder<List<ChatPreview>>(
          stream: client.watchChatPreviews(),
          builder: (context, chatSnapshot) {
            switch (chatSnapshot.connectionState) {
              case ConnectionState.none:
                return Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.grey),
                  ),
                );
              case ConnectionState.waiting:
                return Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.grey),
                  ),
                );
              case ConnectionState.active:
              case ConnectionState.done:
                if (chatSnapshot.hasError) {
                  // Don't show error if it's due to logout (database closed)
                  // The Consumer in main.dart will handle navigation
                  debugPrint('Chat stream error: ${chatSnapshot.error}');
                  return Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.grey),
                    ),
                  );
                }
            }
            return StreamBuilder<Map<int, int>>(
              stream: client.watchUnreadCounts(),
              builder: (context, unreadSnapshot) {
                if (unreadSnapshot.hasError) {
                  // Don't show error if it's due to logout (database closed)
                  debugPrint('Unread counts stream error: ${unreadSnapshot.error}');
                  return Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.grey),
                    ),
                  );
                }
                return ChatListView(
                  chats: chatSnapshot.data!,
                  unreadCounts: unreadSnapshot.data ?? {},
                  selectedChats: _selectedChats,
                  selectOrRemove: selectOrRemove,
                  navigate: navigate,
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => navigate('/new-chat'),
        tooltip: 'New',
        backgroundColor: Theme.of(context).iconTheme.color,
        child: Icon(Icons.add),
      ),
    );
  }

  void selectOrRemove(ChatPreview chat) {
    setState(() {
      if (!_selectedChats.remove(chat)) {
        _selectedChats.add(chat);
      }
    });
  }

  List<Widget> getActions() {
    List<Widget> actions = [];
    if (_selectedChats.isNotEmpty) {
      actions.add(IconButton(
        iconSize: 22,
        icon: Icon(Icons.clear),
        onPressed: () {
          setState(() {
            _selectedChats = [];
          });
        },
      ));
      actions.add(IconButton(
        iconSize: 22,
        icon: Icon(Icons.delete),
        onPressed: () async {
          setState(() {
            _selectedChats = [];
          });
        },
      ));
    }
    actions.add(
      PopupMenuButton(
        onSelected: (value) async {
          //Navigator.of(context).pop(value);
          if (value == 'About Dialog') {
            showAboutDialog(
              context: context,
              applicationName: AppConfig.packageInfo.appName,
              applicationIcon: AppLogo(size: 25),
              applicationVersion:
                  "${AppConfig.packageInfo.version}+${AppConfig.packageInfo.buildNumber}",
              children: <Widget>[
                Text(
                  AppConfig.subtitle,
                ),
                RichMessage(
                  AppConfig.description,
                  TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ),
                Text("------------------------------------------------"),
                RichMessage(
                    """Server Info:\n API URL: ${AppConfig.apiUrl} \n WebSocket: ${AppConfig.wsUrl}""",
                    TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ))
              ],
            );
          } else if (value == 'Privacy Policy') {
            var link = AppConfig.privacyPolicy;
            launchUrl(link);
          } else if (value == "Profile") {
            Navigator.of(context).pushNamed('/profile');
          } else if (value == "Logout") {
            final auth = Provider.of<AuthRepository>(context,
                listen: false);
            await auth.logout();
          }
        },
        itemBuilder: (BuildContext context) {
          final options = [
            PopupMenuItem(value: 'Profile', child: Text("Profile")),
            PopupMenuItem(value: 'About Dialog', child: Text("About us")),
            PopupMenuItem(
              value: 'Privacy Policy',
              child: Text("Privacy Policy"),
            ),
          ];
          if (!kReleaseMode) {
            options.add(PopupMenuItem(value: "Logout", child: Text("Logout")));
          }
          return options;
        },
      ),
    );
    return actions;
  }

  Future<void> navigate(String screen, {Object? data}) async {
    // Get references before async operations
    final currentUser = CurrentUser.of(context).user!;
    final client = VartalapClientProvider.of(context).client;
    final navigator = Navigator.of(context);

    var result = await navigator.pushNamed(screen, arguments: data);
    if (screen == "/new-chat") {
      if (result == null) {
        return;
      }
      ChannelModel channel;
      if (result is ChannelModel) {
        channel = result;
      } else {
        return;
      }
      final chat = await client.chat(
        channel: channel,
        currentUser: currentUser,
      );
      if (mounted) {
        await Navigator.of(context).pushNamed('/chat', arguments: chat);
      }
    }
  }
}

class ChatListView extends StatefulWidget {
  const ChatListView({
    super.key,
    required List<ChatPreview> chats,
    required Map<int, int> unreadCounts,
    required List<ChatPreview> selectedChats,
    required Function selectOrRemove,
    required Function navigate,
  })  : _chats = chats,
        _unreadCounts = unreadCounts,
        _selectedChats = selectedChats,
        _selectOrRemove = selectOrRemove,
        _navigate = navigate;

  final List<ChatPreview> _chats;
  final Map<int, int> _unreadCounts;
  final List<ChatPreview> _selectedChats;
  final Function _selectOrRemove;
  final Function _navigate;

  @override
  State<StatefulWidget> createState() => ChatListViewState();
}

class ChatListViewState extends State<ChatListView>
    with WidgetsBindingObserver {
  late List<ChatPreview> _chats;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _chats = widget._chats;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // These are the callbacks
    switch (state) {
      case AppLifecycleState.resumed:
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _chats.isEmpty
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  Icons.group_add,
                  size: 50,
                ),
                SizedBox(
                  height: 5,
                ),
                RichText(
                  text: TextSpan(
                      style: TextStyle(
                        color: Colors.grey,
                      ),
                      children: [
                        TextSpan(text: "Click"),
                        TextSpan(
                          text: " + ",
                          style: TextStyle(
                            color: Theme.of(context).iconTheme.color,
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(text: "to create chat")
                      ]),
                )
              ],
            ),
          )
        : ListView.builder(
            itemCount: _chats.length,
            itemBuilder: (context, i) {
              final chat = _chats[i];
              // Use unread count from the stream if available, otherwise use the one from ChatPreview
              final effectiveUnreadCount =
                  widget._unreadCounts[chat.channel.id] ?? chat.unreadCount;

              // Create a new ChatPreview with the updated unread count if different
              final chatWithUpdatedCount =
                  effectiveUnreadCount != chat.unreadCount
                      ? ChatPreview(
                          channel: chat.channel,
                          lastMessage: chat.lastMessage,
                          unreadCount: effectiveUnreadCount,
                        )
                      : chat;

              return ChatPreviewWidget(
                chatWithUpdatedCount,
                (ChannelModel channel) async {
                  if (widget._selectedChats.isNotEmpty) {
                    widget._selectOrRemove(channel);
                    return;
                  }
                  final currentUser = CurrentUser.of(context).user!;
                  final client = VartalapClientProvider.of(context).client;
                  final chatClient = await client.chat(
                    channel: channel,
                    currentUser: currentUser,
                  );
                  widget._navigate('/chat', data: chatClient);
                },
                widget._selectOrRemove,
                isSelected: widget._selectedChats.contains(widget._chats[i]),
              );
            },
          );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
