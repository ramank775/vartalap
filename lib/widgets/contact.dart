import 'package:flutter/material.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/avator.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';

class ContactItem extends StatelessWidget {
  final Contact contact;
  final Function? onProfileTap;
  final Function? onTap;
  final bool isSelected;
  final bool enabled;
  ContactItem({
    required this.contact,
    this.isSelected = false,
    this.onProfileTap,
    this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final vtheme = VartalapTheme.theme;
    return ListTileTheme(
      selectedColor: vtheme.selectedRowColor,
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
                text: contact.displayName,
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
          contact.displayName,
          maxLines: 1,
          style: TextStyle(
            fontSize: 18.0,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          contact.username ?? '',
          maxLines: 1,
        ),
        onTap: () {
          if (onTap != null) {
            onTap!(contact);
          }
        },
        selected: isSelected,
        enabled: enabled,
      ),
    );
  }
}
