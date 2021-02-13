import 'package:vartalap/models/chat.dart';
import 'package:vartalap/models/user.dart';
import 'package:vartalap/services/user_service.dart';
import 'package:flutter/material.dart';
import 'package:vartalap/widgets/contactPreviewItem.dart';
import 'contact.dart';

class NewGroupChatScreen extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => NewGroupChatState();
}

class NewGroupChatState extends State<NewGroupChatScreen> {
  Future<List<User>> _contacts;
  int _numContacts;
  bool _openSearch = false;
  List<User> _selectedUsers = [];

  @override
  void initState() {
    super.initState();
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
          this._selectedUsers.length > 0
              ? SizedBox(
                  height: this._selectedUsers.length == 0 ? 0 : 90,
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
                )
              : Container(),
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
                List<dynamic> data = snapshot.data.toList();
                return ListView.builder(
                  itemCount: data.length,
                  itemBuilder: (context, i) {
                    return ContactItem(
                      user: data.elementAt(i),
                      isSelected:
                          this._selectedUsers.contains(data.elementAt(i)),
                      onProfileTap: () =>
                          {}, // onTapProfileContactItem( context, snapshot.data.elementAt(i))
                      onTap: (User user) async {
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
              child: Icon(Icons.arrow_forward),
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
              'New Group',
              style: TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Container(
            child: Text(
              _selectedUsers.isEmpty
                  ? 'Add members'
                  : '${_selectedUsers.length} of $_numContacts',
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
      leading: FlatButton(
        shape: CircleBorder(),
        padding: const EdgeInsets.only(left: 1.0),
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
          color: Colors.white,
          fontSize: 20.0,
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: "Search",
          hintStyle: TextStyle(
            color: Colors.white,
            fontSize: 20.0,
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
