import 'package:vartalap/models/user.dart';
import 'package:vartalap/services/user_service.dart';
import 'package:flutter/material.dart';
import 'contact.dart';

class NewChatScreen extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => NewChatState();
}

class NewChatState extends State<NewChatScreen> {
  Future<List<User>> _contacts;
  int _numContacts;
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
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(bottom: 2.0),
              child: Text(
                'Select contact',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Container(
              child: _numContacts == null
                  ? null
                  : Text(
                      '$_numContacts contacts',
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
            onPressed: () {},
          ),
          PopupMenuButton(itemBuilder: (BuildContext cntx) {
            List<PopupMenuEntry<Object>> entries = [];
            entries.add(PopupMenuItem(
              child: GestureDetector(
                child: Text("Refresh"),
                onTap: () {
                  setState(() {
                    _contacts = UserService.getUsers(sync: true);
                  });
                },
              ),
            ));
            return entries;
          })
        ],
      ),
      body: FutureBuilder<Iterable<User>>(
        future: _contacts,
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
          List<dynamic> data = List<dynamic>();
          data.add(ListTile(
            leading: Container(
              decoration: BoxDecoration(
                //color: fabBgColor,
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.all(4.0),
              child: Icon(
                Icons.group,
                size: 32.0,
                color: Colors.white,
              ),
            ),
            title: Text('New group',
                style: TextStyle(
                  fontSize: 18.0,
                  fontWeight: FontWeight.bold,
                )),
            onTap: () {
              // Naviagate to new group screen
            },
          ));
          data.add(ListTile(
            leading: Container(
              decoration: BoxDecoration(
                //color: fabBgColor,
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.all(8.0),
              child: Icon(
                Icons.person_add,
                size: 24.0,
                color: Colors.white,
              ),
            ),
            title: Text('New contact',
                style: TextStyle(
                  fontSize: 18.0,
                  fontWeight: FontWeight.bold,
                )),
            onTap: () {
              //AndroidIntentHelpers.createContact(context);
            },
          ));
          data.addAll(snapshot.data);
          data.add(ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8.0),
              child: Icon(Icons.share),
            ),
            title: Text('Invite friends',
                style: TextStyle(
                  fontSize: 18.0,
                  fontWeight: FontWeight.bold,
                )),
            onTap: () {},
          ));
          data.add(ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8.0),
              child: Icon(Icons.help),
            ),
            title: Text('Contacts help',
                style: TextStyle(
                  fontSize: 18.0,
                  fontWeight: FontWeight.bold,
                )),
            onTap: () {
              // Application.router.navigateTo(
              //   context,
              //   Routes.contactsHelp,
              //   transition: TransitionType.inFromRight,
              // );
            },
          ));
          return ListView.builder(
              itemCount: data.length,
              itemBuilder: (context, i) {
                if (i < 2 || i > data.length - 3) {
                  return data[i];
                }
                return ContactItem(
                    user: data.elementAt(i),
                    onProfileTap: () =>
                        {}, // onTapProfileContactItem( context, snapshot.data.elementAt(i))
                    onTap: (User user) async {
                      Navigator.of(context).pop(user);
                    });
              });
        },
      ),
    );
  }
}
