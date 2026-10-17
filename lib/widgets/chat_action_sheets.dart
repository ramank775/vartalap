/// The dialogs and the mute sheet (frame f) behind a chat's local-only
/// actions, shared by the chat-list selection bar and chat info.
///
/// Everything here is device-local — mute, clear history and delete
/// chat never touch the server (V3_ARCHITECTURE decision 3 offline
/// matrix). That is why they apply immediately and nothing here can
/// fail or asks for a connection. The one action that *is* a server
/// op, "Leave group", deliberately lives elsewhere — in group info, in
/// error red, behind its own confirm.
library vartalap.widgets.chat_action_sheets;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/theme/theme.dart';

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

/// Clearing history destroys local messages for good, so it confirms
/// first. The chat itself stays in the list. Shared by the chat-list
/// selection bar and group info, so the wording lives in one place.
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

/// WhatsApp's "Delete this chat?" / "Delete 3 chats?". It erases the
/// history on this phone for good, so it confirms like Clear history;
/// the body says what it does *not* do (leave a group, drop a contact).
/// [isGroup] picks the wording for a single chat; several chats share
/// one sentence covering both kinds.
///
/// Returns true if the user went through with it.
Future<bool> confirmDeleteChat({
  required BuildContext context,
  required ChatService chatService,
  required List<String> channelIds,
  required bool isGroup,
}) async {
  final one = channelIds.length == 1;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(
        one ? 'Delete this chat?' : 'Delete ${channelIds.length} chats?',
      ),
      content: Text(
        !one
            ? 'Their messages will be erased from this phone. You stay in '
                'any groups, contacts stay in Contacts, and a chat comes '
                'back the next time someone writes.'
            : isGroup
                ? 'Its messages will be erased from this phone. You stay '
                    'in the group, and the chat comes back the next time '
                    'someone writes. To leave, use Leave group in group '
                    'info.'
                : 'Its messages will be erased from this phone. The '
                    'contact stays in Contacts, and the chat comes back '
                    'the next time either of you writes.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(
            one ? 'Delete chat' : 'Delete chats',
            style: TextStyle(color: Theme.of(ctx).colorScheme.error),
          ),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;
  for (final id in channelIds) {
    await chatService.deleteChat(id);
  }
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
/// messages still arrive, only the alert is silenced. The choice
/// applies to every chat in [channelIds] (a chat-list selection);
/// [mutedUntilMs] only picks the preselected option.
///
/// Returns true on Save, false if the sheet was dismissed.
Future<bool> showMuteSheet({
  required BuildContext context,
  required ChatService chatService,
  required List<String> channelIds,
  required int? mutedUntilMs,
}) async {
  final now = DateTime.now();
  var selected = _choiceFor(mutedUntilMs, now);

  final saved = await showModalBottomSheet<bool>(
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
                          Navigator.of(ctx).pop(true);
                          for (final id in channelIds) {
                            await chatService.setMuted(
                              id,
                              selected.untilMs(now),
                            );
                          }
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
  return saved ?? false;
}
