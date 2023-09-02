import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vartalap/config/config_store.dart';
import 'package:vartalap/models/chat.dart';
import 'package:vartalap/models/user.dart';
import 'package:vartalap/widgets/chat_preview.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/services/user_service.dart';
import 'package:flutter/material.dart';
import 'package:vartalap/widgets/contact.dart';

class NewChatScreen extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => NewChatState();
}

class NewChatState extends State<NewChatScreen>
    with SingleTickerProviderStateMixin {
  late Future<List<User>> _contacts;
  late Future<List<Chat>> _groups;
  late TabController _tabController;
  late Future<PermissionStatus> _fPermission;
  bool _openSearch = false;
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _contacts = UserService.getUsers();
    _groups = ChatService.getGroups();
    _fPermission = Permission.contacts.status;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return new Scaffold(
        appBar: this._openSearch ? buildSearchAppBar() : buildAppBar(),
        body: TabBarView(
          controller: _tabController,
          children: [
            contacts(),
            GroupList(
              groups: _groups,
              onTap: onGroupTap,
            ),
          ],
        ));
  }

  Widget contacts() {
    return FutureBuilder<PermissionStatus>(
      future: _fPermission,
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
        if (snapshot.data == PermissionStatus.granted) {
          return ContactList(contacts: _contacts);
        } else {
          return ContactPermissionDisclosure(onSkip: () {
            _tabController.index = 1;
          }, onAllow: () {
            setState(() {
              _fPermission = Permission.contacts.status;
              _contacts = UserService.getUsers(sync: true);
            });
          });
        }
      },
    );
  }

  Future onGroupTap(Chat ch) async {
    if (ch.users.length == 0) {
      var _users = await ChatService.getChatUserByid(ch.id);
      _users.forEach((u) {
        ch.addUser(u);
      });
    }
    Navigator.of(context).pop(ch);
  }

  AppBar buildAppBar() {
    return AppBar(
      title: Text(
        'New Chat',
        style: TextStyle(
          fontWeight: FontWeight.bold,
        ),
      ),
      actions: <Widget>[
        IconButton(
          tooltip: 'Search',
          icon: Icon(Icons.search),
          onPressed: () {
            setState(() {
              this._openSearch = true;
            });
          },
        ),
        PopupMenuButton(itemBuilder: (BuildContext cntx) {
          List<PopupMenuEntry<Object>> entries = [];
          entries.add(PopupMenuItem(
            child: GestureDetector(
              child: Text("Refresh"),
              onTap: () {
                setState(() {
                  _contacts = UserService.getUsers(sync: true);
                  _groups = ChatService.getGroups();
                });
              },
            ),
          ));
          return entries;
        })
      ],
      bottom: TabBar(
        controller: _tabController,
        tabs: [
          Tab(
            child: Icon(Icons.contacts),
          ),
          Tab(
            child: Icon(Icons.group),
          )
        ],
      ),
    );
  }

  AppBar buildSearchAppBar() {
    return AppBar(
      leading: TextButton(
        style: TextButton.styleFrom(
          shape: CircleBorder(),
          padding: const EdgeInsets.only(left: 1.0),
        ),
        onPressed: () {
          setState(() {
            this._openSearch = false;
            this._contacts = UserService.getUsers();
            this._groups = ChatService.getGroups();
          });
        },
        child: Icon(
          Icons.arrow_back,
          size: 24.0,
        ),
      ),
      titleSpacing: 0,
      automaticallyImplyLeading: false,
      title: TextField(
        style: TextStyle(
          fontSize: 20.0,
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: "Search",
          hintStyle: TextStyle(
            fontSize: 20.0,
          ),
        ),
        maxLines: 1,
        autofocus: true,
        onChanged: (value) {
          setState(() {
            if (_tabController.index == 0)
              this._contacts = UserService.getUsers(search: value);
            else
              this._groups = ChatService.getGroups(search: value);
          });
        },
      ),
      actions: [],
    );
  }
}

class ContactPermissionDisclosure extends StatelessWidget {
  const ContactPermissionDisclosure(
      {Key? key, required Function onSkip, required Function onAllow})
      : _onSkip = onSkip,
        _onAllow = onAllow,
        super(key: key);
  final Function _onSkip;
  final Function _onAllow;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(15.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            children: [
              Text(
                "Contact Permission Required",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          Icon(
            Icons.contacts_rounded,
            size: 70,
          ),
          Column(
            children: [
              Text(
                "Vartalap need to access your contacts, to provide you with the list of users using our services in your contact.",
              ),
              Text(""),
              Text(
                "All the information expect phone number are stored on your device only and are not collected in any channel. "
                "Contacts syncing happen at periodically, inorder to keep the contact upto date.",
                style: TextStyle(fontSize: 13),
              ),
              Text(""),
              Text(
                "Note: Your contact's phone number are not stored on servers, only used for the syncing your contact list.",
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              )
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              TextButton(
                  onPressed: () {
                    _onSkip();
                  },
                  child: Text('Skip')),
              TextButton(
                  onPressed: () async {
                    final permission = await Permission.contacts.request();
                    if (permission == PermissionStatus.granted) {
                      _onAllow();
                    }
                  },
                  child: Text('Allow'))
            ],
          )
        ],
      ),
    );
  }
}

class GroupList extends StatelessWidget {
  const GroupList({
    Key? key,
    required Future<List<Chat>> groups,
    required Function(Chat ch) onTap,
  })  : _groups = groups,
        _onTap = onTap,
        super(key: key);

  final Future<List<Chat>> _groups;
  final Function(Chat) _onTap;
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Iterable<Chat>>(
      future: _groups,
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
        List<dynamic> data = [];
        data.add(ListTile(
          leading: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.all(4.0),
            child: Icon(
              Icons.group,
              size: 32.0,
              color: Colors.grey,
            ),
          ),
          title: Text('New group',
              style: TextStyle(
                fontSize: 18.0,
                fontWeight: FontWeight.bold,
              )),
          onTap: () {
            Navigator.of(context).pushReplacementNamed('/new-group');
          },
        ));

        data.addAll(snapshot.data!);
        return ListView.builder(
            itemCount: data.length,
            itemBuilder: (context, i) {
              if (i < 1) {
                return data[i];
              }
              Chat chat = data.elementAt(i);
              ChatPreview preview =
                  ChatPreview(chat.id, chat.title, chat.pic, '', 0, 0);
              preview.type = chat.type;
              return ChatPreviewWidget(
                preview,
                _onTap,
                _onTap,
              );
            });
      },
    );
  }
}

class ContactList extends StatelessWidget {
  const ContactList({
    Key? key,
    required Future<List<User>> contacts,
  })  : _contacts = contacts,
        super(key: key);

  final Future<List<User>> _contacts;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Iterable<User>>(
      future: _contacts,
      builder: (context, snapshot) {
        switch (snapshot.connectionState) {
          case ConnectionState.none:
            return Center(
              child: CircularProgressIndicator(),
            );
          case ConnectionState.active:
          case ConnectionState.waiting:
            return Center(
              child: CircularProgressIndicator(),
            );
          case ConnectionState.done:
            if (snapshot.hasError) {
              return Center(
                child: Text('Error: ${snapshot.error}'),
              );
            }
        }
        List<dynamic> data = [];
        data.addAll(snapshot.data!);
        data.add(ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8.0),
            child: Icon(
              Icons.share,
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
          title: Text(
            'Invite friends',
            style: TextStyle(
              fontSize: 18.0,
              fontWeight: FontWeight.bold,
            ),
          ),
          onTap: () {
            Share.share(ConfigStore().get('share_message'));
          },
        ));

        return ListView.builder(
          itemCount: data.length,
          itemBuilder: (context, i) {
            if (i > data.length - 2) {
              return data[i];
            }
            return ContactItem(
                user: data.elementAt(i),
                onProfileTap: () => {},
                onTap: (User user) async {
                  Navigator.of(context).pop(user);
                });
          },
        );
      },
    );
  }
}
