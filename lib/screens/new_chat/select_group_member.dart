import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vartalap/widgets/contact_preview_item.dart';
import 'package:vartalap/widgets/contact.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';

class SelectGroupMemberScreen extends StatefulWidget {
  final ChannelModel? channel;
  const SelectGroupMemberScreen({super.key, this.channel});
  @override
  State<StatefulWidget> createState() => SelectGroupMemberState();
}

class SelectGroupMemberState extends State<SelectGroupMemberScreen> {
  late final VartalapChatClientFlutter client;
  late Selectable<Contact> _contacts;
  late int _numContacts;
  bool _openSearch = false;
  final List<Contact> _selectedContacts = [];
  final Set<int> _existingUser = {};
  final bool _isUpdate = false;
  @override
  void initState() {
    super.initState();
    // if (this.widget.channel != null) {
    //   this._isUpdate = true;
    //   this
    //       .widget
    //       .channel!
    //       .members
    //       .forEach((member) => this._existingUser.add(member.user.id));
    // }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    client = context.read<VartalapChatClientFlutter>();
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
    return Scaffold(
      appBar: _openSearch ? buildSearchAppBar() : buildAppBar(),
      body: Column(
        children: [
          ...(_selectedContacts.isNotEmpty
              ? [
                  SizedBox(
                    height: 90,
                    child: ListView.separated(
                      padding: EdgeInsets.only(top: 10, left: 20),
                      scrollDirection: Axis.horizontal,
                      shrinkWrap: true,
                      reverse: true,
                      itemCount: _selectedContacts.length,
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
                if (snapshot.connectionState == ConnectionState.none ||
                    (snapshot.connectionState == ConnectionState.waiting &&
                        !snapshot.hasData)) {
                  return Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.grey),
                    ),
                  );
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Error: ${snapshot.error}'),
                  );
                }
                List<dynamic> data = snapshot.data!.toList();
                return ListView.builder(
                  itemCount: data.length,
                  itemBuilder: (context, i) {
                    Contact contact = data.elementAt(i);
                    return ContactItem(
                      contact: contact,
                      isSelected: _selectedContacts.contains(contact),
                      enabled: !_existingUser.contains(contact.id),
                      onProfileTap: () => {},
                      onTap: (Contact contact) async {
                        if (_existingUser.contains(contact.id)) return;
                        setState(() {
                          if (!_selectedContacts.remove(contact)) {
                            _selectedContacts.add(contact);
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
      floatingActionButton: _selectedContacts.isNotEmpty
          ? FloatingActionButton(
              onPressed: () async {
                if (_isUpdate) {
                  return Navigator.of(context).pop(_selectedContacts);
                }
                final result = await Navigator.of(context)
                    .pushNamed('/create-group', arguments: _selectedContacts);
                if (result != null && mounted) {
                  Navigator.of(context).pop(result);
                }
              },
              tooltip: 'Next',
              child: Icon(_isUpdate ? Icons.check : Icons.arrow_forward),
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
              : Text(
                  '${_selectedContacts.length} of $_numContacts',
                  style: TextStyle(
                    fontSize: 12.0,
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
              _openSearch = true;
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
            _openSearch = false;
            _contacts = client.getContacts(
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
            _contacts = client.getContacts(
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
