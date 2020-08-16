import 'package:vartalap/models/user.dart';
import 'package:flutter/material.dart';

class ContactItem extends StatelessWidget {
  final User user;
  final Function onProfileTap;
  final Function onTap;

  ContactItem({this.user, this.onProfileTap, this.onTap});

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
        user.name,
        maxLines: 1,
        style: TextStyle(
          fontSize: 18.0,
          fontWeight: FontWeight.bold,
        ),
      ),
      subtitle: Text(
        user.username,
        maxLines: 1,
      ),
      onTap: () => onTap(user),
    );
  }
}
