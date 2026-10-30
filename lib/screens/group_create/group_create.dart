/// New group, in WhatsApp's two steps: pick the members, then name the
/// group (and give it a photo). [MemberPickerScreen] is also group
/// info's "Add members".
library vartalap.screens.group_create;

import 'package:flutter/material.dart';
import 'package:vartalap/screens/chat/chat.dart';
import 'package:vartalap/services/asset_cache.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/avator.dart';
import 'package:vartalap_store/vartalap_store.dart';

class GroupCreateScreen extends StatelessWidget {
  final ChatService chatService;
  final AuthService authService;

  const GroupCreateScreen({
    super.key,
    required this.chatService,
    required this.authService,
  });

  @override
  Widget build(BuildContext context) => MemberPickerScreen(
        chatService: chatService,
        title: 'New group',
        doneIcon: Icons.arrow_forward,
        onDone: (context, picked) => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _GroupNameScreen(
              chatService: chatService,
              authService: authService,
              members: picked,
            ),
          ),
        ),
      );
}

/// Contacts on Vartalap, tap to pick; the picked ones line up along the
/// top and [onDone] gets them in the order they were picked.
class MemberPickerScreen extends StatefulWidget {
  final ChatService chatService;
  final String title;
  final IconData doneIcon;

  /// Already in the group, so not offered.
  final Set<String> exclude;
  final void Function(BuildContext context, List<ContactRow> picked) onDone;

  const MemberPickerScreen({
    super.key,
    required this.chatService,
    required this.title,
    required this.doneIcon,
    required this.onDone,
    this.exclude = const {},
  });

  @override
  State<MemberPickerScreen> createState() => _MemberPickerScreenState();
}

class _MemberPickerScreenState extends State<MemberPickerScreen> {
  late final Future<List<ContactRow>> _contacts =
      widget.chatService.discoverContacts();
  final List<ContactRow> _picked = [];

  void _toggle(ContactRow c) => setState(() {
        if (!_picked.any((p) => p.userId == c.userId)) {
          _picked.add(c);
        } else {
          _picked.removeWhere((p) => p.userId == c.userId);
        }
      });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // The bar is primary in light mode, surface in dark.
    final onBar =
        Theme.of(context).appBarTheme.foregroundColor ?? scheme.onSurface;
    // Under "New group"; from Group info the title already says it.
    final hint = _picked.isNotEmpty
        ? '${_picked.length} selected'
        : widget.title == 'Add members'
            ? null
            : 'Add members';
    return Scaffold(
      appBar: AppBar(
        title: hint == null
            ? Text(widget.title)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title),
                  Text(
                    hint,
                    style: TextStyle(
                      fontSize: 13,
                      color: onBar.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
      ),
      body: FutureBuilder<List<ContactRow>>(
        future: _contacts,
        builder: (context, snap) {
          if (!snap.hasData) {
            return snap.hasError
                ? Center(child: Text('Error: ${snap.error}'))
                : const Center(child: CircularProgressIndicator());
          }
          final contacts = [
            for (final c in snap.data!)
              if (!widget.exclude.contains(c.userId)) c,
          ];
          if (contacts.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(kSpaceXl),
                child: Text(
                  widget.exclude.isEmpty
                      ? 'None of your contacts are on Vartalap yet'
                      : 'Everyone in your contacts is already in this group',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            );
          }
          return Column(
            children: [
              if (_picked.isNotEmpty) ...[
                SizedBox(
                  height: 92,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(
                        kSpaceMd, kSpaceMd, kSpaceMd, 0),
                    children: [
                      for (final c in _picked)
                        _PickedChip(contact: c, onRemove: () => _toggle(c)),
                    ],
                  ),
                ),
                const Divider(height: 1, indent: 0),
              ],
              Expanded(
                child: ListView.builder(
                  itemCount: contacts.length,
                  itemBuilder: (_, i) => _ContactTile(
                    contact: contacts[i],
                    picked: _picked.any((p) => p.userId == contacts[i].userId),
                    onTap: () => _toggle(contacts[i]),
                  ),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: _picked.isEmpty
          ? null
          : FloatingActionButton(
              tooltip: 'Next',
              onPressed: () => widget.onDone(context, List.of(_picked)),
              child: Icon(widget.doneIcon),
            ),
    );
  }
}

/// Step two: photo and name on one row, the members below.
class _GroupNameScreen extends StatefulWidget {
  final ChatService chatService;
  final AuthService authService;
  final List<ContactRow> members;

  const _GroupNameScreen({
    required this.chatService,
    required this.authService,
    required this.members,
  });

  @override
  State<_GroupNameScreen> createState() => _GroupNameScreenState();
}

class _GroupNameScreenState extends State<_GroupNameScreen> {
  final _name = TextEditingController();
  String? _photo;
  bool _creating = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final path = await pickPhoto(widget.chatService.assets);
    if (path != null && mounted) setState(() => _photo = path);
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    final messenger = ScaffoldMessenger.of(context);
    if (name.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Give the group a name')),
      );
      return;
    }
    final me = widget.authService.currentUserId;
    if (me == null) return;
    setState(() => _creating = true);
    try {
      final channelId = await widget.chatService.createGroup(
        name: name,
        creatorUserId: me,
        memberUserIds: [for (final m in widget.members) m.userId],
      );
      final photo = _photo;
      if (photo != null) {
        await widget.chatService.setChannelAvatar(
          channelId: channelId,
          path: photo,
          announce: false,
        );
      }
      if (!mounted) return;
      // Back from the new group goes to the chat list, not the pickers.
      await Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            channelId: channelId,
            channelName: name,
            channelKind: 'group',
            chatService: widget.chatService,
            authService: widget.authService,
          ),
        ),
        (route) => route.isFirst,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      messenger.showSnackBar(
        SnackBar(content: Text("Couldn't create the group: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('New group')),
      body: ListView(
        padding: const EdgeInsets.all(kSpaceLg),
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: _pickPhoto,
                child: _photo == null
                    ? CircleAvatar(
                        radius: kAvatarMd / 2,
                        backgroundColor: scheme.surfaceContainerHighest,
                        child: Icon(
                          Icons.add_a_photo_outlined,
                          color: scheme.onSurfaceVariant,
                          semanticLabel: 'Add group photo',
                        ),
                      )
                    : Avator(
                        text: _name.text,
                        avatarUrl: _photo,
                        isGroup: true,
                        width: kAvatarMd,
                        height: kAvatarMd,
                      ),
              ),
              const SizedBox(width: kSpaceMd),
              Expanded(
                child: TextField(
                  controller: _name,
                  autofocus: true,
                  maxLength: 100,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _create(),
                  decoration: const InputDecoration(
                    hintText: 'Group name',
                    counterText: '',
                    filled: false,
                    border: UnderlineInputBorder(),
                    enabledBorder: UnderlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: kSpaceXl),
          Text(
            'Members: ${widget.members.length}',
            style: textTheme.titleSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: kSpaceMd),
          Wrap(
            spacing: kSpaceMd,
            runSpacing: kSpaceMd,
            children: [
              for (final m in widget.members) _MemberBadge(contact: m),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Create group',
        onPressed: _creating ? null : _create,
        child: _creating
            ? const SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.check),
      ),
    );
  }
}

class _MemberBadge extends StatelessWidget {
  final ContactRow contact;
  final Widget? badge;

  const _MemberBadge({required this.contact, this.badge});

  @override
  Widget build(BuildContext context) {
    final name = contact.displayLabel;
    return SizedBox(
      width: 64,
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Avator(
                text: name,
                seed: personSeed(context, contact.userId),
                avatarUrl: contact.avatarUrl,
                width: kAvatarMd,
                height: kAvatarMd,
              ),
              if (badge != null)
                Positioned(right: -4, bottom: -2, child: badge!),
            ],
          ),
          const SizedBox(height: kSpaceXs),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// A picked contact in the strip; tap to put them back.
class _PickedChip extends StatelessWidget {
  final ContactRow contact;
  final VoidCallback onRemove;

  const _PickedChip({required this.contact, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: kSpaceMd),
      child: GestureDetector(
        onTap: onRemove,
        child: _MemberBadge(
          contact: contact,
          badge: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.onSurfaceVariant,
              border: Border.all(color: scheme.surface, width: 2),
            ),
            child: Icon(
              Icons.close,
              size: 12,
              color: scheme.surface,
              semanticLabel: 'Remove ${contact.displayLabel}',
            ),
          ),
        ),
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  final ContactRow contact;
  final bool picked;
  final VoidCallback onTap;

  const _ContactTile({
    required this.contact,
    required this.picked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = contact.displayLabel;
    return ListTile(
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          Avator(
            text: name,
            seed: personSeed(context, contact.userId),
            avatarUrl: contact.avatarUrl,
            width: kAvatarMd,
            height: kAvatarMd,
          ),
          if (picked)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.primary,
                  border: Border.all(color: scheme.surface, width: 2),
                ),
                child: Icon(Icons.check, size: 13, color: scheme.onPrimary),
              ),
            ),
        ],
      ),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      // The handle under a contact-book name; none when the name already
      // is the handle.
      subtitle: contact.username != null && !name.startsWith('@')
          ? Text(
              '@${contact.username}',
              style: TextStyle(color: scheme.onSurfaceVariant),
            )
          : null,
      onTap: onTap,
    );
  }
}
