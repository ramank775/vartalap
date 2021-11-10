import 'package:vartalap/models/user.dart';
import 'package:flutter/material.dart';
import 'package:vartalap/widgets/avator.dart';

class ContactItem extends StatelessWidget {
  final User user;
  final Function? onProfileTap;
  final Function? onTap;
  final bool isSelected;
  final bool enabled;
  ContactItem({
    required this.user,
    this.isSelected = false,
    this.onProfileTap,
    this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return ListTileTheme(
      selectedColor: Theme.of(context).selectedRowColor,
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(
          vertical: 2.0,
          horizontal: 16.0,
        ),
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
                          size: 15,
                          color: Colors.white,
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
          onTap!(user);
        },
        selected: isSelected,
        enabled: enabled,
      ),
    );
  }
}
