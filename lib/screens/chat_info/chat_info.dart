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
import 'package:vartalap/screens/albums/albums.dart';
import 'package:vartalap/screens/chat_info/live_location_controls.dart';
import 'package:vartalap/screens/chat_info/security_code.dart';
import 'package:vartalap/screens/chat_info/media.dart';
import 'package:vartalap/screens/group_create/group_create.dart';
import 'package:vartalap/screens/labels/labels.dart';
import 'package:vartalap/screens/invites/invites.dart';
import 'package:vartalap/services/asset_cache.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/Inherited/app_services.dart';
import 'package:vartalap/widgets/asset_image.dart';
import 'package:vartalap/widgets/avator.dart';
import 'package:vartalap/widgets/chat_action_sheets.dart';
import 'package:vartalap/widgets/name_dialog.dart';
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
  /// Photos plus files — everything the Media screen lists.
  late Future<int> _mediaCount;

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

  /// Decision 221: who is invited into this group, not a member yet.
  List<InviteRow> _invited = const [];

  /// Decision 219: who we blocked, for a DM's Block / Unblock.
  Set<String> _blocked = const {};
  final List<StreamSubscription<Object>> _subs = [];
  Map<String, String> _names = const {};

  @override
  void initState() {
    super.initState();
    _membersFuture = widget.chatService.fetchChannelMembers(widget.channelId);
    // What the three tabs list, as WhatsApp counts it.
    _mediaCount = Future.wait([
      widget.chatService.fetchMedia(widget.channelId),
      widget.chatService.fetchFiles(widget.channelId),
      widget.chatService.fetchLinks(widget.channelId),
    ]).then((lists) => lists.fold<int>(0, (n, l) => n + l.length));
    _reloadChannel();
    _subs.add(widget.chatService.watchInvites().listen((all) {
      if (mounted) {
        setState(() => _invited = [
              for (final i in all)
                if (i.channelId == widget.channelId) i,
            ]);
      }
    }));
    _subs.add(widget.chatService.watchBlocked().listen((blocked) {
      if (mounted) setState(() => _blocked = blocked);
    }));
    widget.chatService.discoverContacts().then((contacts) {
      if (mounted) {
        setState(() =>
            _names = {for (final c in contacts) c.userId: c.displayLabel});
      }
    });
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
    for (final sub in _subs) {
      sub.cancel();
    }
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

          // Decision 81: the owner and every admin manage the group; a
          // plain member sees no controls at all.
          final canManage = _roleOf(members, localUserId) != 'member';
          // We left, or were removed: the chat stays, read only.
          final left = _isGroup &&
              snap.hasData &&
              !members.any((m) => m.userId == localUserId);
          return ListView(
            // Clear of the gesture bar on an edge-to-edge screen.
            padding: EdgeInsets.only(
                bottom: MediaQuery.paddingOf(context).bottom + kSpaceMd),
            children: [
              const SizedBox(height: kSpaceMd),
              Center(
                child: Column(
                  children: [
                    Builder(builder: (_) {
                      final url = _channel?.avatarUrl;
                      // Frame e: only a group photo is ours to change.
                      // A DM's avatar belongs to the peer; a group we
                      // left is not ours to change either.
                      final mine = _isGroup && !left;
                      // WhatsApp: a photo opens full screen first.
                      final view = url == null || url.isEmpty
                          ? null
                          : () => showAssetViewer(context,
                              uri: url,
                              title: _name,
                              onEdit: mine ? _pickGroupPhoto : null);
                      final avatar = Avator(
                        text: _name,
                        seed: widget.channelId,
                        avatarUrl: url,
                        isGroup: _isGroup,
                        width: kAvatarHeader,
                        height: kAvatarHeader,
                      );
                      if (!mine) {
                        return GestureDetector(onTap: view, child: avatar);
                      }
                      return EditableAvator(
                        avatar: avatar,
                        busy: _settingPhoto,
                        onTap: _pickGroupPhoto,
                        onView: view,
                      );
                    }),
                    const SizedBox(height: kSpaceSm),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Balances the pencil so the name stays centred.
                        if (_isGroup && canManage) const SizedBox(width: 48),
                        Flexible(
                          child: Text(
                            _name,
                            style: textTheme.headlineSmall,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        if (_isGroup && canManage)
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: 'Rename group',
                            onPressed: _rename,
                          ),
                      ],
                    ),
                    const SizedBox(height: kSpaceXs),
                    Text(
                      left
                          ? 'Group'
                          : _isGroup
                              ? 'Group · ${_memberCount(members.length)}'
                              : peer!.contact?.tildeName ?? 'Direct message',
                      style: textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: kSpaceMd),
                    // WhatsApp's row of shortcuts under the name; only
                    // what we have (no calls).
                    InfoActions(actions: [
                      if (_isGroup && canManage && !left)
                        (
                          Icons.person_add_alt_1_outlined,
                          'Add',
                          () => _addMembers(members),
                        ),
                      // Back to the chat with its search open
                      // ([ChatScreen] reads it).
                      (
                        Icons.search,
                        'Search',
                        () => Navigator.of(context).pop('search'),
                      ),
                      if (!left)
                        muted == null
                            ? (Icons.volume_off_outlined, 'Mute', _mute)
                            : (Icons.volume_up_outlined, 'Unmute', _unmute),
                    ]),
                  ],
                ),
              ),
              const SizedBox(height: kSpaceMd),
              if (muted != null) ...[
                _MuteBar(label: muted),
                const SizedBox(height: kSpaceSm),
              ],
              if (!_isGroup) ...[
                _sectionGap,
                _DmIdentityBlock(peer: peer!),
              ],
              _sectionGap,
              FutureBuilder<int>(
                future: _mediaCount,
                builder: (ctx, mediaSnap) {
                  final count = mediaSnap.data;
                  return _InfoTile(
                    icon: Icons.image_outlined,
                    title: 'Media, links and docs',
                    subtitle: count == null
                        ? null
                        : (count == 0
                            ? 'Nothing shared yet'
                            : '$count ${count == 1 ? "item" : "items"}'),
                    onTap: () => Navigator.of(context)
                        .push(
                      MaterialPageRoute<String>(
                        builder: (_) => MediaScreen(
                          channelId: widget.channelId,
                          chatService: widget.chatService,
                          nameOf: (id) => id == localUserId
                              ? 'You'
                              : _names[id] ?? 'Unknown',
                        ),
                      ),
                    )
                        // A secure message picked there: back to the chat,
                        // which shows it.
                        .then((messageId) {
                      if (messageId != null && context.mounted) {
                        Navigator.of(context).pop(messageId);
                      }
                    }),
                  );
                },
              ),
              // decision 233; a 1:1's waits for its peer
              if (_isGroup || peer!.userId.isNotEmpty)
                AlbumsTile(
                  chatService: widget.chatService,
                  channelId: widget.channelId,
                  peer: _isGroup ? null : peer!.userId,
                ),
              _InfoTile(
                icon: muted == null
                    ? Icons.notifications_outlined
                    : Icons.notifications_off_outlined,
                title: 'Notifications',
                subtitle: muted ?? 'On',
                onTap: _mute,
              ),
              if (!_isGroup && peer!.userId.isNotEmpty)
                ContactLabelsTile(
                    chatService: widget.chatService, userId: peer.userId),
              if (!_isGroup && peer!.userId.isNotEmpty)
                _InfoTile(
                  icon: Icons.lock_outline,
                  title: 'Encryption',
                  subtitle: 'Messages are end-to-end encrypted. Tap to verify.',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => SecurityCodeScreen(
                      name: peer.contact?.displayLabel ?? _name,
                      number: widget.chatService.safetyNumber(peer.userId),
                    ),
                  )),
                ),
              if (!_isGroup && peer!.userId.isNotEmpty)
                LiveLocationControls(
                  channelId: widget.channelId,
                  peerUserId: peer.userId,
                  peerName: peer.contact?.displayLabel ?? _name,
                ),
              if (left) ...[
                _sectionGap,
                Padding(
                  padding: const EdgeInsets.all(kSpaceMd),
                  child: Text(
                    "You're no longer a member of this group",
                    style: textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ] else if (_isGroup) ...[
                _sectionGap,
                _MembersSection(
                  members: members,
                  invited: [
                    for (final i in _invited)
                      (i.toUser, _names[i.toUser] ?? 'Unknown'),
                  ],
                  localUserId: localUserId,
                  canManageRoles: canManage,
                  loading: snap.connectionState == ConnectionState.waiting,
                  onSetRole: _setMemberRole,
                  onAdd: canManage ? () => _addMembers(members) : null,
                  onRemove: _removeMember,
                  onCancelInvite: canManage ? _cancelInvite : null,
                ),
              ],
              _sectionGap,
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
                subtitle: left
                    ? 'Removes it from Chats and erases its messages on '
                        'this phone.'
                    : _isGroup
                        ? 'Removes it from Chats. You stay a member and the '
                            'group stays under Groups.'
                        : 'Removes it from Chats. The contact stays in '
                            'Contacts.',
                onTap: () => _deleteChat(context, left: left),
              ),
              // WhatsApp's two red rows at the bottom (decision 219)
              if (!_isGroup && peer!.userId.isNotEmpty) ...[
                _sectionGap,
                _InfoTile(
                  icon: Icons.block,
                  title: _blocked.contains(peer.userId)
                      ? 'Unblock $_name'
                      : 'Block $_name',
                  iconColor: scheme.error,
                  titleColor: scheme.error,
                  onTap: () => _toggleBlock(peer.userId),
                ),
                _InfoTile(
                  icon: Icons.thumb_down_outlined,
                  title: 'Report $_name',
                  iconColor: scheme.error,
                  titleColor: scheme.error,
                  onTap: () => showReportDialog(
                    context,
                    chatService: widget.chatService,
                    userId: peer.userId,
                    name: _name,
                    channelId: widget.channelId,
                  ),
                ),
              ],
              if (_isGroup && !left) ...[
                _sectionGap,
                _InfoTile(
                  icon: Icons.exit_to_app,
                  title: 'Leave group',
                  subtitle: 'You stop receiving messages. The chat and its '
                      'history stay on this phone.',
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
            ],
          );
        },
      ),
    );
  }

  /// Between sections: WhatsApp's narrow band, full width.
  static const Widget _sectionGap = Divider(height: kSpaceSm, indent: 0);

  /// Mute opens the durations; unmute needs none (WhatsApp).
  Future<void> _mute() async {
    await showMuteSheet(
      context: context,
      chatService: widget.chatService,
      channelIds: [widget.channelId],
      mutedUntilMs: _channel?.mutedUntilMs,
    );
    await _reloadChannel();
  }

  Future<void> _unmute() async {
    await widget.chatService.setMuted(widget.channelId, null);
    await _reloadChannel();
  }

  static String _memberCount(int n) => '$n ${n == 1 ? "member" : "members"}';

  /// Local-only, so nothing can fail, but it erases history for good —
  /// so it confirms first, with the chat list's dialog. Pops straight
  /// out to the chat list.
  Future<void> _deleteChat(BuildContext context, {bool left = false}) async {
    final deleted = await confirmDeleteChat(
      context: context,
      chatService: widget.chatService,
      channelIds: [widget.channelId],
      isGroup: _isGroup,
      member: !left,
    );
    if (!deleted || !context.mounted) return;
    // Pop chat info and the chat screen underneath it.
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  static String _roleOf(List<ChannelMemberRow> members, String? userId) =>
      members.where((m) => m.userId == userId).map((m) => m.role).firstOrNull ??
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

  /// The group's name now — a rename here or from someone else.
  /// A DM's resolved name (§2.4), the same one the chat list shows.
  String get _name => _channel?.title ?? widget.channelName;

  Future<void> _rename() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => NameDialog(title: 'Group name', initial: _name),
    );
    if (name == null || name.isEmpty || name == _name) return;
    await widget.chatService.renameGroup(widget.channelId, name);
    await _reloadChannel();
  }

  Future<void> _toggleBlock(String userId) async {
    final block = !_blocked.contains(userId);
    if (block && !await confirmBlock(context, _name)) return;
    try {
      await widget.chatService.setBlocked(userId, block);
    } catch (e) {
      if (mounted) showInviteError(context, e);
    }
  }

  Future<void> _cancelInvite(String userId) async {
    try {
      await widget.chatService.cancelInvite(widget.channelId, userId);
    } catch (e) {
      if (mounted) showInviteError(context, e);
    }
  }

  Future<void> _addMembers(List<ChannelMemberRow> members) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MemberPickerScreen(
          chatService: widget.chatService,
          title: 'Add members',
          doneIcon: Icons.check,
          exclude: {
            for (final m in members) m.userId,
            for (final i in _invited) i.toUser,
          },
          onDone: (pickerContext, picked) async {
            await widget.chatService.addMembers(
              widget.channelId,
              [for (final c in picked) c.userId],
            );
            if (pickerContext.mounted) Navigator.of(pickerContext).pop();
          },
        ),
      ),
    );
    if (mounted) setState(_reloadMembers);
  }

  Future<void> _removeMember(ChannelMemberRow member) async {
    final name = member.contact?.displayLabel ?? 'Unknown';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text('Remove $name from "$_name"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.chatService.removeMember(widget.channelId, member.userId);
    if (mounted) setState(_reloadMembers);
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
        title: Text('Leave $_name?'),
        content: Text(
          'You will stop receiving messages. The chat and its history '
          'stay on this phone until you delete it. Other members stay in '
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
              // WhatsApp stays here: now read only, with Delete chat.
              if (mounted) setState(_reloadMembers);
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
        title: Text('Delete $_name?'),
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

/// Owns its controller: the dialog is still animating out when
/// `showDialog` returns, so the caller can't dispose one it made.
/// Slim banner under the header while the chat is muted.
class _MuteBar extends StatelessWidget {
  final String label;
  const _MuteBar({required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: kSpaceMd),
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
        horizontal: kSpaceMd,
        vertical: kSpaceSm,
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
            const SizedBox(height: kSpaceSm),
          ],
          if (status != null && status.isNotEmpty) ...[
            Text('About',
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

  /// Invited, not members yet (decision 221): (user_id, name).
  final List<(String, String)> invited;
  final String? localUserId;
  final bool canManageRoles;
  final bool loading;
  final Future<void> Function(ChannelMemberRow, String) onSetRole;
  final VoidCallback? onAdd;
  final Future<void> Function(ChannelMemberRow) onRemove;
  final Future<void> Function(String userId)? onCancelInvite;

  const _MembersSection({
    required this.members,
    required this.invited,
    required this.localUserId,
    required this.canManageRoles,
    required this.loading,
    required this.onSetRole,
    required this.onAdd,
    required this.onRemove,
    required this.onCancelInvite,
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
            horizontal: kSpaceMd,
            vertical: kSpaceSm,
          ),
          child: Text(
            '${members.length} ${members.length == 1 ? "member" : "members"}',
            style:
                textTheme.titleSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        if (onAdd != null)
          ListTile(
            leading: CircleAvatar(
              radius: kAvatarMd / 2,
              backgroundColor: scheme.primary,
              child: Icon(Icons.person_add_alt_1, color: scheme.onPrimary),
            ),
            title: const Text('Add members'),
            onTap: onAdd,
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
              onRemove: onRemove,
            ),
        for (final (userId, name) in invited)
          ListTile(
            leading: Avator(
              text: name,
              seed: personSeed(context, userId),
              width: kAvatarMd,
              height: kAvatarMd,
            ),
            title: Text(name),
            subtitle: Text('Invited',
                style: TextStyle(color: scheme.onSurfaceVariant)),
            trailing: onCancelInvite == null
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Cancel invite',
                    onPressed: () => onCancelInvite!(userId),
                  ),
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
  final Future<void> Function(ChannelMemberRow) onRemove;

  const _MemberTile({
    required this.member,
    required this.isYou,
    required this.canManageRoles,
    required this.onSetRole,
    required this.onRemove,
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
              ListTile(
                leading: Icon(Icons.person_off_outlined, color: scheme.error),
                title: Text(
                  'Remove $name',
                  style: TextStyle(color: scheme.error),
                ),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  onRemove(member);
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
        seed: personSeed(context, member.userId),
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

/// WhatsApp's row of shortcuts under the name on Contact info and Chat
/// info: rounded boxes of equal width, icon over label.
class InfoActions extends StatelessWidget {
  final List<(IconData, String, VoidCallback?)> actions;

  const InfoActions({super.key, required this.actions});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kSpaceMd),
      // Two or three boxes stay box-sized rather than stretching.
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: actions.length * 120.0),
        child: Row(
          children: [
            for (final (i, (icon, label, onTap)) in actions.indexed) ...[
              if (i > 0) const SizedBox(width: kSpaceSm),
              Expanded(
                child: OutlinedButton(
                  onPressed: onTap,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: kSpaceMd),
                    side: BorderSide(color: scheme.outlineVariant),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(kRadiusMd),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon),
                      const SizedBox(height: kSpaceXs),
                      Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A chat-list avatar (WhatsApp): a tap opens the photo card, or Info
/// straight away when there is no photo to show.
class ChatAvatarPeek extends StatelessWidget {
  final ChannelListEntry entry;
  final String title;

  /// Opens the chat, as tapping the row does.
  final VoidCallback onMessage;

  /// Null: Chat info, with the app's services.
  final VoidCallback? onInfo;
  final Widget child;

  const ChatAvatarPeek({
    super.key,
    required this.entry,
    required this.title,
    required this.onMessage,
    this.onInfo,
    required this.child,
  });

  void _openInfo(BuildContext context) {
    final services = AppServicesProvider.maybeOf(context);
    if (services == null) return;
    Navigator.of(context)
        .push(MaterialPageRoute<Object?>(
          builder: (_) => ChatInfoScreen(
            channelId: entry.channelId,
            channelName: title,
            channelKind: entry.kind,
            chatService: services.chatService,
            authService: services.authService,
          ),
        ))
        // Search lives in the chat.
        .then((result) => result == 'search' ? onMessage() : null);
  }

  void _peek(BuildContext context) {
    final info = onInfo ?? () => _openInfo(context);
    final url = entry.avatarUrl;
    if (url == null || url.isEmpty) return info();
    showDialog<void>(
      context: context,
      builder: (dialog) {
        void then(VoidCallback next) {
          Navigator.of(dialog).pop();
          next();
        }

        final scheme = Theme.of(dialog).colorScheme;
        return Dialog(
          clipBehavior: Clip.antiAlias,
          insetPadding: const EdgeInsets.symmetric(horizontal: kSpaceXxl),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kRadiusSm),
          ),
          child: SizedBox(
            width: 280,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () => then(
                      () => showAssetViewer(context, uri: url, title: title)),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        AssetImageView(
                          uri: url,
                          placeholder: AssetImagePlaceholder(
                            icon: entry.kind == 'group'
                                ? Icons.groups_rounded
                                : Icons.person_rounded,
                          ),
                        ),
                        // The name strip over the photo's top edge.
                        Align(
                          alignment: Alignment.topCenter,
                          child: Container(
                            width: double.infinity,
                            color: Colors.black38,
                            padding: const EdgeInsets.symmetric(
                              horizontal: kSpaceMd,
                              vertical: kSpaceSm,
                            ),
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chat_outlined),
                      color: scheme.primary,
                      tooltip: 'Message',
                      onPressed: () => then(onMessage),
                    ),
                    IconButton(
                      icon: const Icon(Icons.info_outline),
                      color: scheme.primary,
                      tooltip: 'Info',
                      onPressed: () => then(info),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => _peek(context),
        child: child,
      );
}
