/// Group info / chat info (frames e, e2).
///
/// This is the screen where "Delete chat" and "Leave group" appear
/// together, on purpose and never as adjacent lookalikes: Delete chat
/// sits in the neutral block with its consequence written under it and
/// is local-only; Leave group sits alone at the bottom, in error red,
/// below a rule, behind a confirm, and is the one action here that
/// enqueues a server op.
///
/// Decisions 9/80/81 add roles on top of that: the owner also gets
/// "Delete group" (the group dies for everyone), the owner and admins
/// get Make admin / Dismiss as admin off each member row, and the
/// owner's Leave confirm names the successor the server is about to
/// promote.
library vartalap.screens.chat_info;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vartalap/screens/chat_info/media.dart';
import 'package:vartalap/services/asset_cache.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/avator.dart';
import 'package:vartalap/widgets/chat_action_sheets.dart';
import 'package:vartalap_store/vartalap_store.dart';

/// Decision 9's succession rule, computed locally so the owner's Leave
/// confirm can name the person: the longest-standing admin, else the
/// longest-standing remaining member. `joined_at` is the clock, with
/// `user_id` as a deterministic tiebreaker. Null when the owner is the
/// only member left (the group goes with them).
ChannelMemberRow? successorAfterOwnerLeaves(
  List<ChannelMemberRow> members,
  String ownerUserId,
) {
  final rest = members.where((m) => m.userId != ownerUserId).toList()
    ..sort((a, b) => a.joinedAt == b.joinedAt
        ? a.userId.compareTo(b.userId)
        : a.joinedAt.compareTo(b.joinedAt));
  if (rest.isEmpty) return null;
  return rest.firstWhere((m) => m.role == 'admin', orElse: () => rest.first);
}

/// What a member row is labelled with. Members carry no badge.
String? roleBadge(String role) => switch (role) {
      'owner' => 'Owner',
      'admin' => 'Admin',
      _ => null,
    };

class ChatInfoScreen extends StatefulWidget {
  final String channelId;
  final String channelName;
  final String channelKind; // 'one_to_one' | 'group'
  final ChatService chatService;
  final AuthService authService;

  const ChatInfoScreen({
    super.key,
    required this.channelId,
    required this.channelName,
    required this.channelKind,
    required this.chatService,
    required this.authService,
  });

  @override
  State<ChatInfoScreen> createState() => _ChatInfoScreenState();
}

class _ChatInfoScreenState extends State<ChatInfoScreen> {
  late Future<List<ChannelMemberRow>> _membersFuture;
  late Future<List<MessageRow>> _mediaFuture;

  /// Channel row, for the avatar and the local mute flag. Re-read
  /// after the mute sheet closes so the bar and the tile agree.
  ChannelListEntry? _channel;

  bool get _isGroup => widget.channelKind == 'group';

  /// True between picking a group photo and the local row being
  /// updated — the upload itself runs in the op queue afterwards.
  bool _settingPhoto = false;

  /// Frame e — tap the group avatar to replace the photo. Local first:
  /// the new image shows straight away and the upload + `PATCH
  /// /v3.0/channels/{id}` ride the outbound queue.
  Future<void> _pickGroupPhoto() async {
    final path = await pickPhoto(widget.chatService.assets);
    if (path == null || !mounted) return;
    setState(() => _settingPhoto = true);
    try {
      await widget.chatService.setChannelAvatar(
        channelId: widget.channelId,
        path: path,
      );
      final channel = await widget.chatService.fetchChannel(widget.channelId);
      if (mounted) setState(() => _channel = channel);
    } finally {
      if (mounted) setState(() => _settingPhoto = false);
    }
  }

  /// Role ops that already produced a toast, so one failure is reported
  /// once however often the failure stream re-emits.
  final Set<String> _reportedFailures = {};
  StreamSubscription<List<OutboundOpRow>>? _failureSub;

  @override
  void initState() {
    super.initState();
    _membersFuture = widget.chatService.fetchChannelMembers(widget.channelId);
    _mediaFuture = widget.chatService.fetchMedia(widget.channelId);
    _reloadChannel();
    // A rejected role change is rolled back in the store
    // (`_rollbackMemberRole`); the screen's job is to say so and show
    // the restored roster.
    _failureSub = widget.chatService.watchFailures().listen((ops) {
      final failed = ops.where((op) =>
          op.kind == OpKind.setMemberRole &&
          op.targetChannelId == widget.channelId &&
          _reportedFailures.add(op.opId));
      if (failed.isEmpty || !mounted) return;
      setState(_reloadMembers);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not change that role')),
      );
    });
  }

  @override
  void dispose() {
    _failureSub?.cancel();
    super.dispose();
  }

  void _reloadMembers() {
    _membersFuture = widget.chatService.fetchChannelMembers(widget.channelId);
  }

  Future<void> _reloadChannel() async {
    final channel = await widget.chatService.fetchChannel(widget.channelId);
    if (!mounted) return;
    setState(() => _channel = channel);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final localUserId = widget.authService.currentUserId;
    final muted = muteLabel(_channel?.mutedUntilMs);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isGroup ? 'Group info' : 'Chat info'),
      ),
      body: FutureBuilder<List<ChannelMemberRow>>(
        future: _membersFuture,
        builder: (context, snap) {
          final members = snap.data ?? const <ChannelMemberRow>[];
          final peer = _isGroup
              ? null
              : members.firstWhere(
                  (m) => m.userId != localUserId,
                  orElse: () => members.isNotEmpty
                      ? members.first
                      : ChannelMemberRow(
                          channelId: widget.channelId,
                          userId: '',
                          role: 'member',
                          joinedAt: 0,
                          contact: null,
                        ),
                );

          return ListView(
            children: [
              const SizedBox(height: kSpaceXl),
              Center(
                child: Column(
                  children: [
                    Builder(builder: (_) {
                      final avatar = Avator(
                        text: widget.channelName,
                        seed: widget.channelId,
                        avatarUrl: _channel?.avatarUrl,
                        isGroup: _isGroup,
                        width: kAvatarXl,
                        height: kAvatarXl,
                      );
                      // Frame e: only a group photo is ours to change.
                      // A DM's avatar belongs to the peer.
                      if (!_isGroup) return avatar;
                      return EditableAvator(
                        avatar: avatar,
                        busy: _settingPhoto,
                        onTap: _pickGroupPhoto,
                      );
                    }),
                    const SizedBox(height: kSpaceMd),
                    Text(widget.channelName, style: textTheme.headlineSmall),
                    const SizedBox(height: kSpaceXs),
                    Text(
                      _isGroup
                          ? 'Group · ${_memberCount(members.length)}'
                          : 'Direct message',
                      style: textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: kSpaceXl),
              if (muted != null) _MuteBar(label: muted),
              if (!_isGroup) ...[
                const Divider(),
                _DmIdentityBlock(peer: peer!),
              ],
              const Divider(),
              FutureBuilder<List<MessageRow>>(
                future: _mediaFuture,
                builder: (ctx, mediaSnap) {
                  final count = mediaSnap.data?.length;
                  return _InfoTile(
                    icon: Icons.image_outlined,
                    title: 'Media, links and docs',
                    subtitle: count == null
                        ? null
                        : (count == 0
                            ? 'Nothing shared yet'
                            : '$count ${count == 1 ? "item" : "items"}'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MediaScreen(
                          channelId: widget.channelId,
                          chatService: widget.chatService,
                        ),
                      ),
                    ),
                  );
                },
              ),
              _InfoTile(
                icon: muted == null
                    ? Icons.notifications_outlined
                    : Icons.notifications_off_outlined,
                title: 'Notifications',
                subtitle: muted ?? 'On',
                onTap: () async {
                  await showMuteSheet(
                    context: context,
                    chatService: widget.chatService,
                    channelId: widget.channelId,
                    mutedUntilMs: _channel?.mutedUntilMs,
                  );
                  await _reloadChannel();
                },
              ),
              if (_isGroup) ...[
                const Divider(),
                _MembersSection(
                  members: members,
                  localUserId: localUserId,
                  // Decision 81: the owner and every admin can promote
                  // and demote; a plain member sees no menu at all.
                  canManageRoles: _roleOf(members, localUserId) != 'member',
                  loading: snap.connectionState == ConnectionState.waiting,
                  onSetRole: _setMemberRole,
                ),
              ],
              const Divider(),
              _InfoTile(
                icon: Icons.cleaning_services_outlined,
                title: 'Clear history',
                subtitle: 'Erases messages on this phone only',
                onTap: () async {
                  final cleared = await confirmClearHistory(
                    context: context,
                    chatService: widget.chatService,
                    channelId: widget.channelId,
                    isGroup: _isGroup,
                  );
                  if (cleared) setState(() {});
                },
              ),
              _InfoTile(
                icon: Icons.delete_outline,
                title: 'Delete chat',
                subtitle: _isGroup
                    ? 'Removes it from Chats. You stay a member and the '
                        'group stays under Groups.'
                    : 'Removes it from Chats. The contact stays in '
                        'Contacts.',
                onTap: () => _deleteChat(context),
              ),
              if (_isGroup) ...[
                const Divider(),
                _InfoTile(
                  icon: Icons.exit_to_app,
                  title: 'Leave group',
                  subtitle: 'You stop receiving messages. The group '
                      'disappears from Groups too.',
                  iconColor: scheme.error,
                  titleColor: scheme.error,
                  onTap: () => _confirmLeave(context, members),
                ),
                // Decision 9: only the owner can end the group for
                // everyone, and it is never the same tap as leaving.
                if (_roleOf(members, localUserId) == 'owner')
                  _InfoTile(
                    icon: Icons.delete_forever_outlined,
                    title: 'Delete group',
                    subtitle: 'Ends the group for every member. Only you '
                        'can do this.',
                    iconColor: scheme.error,
                    titleColor: scheme.error,
                    onTap: () => _confirmDelete(context),
                  ),
              ],
              const SizedBox(height: kSpaceXl),
            ],
          );
        },
      ),
    );
  }

  static String _memberCount(int n) =>
      '$n ${n == 1 ? "member" : "members"}';

  /// Local-only, so there is nothing to confirm and nothing that can
  /// fail — the consequence is written under the tile and the next
  /// message brings the chat back. Pops straight out to the chat list.
  Future<void> _deleteChat(BuildContext context) async {
    await widget.chatService.deleteChat(widget.channelId);
    if (!context.mounted) return;
    // Pop chat info and the chat screen underneath it.
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  static String _roleOf(List<ChannelMemberRow> members, String? userId) =>
      members
          .where((m) => m.userId == userId)
          .map((m) => m.role)
          .firstOrNull ??
      'member';

  /// Decision 80: the change lands locally at once and rides the
  /// outbound queue; a terminal reject rolls the row back and the
  /// failure subscription in [initState] raises the toast.
  Future<void> _setMemberRole(ChannelMemberRow member, String role) async {
    await widget.chatService.setMemberRole(
      channelId: widget.channelId,
      userId: member.userId,
      role: role,
    );
    if (!mounted) return;
    setState(_reloadMembers);
  }

  void _confirmLeave(BuildContext context, List<ChannelMemberRow> members) {
    final localUserId = widget.authService.currentUserId;
    // Decision 9: an owner may leave, and the group carries on under
    // somebody else. Naming them here is the whole point of the
    // confirm — the server applies the same rule.
    final successor = _roleOf(members, localUserId) == 'owner'
        ? successorAfterOwnerLeaves(members, localUserId ?? '')
        : null;
    final successorName = successor == null
        ? null
        : (successor.contact?.displayLabel ?? 'Unknown');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Leave ${widget.channelName}?'),
        content: Text(
          'You will stop receiving messages and the group will be '
          'removed from Groups and from Chats. Other members stay in '
          'the group and can add you back. Applies right away and '
          'syncs when you are online.'
          '${successorName == null ? '' : ' $successorName will become '
              'the owner.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await widget.chatService.leaveGroup(
                  widget.channelId,
                  selfUserId: localUserId ?? '',
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Could not leave group: $e')),
                );
                return;
              }
              if (!context.mounted) return;
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            child: Text(
              'Leave group',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Owner only, and the one action on this screen that cannot be
  /// undone by anybody — hence the bluntest sentence in the app.
  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${widget.channelName}?'),
        content: const Text(
          'Everyone loses this group. Every member loses the chat and '
          'its history, and it cannot be undone. To walk away without '
          'ending it for the others, leave the group instead.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await widget.chatService.deleteGroup(widget.channelId);
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Could not delete group: $e')),
                );
                return;
              }
              if (!context.mounted) return;
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            child: Text(
              'Delete group',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Slim banner under the header while the chat is muted.
class _MuteBar extends StatelessWidget {
  final String label;
  const _MuteBar({required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: kSpaceLg),
      padding: const EdgeInsets.symmetric(
        horizontal: kSpaceMd,
        vertical: kSpaceSm,
      ),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(kRadiusMd),
      ),
      child: Row(
        children: [
          Icon(
            Icons.notifications_off_outlined,
            size: 18,
            color: scheme.onSecondaryContainer,
          ),
          const SizedBox(width: kSpaceSm),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: scheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// DM peer identity block: username + status text if discovered.
class _DmIdentityBlock extends StatelessWidget {
  final ChannelMemberRow peer;
  const _DmIdentityBlock({required this.peer});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final c = peer.contact;
    final username = c?.username;
    final status = c?.statusText;

    if (username == null && status == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: kSpaceLg,
        vertical: kSpaceMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (username != null) ...[
            Text('Username',
                style: textTheme.labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: kSpaceXs),
            Text('@$username', style: textTheme.bodyLarge),
            const SizedBox(height: kSpaceMd),
          ],
          if (status != null && status.isNotEmpty) ...[
            Text('Status',
                style: textTheme.labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: kSpaceXs),
            Text(status, style: textTheme.bodyLarge),
          ],
        ],
      ),
    );
  }
}

class _MembersSection extends StatelessWidget {
  final List<ChannelMemberRow> members;
  final String? localUserId;
  final bool canManageRoles;
  final bool loading;
  final Future<void> Function(ChannelMemberRow, String) onSetRole;

  const _MembersSection({
    required this.members,
    required this.localUserId,
    required this.canManageRoles,
    required this.loading,
    required this.onSetRole,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: kSpaceLg,
            vertical: kSpaceMd,
          ),
          child: Text(
            '${members.length} ${members.length == 1 ? "member" : "members"}',
            style:
                textTheme.titleSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        if (loading)
          const Padding(
            padding: EdgeInsets.all(kSpaceLg),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          for (final m in members)
            _MemberTile(
              member: m,
              isYou: m.userId == localUserId,
              // Decision 80: the owner is never a target, and nobody
              // changes their own role — the server answers 403 either
              // way, so the menu is not offered.
              canManageRoles: canManageRoles &&
                  m.role != 'owner' &&
                  m.userId != localUserId,
              onSetRole: onSetRole,
            ),
      ],
    );
  }
}

class _MemberTile extends StatelessWidget {
  final ChannelMemberRow member;
  final bool isYou;
  final bool canManageRoles;
  final Future<void> Function(ChannelMemberRow, String) onSetRole;

  const _MemberTile({
    required this.member,
    required this.isYou,
    required this.canManageRoles,
    required this.onSetRole,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = isYou ? 'You' : (member.contact?.displayLabel ?? 'Unknown');
    final badge = roleBadge(member.role);
    final isAdmin = member.role == 'admin';
    // Frame e2: one action, so a menu entry rather than a submenu —
    // the row long-presses into the same thing the trailing button
    // opens, because a long-press is what a phone user tries first.
    void promptRole() {
      if (!canManageRoles) return;
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheetCtx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  isAdmin
                      ? Icons.person_remove_outlined
                      : Icons.shield_outlined,
                ),
                title: Text(isAdmin ? 'Dismiss as admin' : 'Make admin'),
                subtitle: Text(
                  isAdmin
                      ? '$name goes back to being a member.'
                      : '$name can add and remove members and manage '
                          'admins.',
                ),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  onSetRole(member, isAdmin ? 'member' : 'admin');
                },
              ),
            ],
          ),
        ),
      );
    }

    return ListTile(
      leading: Avator(
        text: name,
        seed: member.userId,
        avatarUrl: member.contact?.avatarUrl,
        width: kAvatarMd,
        height: kAvatarMd,
      ),
      title: Text(name),
      subtitle: badge != null
          ? Text(badge, style: TextStyle(color: scheme.onSurfaceVariant))
          : null,
      trailing: canManageRoles
          ? IconButton(
              icon: const Icon(Icons.more_vert),
              tooltip: 'Member options',
              onPressed: promptRole,
            )
          : null,
      onLongPress: canManageRoles ? promptRole : null,
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? iconColor;
  final Color? titleColor;
  final VoidCallback? onTap;

  const _InfoTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.iconColor,
    this.titleColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: iconColor ?? scheme.onSurfaceVariant),
      title: Text(title, style: TextStyle(color: titleColor)),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      onTap: onTap,
    );
  }
}
