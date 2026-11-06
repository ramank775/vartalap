/// Decision 222's message features, the parts of the chat screen that are
/// dialogs and sheets: delete for me / for everyone, edit history, the
/// message timer.
library vartalap.screens.chat.message_options;

import 'package:flutter/material.dart';
import 'package:vartalap/services/chat_service.dart' show kMessageTimers;
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

/// Decision 222: the composer's message timer. The pick, in seconds (0
/// is Off), or null when dismissed.
Future<int?> pickMessageTimer(BuildContext context, int current) =>
    showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: SingleChildScrollView(
              child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                title: Text('Message timer',
                    style: Theme.of(ctx).textTheme.titleMedium),
                subtitle: const Text('The message disappears from both '
                    'phones this long after it is sent.'),
              ),
              // Radio glyphs on plain tiles, as in the mute sheet.
              for (final MapEntry(key: sec, value: label)
                  in kMessageTimers.entries)
                ListTile(
                  leading: Icon(
                    sec == current
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: sec == current ? scheme.primary : null,
                  ),
                  title: Text(label),
                  onTap: () => Navigator.of(ctx).pop(sec),
                ),
            ],
          )),
        );
      },
    );
