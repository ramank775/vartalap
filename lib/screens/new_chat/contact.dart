import 'package:flutter/material.dart';

class Contact {
  String displayName;
}

class ContactItem extends StatelessWidget {
  final Contact contact;
  final String searchKeyword;
  final Function onProfileTap;
  final Function onTap;

  ContactItem(
      {this.contact, this.searchKeyword, this.onProfileTap, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.symmetric(vertical: 2.0, horizontal: 16.0),
      leading: SizedBox(
        width: 45.0,
        height: 45.0,
        child: IconButton(
            padding: const EdgeInsets.all(0.0),
            icon: Icon(
              Icons.account_circle,
              size: 45.0,
            ),
            color: Colors.blueGrey,
            onPressed: onProfileTap),
      ),
      title: Text(
              contact.displayName,
              maxLines: 1,
              style: TextStyle(
                fontSize: 18.0,
                fontWeight: FontWeight.bold,
              ),
            ),
      // title: searchKeyword == null || searchKeyword.isEmpty
      //     ? Text(
      //         contact.displayName,
      //         maxLines: 1,
      //         style: TextStyle(
      //           fontSize: 18.0,
      //           fontWeight: FontWeight.bold,
      //         ),
      //       )
          // : TextHelpers.getHighlightedText(
          //     contact.displayName,
          //     searchKeyword,
          //     TextStyle(
          //       fontSize: 18.0,
          //       fontWeight: FontWeight.bold,
          //       color: Colors.black,
          //     ),
          //     TextStyle(
          //       fontSize: 18.0,
          //       fontWeight: FontWeight.bold,
          //       color: Colors.blue,
          //     )),
//      subtitle: Text(
//        _contact.displayName.lastMessage.content,
//        maxLines: 1,
//      ),
      onTap: onTap,
    );
  }
}
