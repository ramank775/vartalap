import 'package:flutter/material.dart';
import 'package:vartalap/widgets/contact.dart';
import 'package:vartalap/screens/new_chat/select_group_member.dart';
import 'package:vartalap/widgets/avator.dart';
import 'package:vartalap/widgets/loadingIndicator.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';

class ChatInfo extends StatelessWidget {
  final ChatClient chat;

  const ChatInfo(this.chat, {Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 80,
              color: Theme.of(context).appBarTheme.backgroundColor,
              child: ListTile(
                leading: CircleAvatar(
                  radius: 30,
                  foregroundImage: null,
                  child: Avator(
                    height: 50,
                    width: 50,
                    text: chat.displayName,
                  ),
                ),
                title: Text(
                  chat.displayName,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                // subtitle: Text(
                //   "${users.length} members",
                //   style: TextStyle(
                //     color: Colors.white,
                //     fontSize: 14,
                //     fontWeight: FontWeight.w500,
                //   ),
                // ),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  Card(
                    elevation: 5,
                    child: TextButton(
                      child: ListTile(
                        leading: Icon(
                          Icons.group_add,
                          size: 30,
                        ),
                        title: Text(
                          "Add members",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      onPressed: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(builder: (context) {
                            return SelectGroupMemberScreen(
                              channel: chat.channel,
                            );
                          }),
                        );
                      },
                    ),
                  ),
                  Card(
                    elevation: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: MediaQuery.of(context).size.width,
                          margin: EdgeInsets.only(left: 25, top: 10, bottom: 5),
                          child: Text(
                            "Members",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              //color: Theme.of(context).primaryColor,
                            ),
                            textAlign: TextAlign.left,
                          ),
                        ),
                        Divider(
                          thickness: 2,
                        ),
                        StreamBuilder(
                            stream: chat.membersStream,
                            builder: (context, snapshot) {
                              if (snapshot.hasData) {
                                final users = snapshot.data!;
                                return Column(
                                  children: users
                                      .map((u) => ContactItem(contact: u.user))
                                      .toList(),
                                );
                              } else if (snapshot.hasError) {
                                return Center(
                                  child: Text("Error loading members"),
                                );
                              } else {
                                return Center(
                                  child: CircularProgressIndicator(),
                                );
                              }
                            }),
                      ],
                    ),
                  ),
                  Card(
                    elevation: 5,
                    child: TextButton(
                      child: ListTile(
                        leading: Icon(
                          Icons.exit_to_app_outlined,
                          color: Colors.red,
                        ),
                        title: Text(
                          "Exit group",
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      onPressed: () async {
                        showConfirmationDialog(context, onsuccess: () async {
                          try {
                            showLoadingIndicator(context,
                                "While we inform other members about your farewell!!");
                            await chat.removeMember(self: true);

                            Navigator.of(context)
                                .pop(); // Close the loading indicator
                            Navigator.of(context).pop();
                          } catch (err) {
                            Navigator.of(context).pop();
                            showErrorDialog(context, [
                              'Sorry, something wents wrong.',
                              'Make sure you are connected to internet and try again.'
                            ]);
                          }
                        });
                      },
                    ),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  void showConfirmationDialog(BuildContext context,
      {void Function()? onsuccess}) {
    // set up the buttons
    Widget cancelButton = TextButton(
      child: Text("Cancel"),
      onPressed: () {
        Navigator.of(context).pop();
      },
    );
    Widget continueButton = TextButton(
      child: Text("Continue"),
      onPressed: () {
        Navigator.of(context).pop();
        onsuccess!();
      },
    );
    // set up the AlertDialog
    AlertDialog alert = AlertDialog(
      title: Text("Exit group"),
      content: Text("Are you sure you want to exit this group?"),
      actions: [
        cancelButton,
        continueButton,
      ],
    );
    // show the dialog
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return alert;
      },
    );
  }

  void showLoadingIndicator(BuildContext context, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            content: LoadingIndicator(
              text: message,
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
