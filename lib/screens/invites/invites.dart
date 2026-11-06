/// Invite-only (decisions 219-221): the "Invites" row on top of the chat
/// list, the list it opens with Accept / Decline / Decline and block,
/// the bar that stands in for a 1:1 chat's composer until the two are
/// connected, and the Block and Report dialogs. Worded for someone who
/// has never heard of invites.
library vartalap.screens.invites;

import 'package:flutter/material.dart';
import 'package:vartalap/screens/chat/chat.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/avator.dart';
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

/// The invites to [self], oldest first.
Stream<List<InviteRow>> incomingInvites(ChatService chat, String? self) =>
    chat.watchInvites().map((all) => [
          for (final i in all)
            if (i.toUser == self) i,
        ]);

/// "Invites (2)" above the chats; nothing while there are none.
class InvitesRow extends StatefulWidget {
  final ChatService chatService;
  final AuthService authService;
  const InvitesRow({
    super.key,
    required this.chatService,
    required this.authService,
  });

  @override
  State<InvitesRow> createState() => _InvitesRowState();
}

class _InvitesRowState extends State<InvitesRow> {
  /// Once, so the chat list's rebuilds do not start it over.
  late final Stream<List<InviteRow>> _invites = incomingInvites(
      widget.chatService, widget.authService.currentUserId);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chatService = widget.chatService;
    final authService = widget.authService;
    return StreamBuilder<List<InviteRow>>(
      stream: _invites,
      builder: (context, snap) {
        final n = snap.data?.length ?? 0;
        if (n == 0) return const SizedBox.shrink();
        return Column(children: [
          ListTile(
            leading: CircleAvatar(
              radius: kAvatarMd / 2,
              backgroundColor: scheme.primary,
              child: Icon(Icons.person_add_alt_1, color: scheme.onPrimary),
            ),
            title: Text('Invites ($n)'),
            subtitle: Text(n == 1
                ? 'Someone wants to chat with you'
                : '$n people want to chat with you'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => InvitesScreen(
                chatService: chatService,
                authService: authService,
              ),
            )),
          ),
          const Divider(height: 1),
        ]);
      },
    );
  }
}

/// Every invite waiting for an answer, each with its three buttons.
class InvitesScreen extends StatefulWidget {
  final ChatService chatService;
  final AuthService authService;
  const InvitesScreen({
    super.key,
    required this.chatService,
    required this.authService,
  });

  @override
  State<InvitesScreen> createState() => _InvitesScreenState();
}

class _InvitesScreenState extends State<InvitesScreen> {
  late final Stream<(List<InviteRow>, Map<String, String>)> _invites =
      incomingInvites(widget.chatService, widget.authService.currentUserId)
          .asyncMap((invites) async {
    final contacts = await widget.chatService.discoverContacts();
    return (invites, {for (final c in contacts) c.userId: c.displayLabel});
  });

  /// The invite being answered, so its buttons wait.
  String? _busy;

  Future<void> _answer(InviteRow invite, String name, _Answer answer) async {
    if (answer == _Answer.block && !await confirmBlock(context, name)) return;
    setState(() => _busy = invite.channelId);
    final chat = widget.chatService;
    try {
      if (answer == _Answer.accept) {
        final channelId = await chat.acceptInvite(invite);
        if (!mounted) return;
        await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
          builder: (_) => ChatScreen(
            channelId: channelId,
            channelName: invite.isGroup ? invite.name ?? 'Group' : name,
            channelKind: invite.isGroup ? 'group' : 'one_to_one',
            chatService: chat,
            authService: widget.authService,
          ),
        ));
      } else {
        await chat.declineInvite(invite, block: answer == _Answer.block);
      }
    } catch (e) {
      if (mounted) showInviteError(context, e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Invites')),
      body: StreamBuilder<(List<InviteRow>, Map<String, String>)>(
        stream: _invites,
        builder: (context, snap) {
          final data = snap.data;
          if (data == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final (invites, names) = data;
          if (invites.isEmpty) {
            return Center(
              child: Text('No invites',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
            );
          }
          return ListView.separated(
            itemCount: invites.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final invite = invites[i];
              final from = names[invite.fromUser] ?? 'Someone';
              final title = invite.isGroup ? invite.name ?? 'A group' : from;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: kSpaceSm),
                child: Column(children: [
                  ListTile(
                    leading: Avator(
                      text: title,
                      seed: invite.isGroup
                          ? invite.channelId
                          : personSeed(context, invite.fromUser),
                      isGroup: invite.isGroup,
                      width: kAvatarMd,
                      height: kAvatarMd,
                    ),
                    title: Text(title),
                    subtitle: Text(invite.isGroup
                        ? '$from invited you to this group'
                        : 'Wants to chat with you'),
                  ),
                  _AnswerButtons(
                    busy: _busy == invite.channelId,
                    onAnswer: (a) => _answer(invite, from, a),
                  ),
                ]),
              );
            },
          );
        },
      ),
    );
  }
}

enum _Answer { accept, decline, block }

/// Accept, Decline, Decline and block: one row, the safe choice biggest.
class _AnswerButtons extends StatelessWidget {
  final bool busy;
  final void Function(_Answer) onAnswer;
  const _AnswerButtons({required this.busy, required this.onAnswer});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kSpaceLg),
      child: Wrap(
        spacing: kSpaceSm,
        runSpacing: kSpaceSm,
        alignment: WrapAlignment.center,
        children: [
          FilledButton(
            onPressed: busy ? null : () => onAnswer(_Answer.accept),
            child: const Text('Accept'),
          ),
          OutlinedButton(
            onPressed: busy ? null : () => onAnswer(_Answer.decline),
            child: const Text('Decline'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: scheme.error),
            onPressed: busy ? null : () => onAnswer(_Answer.block),
            child: const Text('Decline and block'),
          ),
        ],
      ),
    );
  }
}

/// What stands in for a 1:1 chat's composer until the two are connected
/// (decision 219), or while we have blocked them.
class InviteBar extends StatefulWidget {
  final PeerLink link;
  final String peerUserId;
  final String peerName;
  final ChatService chatService;
  final AuthService authService;

  const InviteBar({
    super.key,
    required this.link,
    required this.peerUserId,
    required this.peerName,
    required this.chatService,
    required this.authService,
  });

  @override
  State<InviteBar> createState() => _InviteBarState();
}

class _InviteBarState extends State<InviteBar> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) showInviteError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chat = widget.chatService;
    final name = widget.peerName;
    final peer = widget.peerUserId;
    final self = widget.authService.currentUserId ?? '';
    final dm = dmChannelId(self, peer);
    final link = widget.link;
    final String text;
    final List<Widget> buttons;
    if (link.blocked) {
      text = 'You blocked $name.';
      buttons = [
        FilledButton(
          onPressed: () => _run(() => chat.setBlocked(peer, false)),
          child: const Text('Unblock'),
        ),
      ];
    } else if (link.inviteReceived) {
      text = '$name wants to chat with you.';
      buttons = [
        FilledButton(
          onPressed: () => _run(() => chat.acceptInvite(_incoming(dm))),
          child: const Text('Accept'),
        ),
        OutlinedButton(
          onPressed: () => _run(() => chat.declineInvite(_incoming(dm))),
          child: const Text('Decline'),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: scheme.error),
          onPressed: () => _run(() async {
            if (await confirmBlock(context, name)) {
              await chat.declineInvite(_incoming(dm), block: true);
            }
          }),
          child: const Text('Decline and block'),
        ),
      ];
    } else if (link.inviteSent) {
      text = 'Invite sent. You can chat once $name accepts.';
      buttons = [
        OutlinedButton(
          onPressed: () => _run(() => chat.cancelInvite(dm, peer)),
          child: const Text('Cancel invite'),
        ),
      ];
    } else {
      text = 'Vartalap is invite only. Send $name an invite. You can '
          'chat once they accept.';
      buttons = [
        FilledButton.icon(
          icon: const Icon(Icons.person_add_alt_1),
          onPressed: () => _run(() => chat.sendInvite(peer)),
          label: const Text('Send invite'),
        ),
      ];
    }
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(kSpaceLg),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(height: kSpaceMd),
          if (_busy)
            const SizedBox.square(
                dimension: 32, child: CircularProgressIndicator())
          else
            Wrap(
              spacing: kSpaceSm,
              runSpacing: kSpaceSm,
              alignment: WrapAlignment.center,
              children: buttons,
            ),
        ]),
      ),
    );
  }

  /// The invite [widget.peerUserId] sent us, as [InviteRow] holds it.
  InviteRow _incoming(String dm) => InviteRow(
        channelId: dm,
        toUser: widget.authService.currentUserId ?? '',
        fromUser: widget.peerUserId,
        createdAt: 0,
      );
}

/// "Block Ravi?" Returns true to go ahead.
Future<bool> confirmBlock(BuildContext context, String name) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Block $name?'),
        content: Text('$name will not be able to message you or send you '
            'invites. They will not be told. Groups you share are not '
            'affected.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Block'),
          ),
        ],
      ),
    ) ??
    false;

/// WhatsApp's Report: optionally with the chat's last 5 messages, and
/// "Report and block". Shows what happened; true when a report went.
Future<bool> showReportDialog(
  BuildContext context, {
  required ChatService chatService,
  required String userId,
  required String name,
  String? channelId,
}) async {
  var withMessages = channelId != null;
  final choice = await showDialog<_Answer>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setInner) => AlertDialog(
        title: Text('Report $name?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('$name will not be told.'),
          if (channelId != null)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: withMessages,
              onChanged: (v) => setInner(() => withMessages = v ?? false),
              title: const Text('Send the last 5 messages of this chat '
                  'with the report'),
            ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_Answer.decline),
            child: const Text('Report'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_Answer.block),
            child: const Text('Report and block'),
          ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return false;
  try {
    await chatService.report(
      userId,
      channelId: withMessages ? channelId : null,
      block: choice == _Answer.block,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(choice == _Answer.block
              ? 'Reported and blocked'
              : 'Report sent')));
    }
    return true;
  } catch (e) {
    if (context.mounted) showInviteError(context, e);
    return false;
  }
}

/// One plain sentence for whatever went wrong.
void showInviteError(BuildContext context, Object error) {
  final text = switch (error) {
    AuthClientException(errorCode: 'invite_limit') =>
      'You have too many invites waiting for an answer. Cancel one, or '
          'wait until someone answers.',
    AuthClientException(statusCode: 404) =>
      'This invite is no longer available.',
    AuthClientException() => 'Something went wrong. Please try again.',
    _ => 'No internet connection. Please try again.',
  };
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}
