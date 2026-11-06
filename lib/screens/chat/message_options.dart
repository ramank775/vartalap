/// Decision 222's message features, the parts of the chat screen that are
/// dialogs and sheets: delete for me / for everyone.
library vartalap.screens.chat.message_options;

import 'package:flutter/material.dart';

/// What the user picked in [confirmDeleteMessages].
enum DeleteChoice { forMe, forEveryone }

/// WhatsApp's "Delete message?": "Delete for everyone" only when
/// [forEveryone] (every selected message is the user's own and young
/// enough, decision 222), "Delete for me" always. Null on Cancel.
Future<DeleteChoice?> confirmDeleteMessages(
  BuildContext context, {
  required int count,
  required bool forEveryone,
}) =>
    showDialog<DeleteChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        content:
            Text(count == 1 ? 'Delete message?' : 'Delete $count messages?'),
        actions: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (forEveryone)
                TextButton(
                  onPressed: () =>
                      Navigator.of(ctx).pop(DeleteChoice.forEveryone),
                  child: const Text('Delete for everyone'),
                ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(DeleteChoice.forMe),
                child: const Text('Delete for me'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ),
    );
