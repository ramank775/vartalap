import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:vartalap/config/config_store.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/Inherited/config_provider.dart';
import 'package:vartalap/widgets/Inherited/vartalap_client_provider.dart';
import 'package:vartalap/widgets/chat_preview.dart';
import 'package:flutter/material.dart';
import 'package:vartalap/utils/url_helper.dart';
import 'package:vartalap/widgets/app_logo.dart';
import 'package:vartalap/widgets/rich_message.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';

class Chats extends StatefulWidget {
  @override
  ChatsState createState() => ChatsState();
}

class ChatsState extends State<Chats> {
  List<ChatPreview> _selectedChats = [];
  late ConfigStore config;

  @override
  void initState() {
    super.initState();
    this._selectedChats = [];
  }

  @override
  Widget build(BuildContext context) {
    config = ConfigProvider.of(context).configStore;
    final client = VartalapClientProvider.of(context).client;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          config.packageInfo.appName,
          style: VartalapTheme.theme.appTitleStyle.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        actions: getActions(),
      ),
      body: new Container(
        padding: EdgeInsets.fromLTRB(5, 5, 5, 0),
        child: StreamBuilder<List<ChatPreview>>(
          stream: client.getChatPreviews().watch(),
          builder: (context, snapshot) {
            switch (snapshot.connectionState) {
              case ConnectionState.none:
                return Center(
                  child: CircularProgressIndicator(
                    valueColor: new AlwaysStoppedAnimation<Color>(Colors.grey),
                  ),
                );
              case ConnectionState.active:
              case ConnectionState.waiting:
                return Center(
                  child: CircularProgressIndicator(
                    valueColor: new AlwaysStoppedAnimation<Color>(Colors.grey),
                  ),
                );
              case ConnectionState.done:
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Error: ${snapshot.error}'),
                  );
                }
            }
            return ChatListView(
              chats: snapshot.data!,
              selectedChats: _selectedChats,
              selectOrRemove: this.selectOrRemove,
              navigate: this.navigate,
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => navigate('/new-chat'),
        tooltip: 'New',
        child: Icon(Icons.add),
        backgroundColor: Theme.of(context).iconTheme.color,
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
    if (this._selectedChats.length > 0) {
      actions.add(IconButton(
        iconSize: 22,
        icon: Icon(Icons.clear),
        onPressed: () {
          setState(() {
            this._selectedChats = [];
          });
        },
      ));
      actions.add(IconButton(
        iconSize: 22,
        icon: Icon(Icons.delete),
        onPressed: () async {
          setState(() {
            this._selectedChats = [];
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
              applicationName: config.packageInfo.appName,
              applicationIcon: AppLogo(size: 25),
              applicationVersion:
                  "${config.packageInfo.version}+${config.packageInfo.buildNumber}",
              children: <Widget>[
                Text(
                  config.subtitle,
                ),
                RichMessage(
                  config.get("description"),
                  TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ),
                Text("------------------------------------------------"),
                RichMessage(
                    """Server Info:\n API URL: ${config.get("api_url")} \n WebSocket: ${config.get("ws_url")}""",
                    TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ))
              ],
            );
          } else if (value == 'Privacy Policy') {
            var link = config.get('privacy_policy');
            launchUrl(link);
          } else if (value == "Logout") {
            await AuthService.instance.signout();
          }
        },
        itemBuilder: (BuildContext context) {
          final options = [
            PopupMenuItem(value: 'About Dialog', child: Text("About us")),
            PopupMenuItem(
              value: 'Privacy Policy',
              child: Text("Privacy Policy"),
            ),
          ];
          if (!kReleaseMode) {
            options.add(PopupMenuItem(child: Text("Logout"), value: "Logout"));
          }
          return options;
        },
      ),
    );
    return actions;
  }

  Future<void> navigate(String screen, {Object? data}) async {
    var result = await Navigator.pushNamed(context, screen, arguments: data);
    if (screen == "/new-chat") {
      if (result == null) {
        return;
      }
      ChannelModel chat;
      if (result is ChannelModel) {
        chat = result;
      } else {
        return;
      }
      await Navigator.of(context).pushNamed('/chat', arguments: chat);
    }
  }
}

class ChatListView extends StatefulWidget {
  const ChatListView({
    Key? key,
    required List<ChatPreview> chats,
    required List<ChatPreview> selectedChats,
    required Function selectOrRemove,
    required Function navigate,
  })  : _chats = chats,
        _selectedChats = selectedChats,
        _selectOrRemove = selectOrRemove,
        _navigate = navigate,
        super(key: key);

  final List<ChatPreview> _chats;
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
    return _chats.length == 0
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
            itemBuilder: (context, i) => new ChatPreviewWidget(
              _chats[i],
              (ChannelModel channel) async {
                if (widget._selectedChats.length > 0) {
                  widget._selectOrRemove(channel);
                  return;
                }
                widget._navigate('/chat', data: channel);
              },
              widget._selectOrRemove,
              isSelected: widget._selectedChats.contains(widget._chats[i]),
            ),
          );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
