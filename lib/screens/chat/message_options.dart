/// Decision 222's message features, the parts of the chat screen that are
/// dialogs and sheets: delete for me / for everyone, edit history.
library vartalap.screens.chat.message_options;

import 'package:flutter/material.dart';
import 'package:vartalap_store/vartalap_store.dart';

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

/// Decision 222: an edited message's versions, newest first, each with
/// when it was written. Opened from the bubble's "edited".
Future<void> showEditHistory(
  BuildContext context,
  Future<List<MessageVersion>> versions,
) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        String when(int ms) {
          final t = DateTime.fromMillisecondsSinceEpoch(ms);
          return '${MaterialLocalizations.of(ctx).formatMediumDate(t)}, '
              '${TimeOfDay.fromDateTime(t).format(ctx)}';
        }

        return SafeArea(
          child: ConstrainedBox(
            constraints:
                BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
            child: FutureBuilder<List<MessageVersion>>(
              future: versions,
              builder: (ctx, snap) {
                final list = snap.data ?? const <MessageVersion>[];
                return ListView(
                  shrinkWrap: true,
                  children: [
                    ListTile(
                      title: Text('Edit history',
                          style: Theme.of(ctx).textTheme.titleLarge),
                    ),
                    for (final (i, v) in list.indexed)
                      ListTile(
                        title: Text(v.body ?? ''),
                        subtitle: Text(
                          '${i == 0 ? 'Current' : i == list.length - 1 ? 'Original' : 'Earlier'}'
                          ' · ${when(v.atMs)}',
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
