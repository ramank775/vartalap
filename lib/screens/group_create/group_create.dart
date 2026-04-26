/// Group creation screen — multi-select contacts + group name.
///
/// Two-step flow:
/// 1. Select contacts from the contact list (multi-select)
/// 2. Enter group name and create
///
/// Group creation is a placeholder until group ops land in
/// vartalap_sync. The UI is ready; the service call is stubbed.
library vartalap.screens.group_create;

import 'package:flutter/material.dart';
import 'package:vartalap/screens/chat/chat.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/avator.dart';
import 'package:vartalap_store/vartalap_store.dart';

class GroupCreateScreen extends StatefulWidget {
  final ChatService chatService;
  final AuthService authService;

  const GroupCreateScreen({
    super.key,
    required this.chatService,
    required this.authService,
  });

  @override
  State<GroupCreateScreen> createState() => _GroupCreateScreenState();
}

class _GroupCreateScreenState extends State<GroupCreateScreen> {
  late Future<List<ContactRow>> _contactsFuture;
  final Set<String> _selectedUserIds = {};
  bool _onNameStep = false;
  final TextEditingController _nameController = TextEditingController();

  /// Cached contacts indexed by user_id so the name step can render
  /// the selected-member chip strip with avatar + name without re-
  /// fetching. Populated from the [_contactsFuture] result.
  final Map<String, ContactRow> _contactsById = {};

  @override
  void initState() {
    super.initState();
    _contactsFuture = widget.chatService.discoverContacts();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _toggleContact(String userId) {
    setState(() {
      if (_selectedUserIds.contains(userId)) {
        _selectedUserIds.remove(userId);
      } else {
        _selectedUserIds.add(userId);
      }
    });
  }

  void _proceedToName() {
    if (_selectedUserIds.isEmpty) return;
    setState(() => _onNameStep = true);
  }

  Future<void> _createGroup() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a group name')),
      );
      return;
    }
    final creatorUserId = widget.authService.currentUserId;
    if (creatorUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not signed in')),
      );
      return;
    }
    try {
      final channelId = await widget.chatService.createGroup(
        name: name,
        creatorUserId: creatorUserId,
        memberUserIds: _selectedUserIds.toList(),
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            channelId: channelId,
            channelName: name,
            channelKind: 'group',
            chatService: widget.chatService,
            authService: widget.authService,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create group: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_onNameStep) return _buildNameStep(context);
    return _buildContactStep(context);
  }

  Widget _buildContactStep(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('New Group'),
            if (_selectedUserIds.isNotEmpty)
              Text(
                '${_selectedUserIds.length} selected',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.normal,
                  color: scheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
          ],
        ),
      ),
      body: FutureBuilder<List<ContactRow>>(
        future: _contactsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final contacts = snapshot.data ?? [];
          for (final c in contacts) {
            _contactsById[c.userId] = c;
          }
          if (contacts.isEmpty) {
            return Center(
              child: Text(
                'No contacts available',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            );
          }
          return ListView.separated(
            itemCount: contacts.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final contact = contacts[i];
              final selected = _selectedUserIds.contains(contact.userId);
              return _SelectableContactTile(
                contact: contact,
                selected: selected,
                onTap: () => _toggleContact(contact.userId),
              );
            },
          );
        },
      ),
      floatingActionButton: _selectedUserIds.isNotEmpty
          ? FloatingActionButton(
              onPressed: _proceedToName,
              child: const Icon(Icons.arrow_forward),
            )
          : null,
    );
  }

  Widget _buildNameStep(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Group Name'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() => _onNameStep = false),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(kSpaceLg),
        child: Column(
          children: [
            const SizedBox(height: kSpaceXl),
            // Group avatar preview
            Container(
              width: kAvatarXl,
              height: kAvatarXl,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.primaryContainer,
              ),
              child: Icon(
                Icons.group,
                size: 40,
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: kSpaceLg),
            TextField(
              controller: _nameController,
              autofocus: true,
              textAlign: TextAlign.center,
              style: textTheme.headlineSmall,
              cursorColor: scheme.primary,
              decoration: InputDecoration(
                hintText: 'Group name',
                hintStyle: textTheme.headlineSmall?.copyWith(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                filled: false,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: kSpaceSm,
                  vertical: kSpaceSm,
                ),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(
                    color: scheme.outlineVariant,
                    width: 1,
                  ),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(
                    color: scheme.primary,
                    width: 2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: kSpaceSm),
            Text(
              '${_selectedUserIds.length} '
              '${_selectedUserIds.length == 1 ? "participant" : "participants"}',
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: kSpaceMd),
            _SelectedMembersStrip(
              userIds: _selectedUserIds.toList(),
              contactsById: _contactsById,
              onRemove: (userId) {
                setState(() {
                  _selectedUserIds.remove(userId);
                  // If everyone got removed, drop back to the picker.
                  if (_selectedUserIds.isEmpty) _onNameStep = false;
                });
              },
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _createGroup,
                child: const Text('Create Group'),
              ),
            ),
            const SizedBox(height: kSpaceLg),
          ],
        ),
      ),
    );
  }
}

/// Horizontally scrollable strip of selected members. Each chip shows
/// the contact's avatar + truncated name with a tap-to-remove "x".
/// Falls back to user_id when the contact row hasn't loaded yet (race
/// during the very first paint).
class _SelectedMembersStrip extends StatelessWidget {
  final List<String> userIds;
  final Map<String, ContactRow> contactsById;
  final ValueChanged<String> onRemove;

  const _SelectedMembersStrip({
    required this.userIds,
    required this.contactsById,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    if (userIds.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 86,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        // Inner padding so the leading and trailing chips don't sit
        // flush against the screen edges and the last chip clips with
        // breathing room rather than mid-letter.
        padding: const EdgeInsets.symmetric(horizontal: kSpaceXs),
        itemCount: userIds.length,
        separatorBuilder: (_, __) => const SizedBox(width: kSpaceMd),
        itemBuilder: (_, i) {
          final userId = userIds[i];
          final contact = contactsById[userId];
          final name = contact?.displayLabel ?? 'Unknown';
          return SizedBox(
            width: 64,
            child: Column(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Avator(text: name, width: kAvatarMd, height: kAvatarMd),
                    Positioned(
                      right: -4,
                      top: -4,
                      child: GestureDetector(
                        onTap: () => onRemove(userId),
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: scheme.surfaceContainerHighest,
                            border: Border.all(
                              color: scheme.outlineVariant,
                              width: 1,
                            ),
                          ),
                          child: Icon(
                            Icons.close,
                            size: 14,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: kSpaceXs),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SelectableContactTile extends StatelessWidget {
  final ContactRow contact;
  final bool selected;
  final VoidCallback onTap;

  const _SelectableContactTile({
    required this.contact,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = contact.displayLabel;

    return ListTile(
      leading: Stack(
        children: [
          Avator(text: name, width: kAvatarMd, height: kAvatarMd),
          if (selected)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.primary,
                  border: Border.all(
                    color: scheme.surface,
                    width: 2,
                  ),
                ),
                child: Icon(
                  Icons.check,
                  size: 12,
                  color: scheme.onPrimary,
                ),
              ),
            ),
        ],
      ),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: contact.username != null
          ? Text(
              '@${contact.username}',
              style: TextStyle(color: scheme.onSurfaceVariant),
            )
          : null,
      tileColor: selected
          ? scheme.primaryContainer.withValues(alpha: 0.2)
          : null,
      onTap: onTap,
    );
  }
}
