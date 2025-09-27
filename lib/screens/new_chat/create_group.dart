import 'package:flutter/material.dart';
import 'package:vartalap/widgets/Inherited/vartalap_client_provider.dart';
import 'package:vartalap/widgets/avator.dart';
import 'package:vartalap/widgets/contactPreviewItem.dart';
import 'package:vartalap/widgets/loadingIndicator.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';

class CreateGroup extends StatelessWidget {
  final List<Contact> _members;
  CreateGroup(this._members);
  @override
  Widget build(BuildContext context) {
    final client = VartalapClientProvider.of(context).client;
    onGroupNameConfirm(String name) async {
      if (name.isNotEmpty) {
        try {
          showLoadingIndicator(context);
          final channelMembers = this
              ._members
              .map((contact) => Member(
                    user: contact,
                    role: 'member',
                    since: DateTime.now(),
                  ))
              .toList();
          ChannelModel channel = ChannelModel(
            id: 0, // ID will be assigned by the server
            type: ChannelType.group,
            config: null,
          );
          await client.createChannel(channel, channelMembers);

          Navigator.of(context).pop();
          Navigator.of(context).pop();
        } on Exception catch (_) {
          showErrorDialog(context, [
            'Error while creating new group.',
            'Make sure you are connected to internet.'
          ]);
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
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
          ],
        ),
      ),
      body: SafeArea(
        child: Container(
          margin: EdgeInsets.only(left: 20, top: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                child: _CreateGroupForm(
                  onConfirm: onGroupNameConfirm,
                ),
              ),
              Container(
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(
                      fontSize: 18,
                      color: Theme.of(context).textTheme.bodyLarge!.color,
                    ),
                    children: [
                      TextSpan(text: "Members:"),
                      TextSpan(
                        text: _members.length.toString(),
                      )
                    ],
                  ),
                ),
              ),
              Expanded(
                flex: 10,
                child: GridView.count(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  crossAxisCount: 5,
                  childAspectRatio: 0.5,
                  children: _members
                      .map((e) => ContactPreviewItem(contact: e))
                      .toList(),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  void showLoadingIndicator(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            content: LoadingIndicator(
              text: "While we are creating group for you.",
            ),
          ),
        );
      },
    );
  }

  void showErrorDialog(BuildContext context, List<String> error) {
    var dialog = AlertDialog(
      title: Text('Error'),
      content: SingleChildScrollView(
        child: ListBody(
          children: error.map((err) => Text(err)).toList(),
        ),
      ),
      actions: [
        TextButton(
          child: Text('OK'),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
      ],
    );
    showDialog(
      context: context,
      builder: (context) => dialog,
    );
  }
}

class _CreateGroupForm extends StatefulWidget {
  final Function(String) onConfirm;
  _CreateGroupForm({Key? key, required this.onConfirm}) : super(key: key);

  @override
  __CreateGroupFormState createState() => __CreateGroupFormState();
}

class __CreateGroupFormState extends State<_CreateGroupForm> {
  String value = "";
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.rectangle,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ListTile(
            leading: Avator(
              width: 55,
              height: 55,
              text: value.isEmpty ? "Group Icon" : value,
            ),
            title: Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: TextField(
                maxLines: 1,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                style: TextStyle(
                  fontSize: 18,
                ),
                onChanged: (val) {
                  setState(() {
                    this.value = val;
                  });
                },
              ),
            ),
            subtitle: Container(),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () async {
                    if (value.isNotEmpty) {
                      this.widget.onConfirm(value);
                    } else {
                      final snackBar = SnackBar(
                          content: Text('Group name can\'t be empty!'));
                      ScaffoldMessenger.of(context).showSnackBar(snackBar);
                    }
                  },
                  style: TextButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    shape: const CircleBorder(side: BorderSide.none),
                  ),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                    child: Icon(
                      Icons.done,
                      //color: Colors.white,
                      size: 30,
                    ),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
