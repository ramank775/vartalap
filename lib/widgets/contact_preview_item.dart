import 'package:flutter/material.dart';
import 'package:vartalap/widgets/avator.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';

class ContactPreviewItem extends StatelessWidget {
  const ContactPreviewItem({
    super.key,
    required this.contact,
  });

  final Contact contact;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Avator(
          height: 45,
          width: 45,
          text: contact.displayName,
        ),
        SizedBox(
          height: 2,
        ),
        SizedBox(
          width: 60,
          child: Text(
            contact.displayName,
            maxLines: 2,
            textAlign: TextAlign.center,
            softWrap: true,
            overflow: TextOverflow.fade,
          ),
        )
      ],
    );
  }
}
