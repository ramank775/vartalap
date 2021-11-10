import 'package:flutter/material.dart';
import 'package:vartalap/models/user.dart';

import 'avator.dart';

class ContactPreviewItem extends StatelessWidget {
  const ContactPreviewItem({
    Key? key,
    required User user,
  })   : _user = user,
        super(key: key);

  final User _user;

  @override
  Widget build(BuildContext context) {
    return Container(
      child: Column(
        children: [
          Avator(
            height: 45,
            width: 45,
            text: _user.name,
          ),
          SizedBox(
            height: 2,
          ),
          SizedBox(
            width: 60,
            child: Text(
              _user.name,
              maxLines: 2,
              textAlign: TextAlign.center,
              softWrap: true,
              overflow: TextOverflow.fade,
            ),
          )
        ],
      ),
    );
  }
}
