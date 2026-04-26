/// Chat info screen — shows channel details, members, and actions.
///
/// Branches on channel `kind` for the destructive action: groups get
/// "Leave group" (drops channel + membership), DMs get "Clear messages"
/// (wipes messages, keeps channel — DM channels must remain unique per
/// user pair to keep the address stable for incoming peer messages).
library vartalap.screens.chat_info;

import 'package:flutter/material.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/avator.dart';
import 'package:vartalap_store/vartalap_store.dart';

class ChatInfoScreen extends StatefulWidget {
  final String channelId;
  final String channelName;
  final String channelKind; // 'dm' | 'group'
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

  bool get _isGroup => widget.channelKind == 'group';

  @override
  void initState() {
    super.initState();
    _membersFuture = widget.chatService.fetchChannelMembers(widget.channelId);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final localUserId = widget.authService.currentUserId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat Info'),
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
                    Avator(
                      text: widget.channelName,
                      width: kAvatarXl,
                      height: kAvatarXl,
                    ),
                    const SizedBox(height: kSpaceMd),
                    Text(widget.channelName, style: textTheme.headlineSmall),
                    const SizedBox(height: kSpaceXs),
                    Text(
                      _isGroup
                          ? '${members.length} ${members.length == 1 ? "member" : "members"}'
                          : 'Direct message',
                      style: textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: kSpaceXl),
              if (!_isGroup) ...[
                const Divider(),
                _DmIdentityBlock(peer: peer!),
              ],
              const Divider(),
              _InfoTile(
                icon: Icons.notifications_outlined,
                title: 'Notifications',
                subtitle: 'Coming soon',
                enabled: false,
              ),
              _InfoTile(
                icon: Icons.image_outlined,
                title: 'Media, links, and docs',
                subtitle: 'Coming soon',
                enabled: false,
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
                title: 'Clear messages',
                iconColor: scheme.error,
                titleColor: scheme.error,
                onTap: () => _confirmClear(context),
              ),
              if (_isGroup)
                _InfoTile(
                  icon: Icons.exit_to_app,
                  title: 'Leave group',
                  iconColor: scheme.error,
                  titleColor: scheme.error,
                  onTap: () => _confirmLeave(context),
                ),
              const SizedBox(height: kSpaceXl),
            ],
          );
        },
      ),
    );
  }

  void _confirmClear(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear messages?'),
        content: Text(
          _isGroup
              ? 'All messages in this group will be removed from this device. '
                  'You’ll stay in the group and can find it under Groups.'
              : 'All messages with this contact will be removed from this device. '
                  'The contact stays in your contacts.',
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
                await widget.chatService.clearMessages(widget.channelId);
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Could not clear messages: $e')),
                );
                return;
              }
              if (!context.mounted) return;
              Navigator.of(context).pop();
            },
            child: Text(
              'Clear',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmLeave(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave group?'),
        content: const Text(
          'You’ll stop receiving messages from this group. '
          'Someone will need to add you back to rejoin.',
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
              Navigator.of(context).pop();
            },
            child: Text(
              'Leave',
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
            style: textTheme.titleSmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        if (loading)
          const Padding(
            padding: EdgeInsets.all(kSpaceLg),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          for (final m in members) _MemberTile(member: m, isYou: m.userId == localUserId),
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
    final name = isYou
        ? 'You'
        : (member.contact?.displayLabel ?? 'Unknown');
    final subtitle = member.role == 'owner' ? 'Owner' : null;
    return ListTile(
      leading: Avator(
        text: name,
        width: kAvatarMd,
        height: kAvatarMd,
      ),
      title: Text(name),
      subtitle: subtitle != null
          ? Text(subtitle,
              style: TextStyle(color: scheme.onSurfaceVariant))
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
  final bool enabled;

  const _InfoTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.iconColor,
    this.titleColor,
    this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final disabledColor = scheme.onSurface.withValues(alpha: 0.38);
    return ListTile(
      enabled: enabled,
      leading: Icon(
        icon,
        color: enabled
            ? (iconColor ?? scheme.onSurfaceVariant)
            : disabledColor,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: enabled ? titleColor : disabledColor,
        ),
      ),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      trailing: enabled && onTap != null
          ? const Icon(Icons.chevron_right)
          : null,
      onTap: enabled ? onTap : null,
    );
  }
}
