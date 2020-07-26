import 'package:flutter/material.dart';
import 'contact.dart';

Contact _testContact = new Contact();

List<Contact> _contactList = [_testContact, _testContact, _testContact];

class NewChat extends StatelessWidget {
  final Future<List<Contact>> _contacts = new Future(() => _contactList);

  @override
  Widget build(BuildContext context) {
    _testContact.displayName = "Raman Kumar";
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
            // Container(
            //   child: numContacts == null
            //    ? null
            //   : Text(
            //       '$numContacts contacts',
            //     style: TextStyle(
            //       fontSize: 12.0,
            //     ),
            //   ),
            // )
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Search',
            icon: Icon(Icons.search),
            onPressed: () {},
          ),
          // PopupMenuButton<NewChatOptions>(
          //   tooltip: "More options",
          //   onSelected: _onSelectOption,
          //   itemBuilder: (BuildContext context) {
          //     return [
          //       PopupMenuItem<NewChatOptions>(
          //         child: Text("Invite a friend"),
          //         value: NewChatOptions.inviteAFriend,
          //       ),
          //       PopupMenuItem<NewChatOptions>(
          //         child: Text("Contacts"),
          //         value: NewChatOptions.contacts,
          //       ),
          //       PopupMenuItem(
          //         child: Text("Refresh"),
          //         value: NewChatOptions.refresh,
          //       ),
          //       PopupMenuItem(
          //         child: Text("Help"),
          //         value: NewChatOptions.help,
          //       ),
          //     ];
          //   },
          // ),
        ],
      ),
      body: FutureBuilder<Iterable<Contact>>(
        future: _contacts,
        builder: (context, snapshot) {
          // switch (snapshot.connectionState) {
          //   case ConnectionState.none:
          //     return Center(
          //       child: CircularProgressIndicator(
          //         valueColor: new AlwaysStoppedAnimation<Color>(Colors.grey),
          //       ),
          //     );
          //   case ConnectionState.active:
          //   case ConnectionState.waiting:
          //     return Center(
          //       child: CircularProgressIndicator(
          //         valueColor: new AlwaysStoppedAnimation<Color>(Colors.grey),
          //       ),
          //     );
          //   case ConnectionState.done:
          //     if (snapshot.hasError) {
          //       return Center(
          //         child: Text('Error: ${snapshot.error}'),
          //       );
          //     }
          //     List<dynamic> data = List<dynamic>();
          //     data.add(ListTile(
          //       leading: Container(
          //         decoration: BoxDecoration(
          //           //color: fabBgColor,
          //           borderRadius: BorderRadius.circular(20),
          //         ),
          //         padding: const EdgeInsets.all(4.0),
          //         child: Icon(
          //           Icons.group,
          //           size: 32.0,
          //           color: Colors.white,
          //         ),
          //       ),
          //       title: Text('New group',
          //           style: TextStyle(
          //             fontSize: 18.0,
          //             fontWeight: FontWeight.bold,
          //           )),
          //       onTap: () {
          //         // Application.router.navigateTo(
          //         //   context,
          //         //   //Routes.newChatGroup,
          //         //   Routes.futureTodo,
          //         //   transition: TransitionType.inFromRight,
          //         // );
          //       },
          //     ));
          //     data.add(ListTile(
          //       leading: Container(
          //         decoration: BoxDecoration(
          //           //color: fabBgColor,
          //           borderRadius: BorderRadius.circular(20),
          //         ),
          //         padding: const EdgeInsets.all(8.0),
          //         child: Icon(
          //           Icons.person_add,
          //           size: 24.0,
          //           color: Colors.white,
          //         ),
          //       ),
          //       title: Text('New contact',
          //           style: TextStyle(
          //             fontSize: 18.0,
          //             fontWeight: FontWeight.bold,
          //           )),
          //       onTap: () {
          //         //AndroidIntentHelpers.createContact(context);
          //       },
          //     ));
          //     data.addAll(snapshot.data);
          //     data.add(ListTile(
          //       leading: Container(
          //         padding: const EdgeInsets.all(8.0),
          //         child: Icon(Icons.share),
          //       ),
          //       title: Text('Invite friends',
          //           style: TextStyle(
          //             fontSize: 18.0,
          //             fontWeight: FontWeight.bold,
          //           )),
          //       onTap: () {
          //         //AndroidIntentHelpers.inviteFriend(context);
          //       },
          //     ));
          //     data.add(ListTile(
          //       leading: Container(
          //         padding: const EdgeInsets.all(8.0),
          //         child: Icon(Icons.help),
          //       ),
          //       title: Text('Contacts help',
          //           style: TextStyle(
          //             fontSize: 18.0,
          //             fontWeight: FontWeight.bold,
          //           )),
          //       onTap: () {
          //         // Application.router.navigateTo(
          //         //   context,
          //         //   Routes.contactsHelp,
          //         //   transition: TransitionType.inFromRight,
          //         // );
          //       },
          //     ));
          //     return ListView.builder(
          //         itemCount: data.length,
          //         itemBuilder: (context, i) {
          //           if (i < 2 || i > data.length - 3) {
          //             return data[i];
          //           }
          //           return ContactItem(
          //               contact: data.elementAt(i),
          //               onProfileTap: () =>
          //                   {}, // onTapProfileContactItem( context, snapshot.data.elementAt(i))
          //               onTap: () {});
          //         });
          // }
          // return null; // unreachable
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
              // Application.router.navigateTo(
              //   context,
              //   //Routes.newChatGroup,
              //   Routes.futureTodo,
              //   transition: TransitionType.inFromRight,
              // );
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
          //data.addAll(snapshot.data);
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
            onTap: () {
              //AndroidIntentHelpers.inviteFriend(context);
            },
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
                    contact: data.elementAt(i),
                    onProfileTap: () =>
                        {}, // onTapProfileContactItem( context, snapshot.data.elementAt(i))
                    onTap: () {});
              });
        },
      ),
    );
  }
}
