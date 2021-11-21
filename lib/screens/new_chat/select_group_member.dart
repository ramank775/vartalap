import 'package:vartalap/models/chat.dart';
import 'package:vartalap/models/user.dart';
import 'package:vartalap/services/user_service.dart';
import 'package:flutter/material.dart';
import 'package:vartalap/widgets/contactPreviewItem.dart';
import 'package:vartalap/widgets/contact.dart';

class SelectGroupMemberScreen extends StatefulWidget {
  final Chat? chat;
  SelectGroupMemberScreen({this.chat});
  @override
  State<StatefulWidget> createState() => SelectGroupMemberState();
}

class SelectGroupMemberState extends State<SelectGroupMemberScreen> {
  late Future<List<User>> _contacts;
  late int _numContacts;
  bool _openSearch = false;
  List<User> _selectedUsers = [];
  Map<String, User> _existingUser = Map();
  bool _isUpdate = false;
  @override
  void initState() {
    super.initState();
    if (this.widget.chat != null) {
      this._isUpdate = true;
      this
          .widget
          .chat!
          .users
          .forEach((u) => this._existingUser[u.username] = u);
    }
    _contacts = UserService.getUsers();
    _contacts.then((value) {
      setState(() {
        _numContacts = value.length;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return new Scaffold(
      appBar: this._openSearch ? buildSearchAppBar() : buildAppBar(),
      body: Column(
        children: [
          ...(this._selectedUsers.length > 0
              ? [
                  SizedBox(
                    height: 90,
                    child: ListView.separated(
                      padding: EdgeInsets.only(top: 10, left: 20),
                      scrollDirection: Axis.horizontal,
                      shrinkWrap: true,
                      reverse: true,
                      itemCount: this._selectedUsers.length,
                      separatorBuilder: (context, index) => SizedBox(
                        width: 10,
                      ),
                      itemBuilder: (context, index) {
                        return ContactPreviewItem(user: _selectedUsers[index]);
                      },
                    ),
                  ),
                  Divider(
                    thickness: 2,
                  ),
                ]
              : []),
          Flexible(
            child: FutureBuilder<Iterable<User>>(
              future: _contacts,
              builder: (context, snapshot) {
                switch (snapshot.connectionState) {
                  case ConnectionState.none:
                    return Center(
                      child: CircularProgressIndicator(
                        valueColor:
                            new AlwaysStoppedAnimation<Color>(Colors.grey),
                      ),
                    );
                  case ConnectionState.active:
                  case ConnectionState.waiting:
                    return Center(
                      child: CircularProgressIndicator(
                        valueColor:
                            new AlwaysStoppedAnimation<Color>(Colors.grey),
                      ),
                    );
                  case ConnectionState.done:
                    if (snapshot.hasError) {
                      return Center(
                        child: Text('Error: ${snapshot.error}'),
                      );
                    }
                }
                List<dynamic> data = snapshot.data!.toList();
                return ListView.builder(
                  itemCount: data.length,
                  itemBuilder: (context, i) {
                    User user = data.elementAt(i);
                    return ContactItem(
                      user: user,
                      isSelected: this._selectedUsers.contains(user),
                      enabled: !this._existingUser.containsKey(user.username),
                      onProfileTap: () => {},
                      onTap: (User user) async {
                        if (this._existingUser.containsKey(user.username))
                          return;
                        setState(() {
                          if (!this._selectedUsers.remove(user)) {
                            this._selectedUsers.add(user);
                          }
                        });
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: this._selectedUsers.length > 0
          ? FloatingActionButton(
              onPressed: () async {
                if (this._isUpdate) {
                  return Navigator.of(context).pop(_selectedUsers);
                }
                var chat = await Navigator.of(context)
                    .pushNamed('/create-group', arguments: _selectedUsers);
                if (chat is Chat) {
                  Navigator.of(context).popAndPushNamed(
                    '/chat',
                    arguments: chat,
                  );
                }
              },
              tooltip: 'Next',
              child: Icon(this._isUpdate ? Icons.check : Icons.arrow_forward),
            )
          : null,
    );
  }

  AppBar buildAppBar() {
    return AppBar(
      title: Column(
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(bottom: 2.0),
            child: Text(
              'Select members',
              style: TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          _selectedUsers.isEmpty
              ? Container()
              : Container(
                  child: Text(
                    '${_selectedUsers.length} of $_numContacts',
                    style: TextStyle(
                      fontSize: 12.0,
                    ),
                  ),
                )
        ],
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
      ],
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
          });
        },
        child: Icon(
          Icons.arrow_back,
          size: 24.0,
          color: Colors.white,
        ),
      ),
      titleSpacing: 0,
      automaticallyImplyLeading: false,
      title: TextField(
        style: TextStyle(
          fontSize: 20.0,
          color: Colors.white,
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: "Search",
          hintStyle: TextStyle(
            fontSize: 20.0,
            color: Colors.white,
          ),
        ),
        maxLines: 1,
        autofocus: true,
        onChanged: (value) {
          setState(() {
            this._contacts = UserService.getUsers(search: value);
          });
        },
      ),
      actions: [],
    );
  }
}
