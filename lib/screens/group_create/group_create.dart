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
    // TODO: implement chatService.createGroup(name, _selectedUserIds)
    // For now, show a placeholder message.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Group creation coming soon in a future update')),
    );
    Navigator.of(context).pop();
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
              decoration: InputDecoration(
                hintText: 'Group name',
                hintStyle: textTheme.headlineSmall?.copyWith(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                border: InputBorder.none,
              ),
            ),
            const SizedBox(height: kSpaceSm),
            Text(
              '${_selectedUserIds.length} participants',
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
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
    final name = contact.resolvedName;

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
