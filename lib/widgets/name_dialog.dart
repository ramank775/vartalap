/// One text field in a dialog: a group's name, a contact's saved name.
/// Pops the trimmed text, or null on Cancel.
library vartalap.widgets.name_dialog;

import 'package:flutter/material.dart';

/// Owns its controller, so the closing animation never sees it
/// disposed (the dialog outlives the `showDialog` future).
class NameDialog extends StatefulWidget {
  final String title;
  final String initial;
  final int maxLength;
  final String? hint;

  const NameDialog({
    super.key,
    required this.title,
    this.initial = '',
    this.maxLength = 100,
    this.hint,
  });

  @override
  State<NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<NameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
          controller: _controller,
          autofocus: true,
          maxLength: widget.maxLength,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(hintText: widget.hint),
          onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      );
}
