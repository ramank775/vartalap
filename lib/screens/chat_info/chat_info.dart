/// Group info / chat info (frames e, e2).
///
/// This is the screen where "Delete chat" and "Leave group" appear
/// together, on purpose and never as adjacent lookalikes: Delete chat
/// sits in the neutral block with its consequence written under it and
/// is local-only; Leave group sits alone at the bottom, in error red,
/// below a rule, behind a confirm, and is the one action here that
/// enqueues a server op.
library vartalap.screens.chat_info;

import 'package:flutter/material.dart';
import 'package:vartalap/screens/chat_info/media.dart';
import 'package:vartalap/services/asset_cache.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/avator.dart';
import 'package:vartalap/widgets/chat_action_sheets.dart';
import 'package:vartalap_store/vartalap_store.dart';

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

  @override
  void initState() {
    super.initState();
    _membersFuture = widget.chatService.fetchChannelMembers(widget.channelId);
    _mediaFuture = widget.chatService.fetchMedia(widget.channelId);
    _reloadChannel();
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
                  loading: snap.connectionState == ConnectionState.waiting,
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
                  onTap: () => _confirmLeave(context),
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

  void _confirmLeave(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Leave ${widget.channelName}?'),
        content: const Text(
          'You will stop receiving messages and the group will be '
          'removed from Groups and from Chats. Other members stay in '
          'the group and can add you back. Applies right away and '
          'syncs when you are online.',
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
                await widget.chatService.leaveGroup(widget.channelId);
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
  final bool loading;

  const _MembersSection({
    required this.members,
    required this.localUserId,
    required this.loading,
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
            _MemberTile(member: m, isYou: m.userId == localUserId),
      ],
    );
  }
}

class _MemberTile extends StatelessWidget {
  final ChannelMemberRow member;
  final bool isYou;

  const _MemberTile({required this.member, required this.isYou});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = isYou ? 'You' : (member.contact?.displayLabel ?? 'Unknown');
    final subtitle = member.role == 'owner' ? 'Owner' : null;
    return ListTile(
      leading: Avator(
        text: name,
        seed: member.userId,
        avatarUrl: member.contact?.avatarUrl,
        width: kAvatarMd,
        height: kAvatarMd,
      ),
      title: Text(name),
      subtitle: subtitle != null
          ? Text(subtitle, style: TextStyle(color: scheme.onSurfaceVariant))
          : null,
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
