/// The two bottom sheets that own a chat's local-only settings:
/// the long-press sheet (frame a2) and the mute sheet (frame f).
///
/// Everything these sheets do is device-local — pin, mute, clear
/// history and delete chat never touch the server (V3_ARCHITECTURE
/// decision 3 offline matrix). That is why they apply immediately and
/// nothing here can fail or asks for a connection. The one action that
/// *is* a server op, "Leave group", deliberately lives elsewhere — in
/// group info, in error red, behind a confirm.
library vartalap.widgets.chat_action_sheets;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/avator.dart';
import 'package:vartalap_store/vartalap_store.dart';

/// Human-readable form of a `muted_until_ms`, for the sheet subtitle
/// and the group-info mute bar. Null when the channel isn't muted.
String? muteLabel(int? untilMs, {DateTime? now}) {
  if (untilMs == null) return null;
  if (untilMs >= kMuteAlways) return 'Always';
  final until = DateTime.fromMillisecondsSinceEpoch(untilMs);
  final current = now ?? DateTime.now();
  if (!until.isAfter(current)) return null;
  final sameDay = until.year == current.year &&
      until.month == current.month &&
      until.day == current.day;
  return sameDay
      ? 'Muted until ${DateFormat.jm().format(until)} today'
      : 'Muted until ${DateFormat.MMMEd().format(until)}';
}

/// Frame a2 — the long-press sheet. Mute, pin, clear history, delete
/// chat, with the destructive pair last and a one-line consequence on
/// each, so the thing "Delete chat" does *not* do is stated where the
/// mistake would be made rather than in a dialog nobody reads.
Future<void> showChatActionsSheet({
  required BuildContext context,
  required ChatService chatService,
  required ChannelListEntry entry,
  required String displayName,
}) {
  final isGroup = entry.kind == 'group';
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetCtx) {
      final scheme = Theme.of(sheetCtx).colorScheme;
      final textTheme = Theme.of(sheetCtx).textTheme;
      final muted = muteLabel(entry.mutedUntilMs);

      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                leading: Avator(
                  text: displayName,
                  seed: entry.channelId,
                  avatarUrl: entry.avatarUrl,
                  isGroup: isGroup,
                  width: kAvatarMd,
                  height: kAvatarMd,
                ),
                title: Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(isGroup ? 'Group' : 'Direct message'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(
                  muted == null
                      ? Icons.notifications_outlined
                      : Icons.notifications_off_outlined,
                ),
                title: const Text('Mute notifications'),
                subtitle: muted == null ? null : Text(muted),
                onTap: () async {
                  Navigator.of(sheetCtx).pop();
                  await showMuteSheet(
                    context: context,
                    chatService: chatService,
                    channelId: entry.channelId,
                    mutedUntilMs: entry.mutedUntilMs,
                  );
                },
              ),
              ListTile(
                leading: Icon(
                  entry.pinned
                      ? Icons.push_pin
                      : Icons.push_pin_outlined,
                ),
                title: Text(entry.pinned ? 'Unpin' : 'Pin to top'),
                onTap: () async {
                  Navigator.of(sheetCtx).pop();
                  await chatService.setPinned(
                    entry.channelId,
                    !entry.pinned,
                  );
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(
                  Icons.cleaning_services_outlined,
                  color: scheme.error,
                ),
                title: Text(
                  'Clear history',
                  style: TextStyle(color: scheme.error),
                ),
                subtitle: const Text(
                  'Erases messages on this phone. The chat stays in '
                  'the list.',
                ),
                isThreeLine: true,
                onTap: () async {
                  Navigator.of(sheetCtx).pop();
                  await confirmClearHistory(
                    context: context,
                    chatService: chatService,
                    channelId: entry.channelId,
                    isGroup: isGroup,
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: scheme.error),
                title: Text(
                  'Delete chat',
                  style: TextStyle(color: scheme.error),
                ),
                subtitle: const Text(
                  'Removes it from Chats and erases history on this '
                  'phone.',
                ),
                isThreeLine: true,
                onTap: () async {
                  Navigator.of(sheetCtx).pop();
                  await chatService.deleteChat(entry.channelId);
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  kSpaceLg,
                  0,
                  kSpaceLg,
                  kSpaceLg,
                ),
                child: Text(
                  isGroup
                      ? 'You stay in the group. $displayName keeps '
                          'showing under Groups in New chat, and '
                          'reappears here the next time someone writes. '
                          'To actually leave, open group info → Leave '
                          'group.'
                      : 'The contact stays in Contacts, and the chat '
                          'reappears here the next time either of you '
                          'writes.',
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// The one confirm in this file, and the reason it is the only one:
/// clearing history destroys local messages for good, while "Delete
/// chat" is self-healing (the next message brings the chat and any
/// later history back) and "Leave group" has its own dialog in group
/// info. Shared with group info so the wording lives in one place.
///
/// Returns true if the user went through with it.
Future<bool> confirmClearHistory({
  required BuildContext context,
  required ChatService chatService,
  required String channelId,
  required bool isGroup,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Clear history?'),
      content: Text(
        isGroup
            ? 'All messages in this group will be erased from this '
                'phone and cannot be recovered. You stay in the group.'
            : 'All messages with this contact will be erased from this '
                'phone and cannot be recovered. The contact stays in '
                'Contacts.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(
            'Clear',
            style: TextStyle(color: Theme.of(ctx).colorScheme.error),
          ),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;
  await chatService.clearMessages(channelId);
  return true;
}

/// The four mute durations from frame f. Each resolves to a real date
/// shown under the option, so "1 week" never has to be worked out in
/// the user's head.
enum MuteChoice {
  eightHours,
  oneWeek,
  always,
  off;

  String get label => switch (this) {
        MuteChoice.eightHours => '8 hours',
        MuteChoice.oneWeek => '1 week',
        MuteChoice.always => 'Always',
        MuteChoice.off => 'Off',
      };

  /// The `muted_until_ms` this choice writes. Null = unmuted.
  int? untilMs(DateTime now) => switch (this) {
        MuteChoice.eightHours =>
          now.add(const Duration(hours: 8)).millisecondsSinceEpoch,
        MuteChoice.oneWeek =>
          now.add(const Duration(days: 7)).millisecondsSinceEpoch,
        MuteChoice.always => kMuteAlways,
        MuteChoice.off => null,
      };

  String subtitle(DateTime now) => switch (this) {
        MuteChoice.eightHours => 'Until '
            '${DateFormat.jm().format(now.add(const Duration(hours: 8)))} '
            'today',
        MuteChoice.oneWeek => 'Until '
            '${DateFormat.MMMEd().format(now.add(const Duration(days: 7)))}',
        MuteChoice.always => 'Until you turn it back on',
        MuteChoice.off => 'Notify me for every message',
      };
}

/// Which radio to pre-select for an existing `muted_until_ms`.
///
/// Only the expiry is stored, not the choice that produced it, so the
/// option is recovered from how much mute is left. Reopening the sheet
/// on a half-elapsed "1 week" therefore shows "1 week", and re-saving
/// it restarts the week — which is what the label says it does.
MuteChoice _choiceFor(int? untilMs, DateTime now) {
  if (untilMs == null) return MuteChoice.off;
  if (untilMs >= kMuteAlways) return MuteChoice.always;
  final remaining = untilMs - now.millisecondsSinceEpoch;
  if (remaining <= 0) return MuteChoice.off;
  return remaining > const Duration(hours: 8).inMilliseconds
      ? MuteChoice.oneWeek
      : MuteChoice.eightHours;
}

/// Frame f — the mute sheet. Writes `muted_until_ms` and nothing else;
/// messages still arrive, only the alert is silenced.
Future<void> showMuteSheet({
  required BuildContext context,
  required ChatService chatService,
  required String channelId,
  required int? mutedUntilMs,
}) {
  final now = DateTime.now();
  var selected = _choiceFor(mutedUntilMs, now);

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetCtx) {
      final scheme = Theme.of(sheetCtx).colorScheme;
      final textTheme = Theme.of(sheetCtx).textTheme;
      return StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    kSpaceLg,
                    0,
                    kSpaceLg,
                    kSpaceMd,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mute notifications',
                        style: textTheme.titleMedium,
                      ),
                      const SizedBox(height: kSpaceXs),
                      Text(
                        'Messages still arrive. Only the alert is '
                        'silenced.',
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // Plain tiles with a radio glyph rather than
                // RadioListTile — the Radio group API is mid-migration
                // in Flutter and this needs no shared group state.
                for (final choice in MuteChoice.values)
                  ListTile(
                    leading: Icon(
                      selected == choice
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: selected == choice ? scheme.primary : null,
                    ),
                    title: Text(choice.label),
                    subtitle: Text(choice.subtitle(now)),
                    onTap: () => setSheetState(() => selected = choice),
                  ),
                Padding(
                  padding: const EdgeInsets.all(kSpaceMd),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: kSpaceSm),
                      FilledButton(
                        onPressed: () async {
                          Navigator.of(ctx).pop();
                          await chatService.setMuted(
                            channelId,
                            selected.untilMs(now),
                          );
                        },
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
