import 'package:vartalap/models/user.dart';
import 'package:flutter/material.dart';
import 'package:vartalap/widgets/avator.dart';

class ContactItem extends StatelessWidget {
  final User user;
  final Function onProfileTap;
  final Function onTap;
  final bool isSelected;
  ContactItem(
      {this.user, this.isSelected = false, this.onProfileTap, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.symmetric(vertical: 2.0, horizontal: 16.0),
      leading: Container(
        width: 45,
        height: 45,
        child: Stack(
          children: [
            Avator(
              width: 45.0,
              height: 45.0,
              text: user.name,
            ),
            this.isSelected
                ? Positioned(
                    bottom: 0,
                    right: 0,
                    child: CircleAvatar(
                      backgroundColor: Theme.of(context).primaryColor,
                      radius: 10,
                      child: Icon(
                        Icons.check,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  )
                : Container()
          ],
        ),
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
      onTap: () {
        if (onTap != null) onTap(user);
      },
      selected: isSelected,
    );
  }
}
