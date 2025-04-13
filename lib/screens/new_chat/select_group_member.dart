import 'package:flutter/material.dart';
import 'package:vartalap/widgets/Inherited/vartalap_client_provider.dart';
import 'package:vartalap/widgets/contactPreviewItem.dart';
import 'package:vartalap/widgets/contact.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';

class SelectGroupMemberScreen extends StatefulWidget {
  final Channel? channel;
  SelectGroupMemberScreen({this.channel});
  @override
  State<StatefulWidget> createState() => SelectGroupMemberState();
}

class SelectGroupMemberState extends State<SelectGroupMemberScreen> {
  late final client = VartalapClientProvider.of(context).client;
  late Selectable<Contact> _contacts;
  late int _numContacts;
  bool _openSearch = false;
  List<Contact> _selectedContacts = [];
  Set<int> _existingUser = Set();
  bool _isUpdate = false;
  @override
  void initState() {
    super.initState();
    if (this.widget.channel != null) {
      this._isUpdate = true;
      this
          .widget
          .channel!
          .members
          .forEach((member) => this._existingUser.add(member.user.id!));
    }
    _contacts = client.getContacts(
      filter: ContactFilter(
        status: ContactStatus.active,
      ),
    );
    _contacts.get().then((value) {
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
          ...(this._selectedContacts.length > 0
              ? [
                  SizedBox(
                    height: 90,
                    child: ListView.separated(
                      padding: EdgeInsets.only(top: 10, left: 20),
                      scrollDirection: Axis.horizontal,
                      shrinkWrap: true,
                      reverse: true,
                      itemCount: this._selectedContacts.length,
                      separatorBuilder: (context, index) => SizedBox(
                        width: 10,
                      ),
                      itemBuilder: (context, index) {
                        return ContactPreviewItem(
                            contact: _selectedContacts[index]);
                      },
                    ),
                  ),
                  Divider(
                    thickness: 2,
                  ),
                ]
              : []),
          Flexible(
            child: StreamBuilder<List<Contact>>(
              stream: _contacts.watch(),
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
                    Contact contact = data.elementAt(i);
                    return ContactItem(
                      contact: contact,
                      isSelected: this._selectedContacts.contains(contact),
                      enabled: !this._existingUser.contains(contact.id!),
                      onProfileTap: () => {},
                      onTap: (Contact contact) async {
                        if (this._existingUser.contains(contact.id!)) return;
                        setState(() {
                          if (!this._selectedContacts.remove(contact)) {
                            this._selectedContacts.add(contact);
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
      floatingActionButton: this._selectedContacts.length > 0
          ? FloatingActionButton(
              onPressed: () async {
                if (this._isUpdate) {
                  return Navigator.of(context).pop(_selectedContacts);
                }
                await Navigator.of(context)
                    .pushNamed('/create-group', arguments: _selectedContacts);
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
          _selectedContacts.isEmpty
              ? Container()
              : Container(
                  child: Text(
                    '${_selectedContacts.length} of $_numContacts',
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
            this._contacts = client.getContacts(
              filter: ContactFilter(
                status: ContactStatus.active,
              ),
            );
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
            this._contacts = client.getContacts(
              filter: ContactFilter(
                status: ContactStatus.active,
                name: value,
              ),
            );
          });
        },
      ),
      actions: [],
    );
  }
}
