/// New-chat picker — two tabs.
///
/// Contacts tab: pick a contact to start (or resume) a DM.
/// Groups tab: pinned "New group" row at the top, then the list of
/// groups the current user is in. Tap a group to open it (re-enter
/// after clearing messages, or jump into a silent group).
///
/// The chat list shows only channels with messages (active
/// conversations). The Groups tab is the canonical surface for "groups
/// I'm in regardless of message state."
library vartalap.screens.new_chat;

import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart' hide PermissionStatus;
import 'package:permission_handler/permission_handler.dart';
import 'package:vartalap/screens/chat/chat.dart';
import 'package:vartalap/screens/group_create/group_create.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/utils/phone_number.dart';
import 'package:vartalap/widgets/avator.dart';
import 'package:vartalap_store/vartalap_store.dart';

class NewChatScreen extends StatefulWidget {
  final ChatService chatService;
  final AuthService authService;
  const NewChatScreen({
    super.key,
    required this.chatService,
    required this.authService,
  });

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('New Chat'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Contacts'),
              Tab(text: 'Groups'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _ContactsTab(
              chatService: widget.chatService,
              authService: widget.authService,
            ),
            _GroupsTab(
              chatService: widget.chatService,
              authService: widget.authService,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Contacts tab
// ---------------------------------------------------------------------------

class _ContactsTab extends StatefulWidget {
  final ChatService chatService;
  final AuthService authService;

  const _ContactsTab({
    required this.chatService,
    required this.authService,
  });

  @override
  State<_ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends State<_ContactsTab>
    with WidgetsBindingObserver {
  bool _creating = false;
  Future<PermissionStatus>? _permissionFuture;
  Future<List<ContactRow>>? _contactsFuture;
  PermissionStatus? _lastStatus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _permissionFuture = Permission.contacts.status;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Re-check permission when the app returns to foreground — the user may
  // have flipped the toggle in system Settings while we were paused.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _maybeRefreshOnResume();
    }
  }

  Future<void> _maybeRefreshOnResume() async {
    final current = await Permission.contacts.status;
    if (!mounted) return;
    if (current != _lastStatus) {
      _lastStatus = current;
      setState(() {
        _permissionFuture = Future.value(current);
        if (current == PermissionStatus.granted && _contactsFuture == null) {
          _contactsFuture = _fetchAndDiscover();
        }
      });
    }
  }

  void _refreshPermission() {
    setState(() {
      _permissionFuture = Permission.contacts.status;
      _contactsFuture = null;
    });
  }

  void _loadContacts() {
    setState(() {
      _contactsFuture = _fetchAndDiscover();
    });
  }

  Future<List<ContactRow>> _fetchAndDiscover() async {
    final phones = await _readDevicePhones();
    return widget.chatService.discoverContacts(normalizedPhones: phones);
  }

  Future<List<String>> _readDevicePhones() async {
    final contacts = await FlutterContacts.getAll(
      properties: {ContactProperty.phone},
    );
    final seen = <String>{};
    for (final c in contacts) {
      for (final p in c.phones) {
        final raw = (p.normalizedNumber?.isNotEmpty ?? false)
            ? p.normalizedNumber!
            : p.number;
        final normalized = normalizePhoneNumber(raw);
        if (normalized != null) seen.add(normalized);
      }
    }
    return seen.toList();
  }

  Future<void> _onContactTap(ContactRow contact) async {
    final localUserId = widget.authService.currentUserId;
    if (localUserId == null) return;
    if (_creating) return;

    setState(() => _creating = true);
    try {
      final channelId = await widget.chatService.startDirectMessage(
        localUserId: localUserId,
        peerUserId: contact.userId,
        peerName: contact.resolvedName,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            channelId: channelId,
            channelName: contact.resolvedName,
            channelKind: 'dm',
            chatService: widget.chatService,
            authService: widget.authService,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create chat: $e')),
      );
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PermissionStatus>(
      future: _permissionFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final status = snapshot.data;
        _lastStatus = status;
        if (status != PermissionStatus.granted) {
          return _ContactPermissionDisclosure(
            status: status,
            onSkip: () => DefaultTabController.of(context).animateTo(1),
            onAllow: () async {
              final granted = await Permission.contacts.request();
              if (granted == PermissionStatus.granted) {
                _refreshPermission();
                _loadContacts();
              } else {
                setState(() {
                  _permissionFuture = Future.value(granted);
                });
              }
            },
            onOpenSettings: () async {
              await openAppSettings();
              _refreshPermission();
            },
          );
        }
        // Permission granted — fetch on first build.
        _contactsFuture ??= _fetchAndDiscover();
        return _ContactsList(
          contactsFuture: _contactsFuture!,
          creating: _creating,
          onTap: _onContactTap,
          onRetry: _loadContacts,
        );
      },
    );
  }
}

class _ContactsList extends StatelessWidget {
  final Future<List<ContactRow>> contactsFuture;
  final bool creating;
  final ValueChanged<ContactRow> onTap;
  final VoidCallback onRetry;

  const _ContactsList({
    required this.contactsFuture,
    required this.creating,
    required this.onTap,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return FutureBuilder<List<ContactRow>>(
      future: contactsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(kSpaceLg),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scheme.errorContainer,
                    ),
                    child: Icon(
                      Icons.error_outline_rounded,
                      size: 36,
                      color: scheme.onErrorContainer,
                    ),
                  ),
                  const SizedBox(height: kSpaceMd),
                  Text(
                    'Could not load contacts',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: kSpaceSm),
                  Text(
                    '${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: kSpaceLg),
                  ElevatedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }

        final contacts = snapshot.data ?? [];
        if (contacts.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(kSpaceLg),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scheme.primaryContainer.withValues(alpha: 0.3),
                    ),
                    child: Icon(
                      Icons.people_outline_rounded,
                      size: 48,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(height: kSpaceMd),
                  Text(
                    'No contacts found',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: kSpaceSm),
                  Text(
                    'None of your contacts are on Vartalap yet.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: kSpaceLg),
                  TextButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh'),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.separated(
          itemCount: contacts.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (ctx, i) {
            final contact = contacts[i];
            return _ContactTile(
              contact: contact,
              onTap: creating ? null : () => onTap(contact),
            );
          },
        );
      },
    );
  }
}

class _ContactTile extends StatelessWidget {
  final ContactRow contact;
  final VoidCallback? onTap;
  const _ContactTile({required this.contact, this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = contact.resolvedName;
    final subtitle = contact.username != null ? '@${contact.username}' : null;
    return ListTile(
      leading: Avator(text: name, width: kAvatarMd, height: kAvatarMd),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          : null,
      onTap: onTap,
    );
  }
}

// ---------------------------------------------------------------------------
// Permission disclosure (Play Store-compliant in-app prompt before the
// system permission dialog).
// ---------------------------------------------------------------------------

class _ContactPermissionDisclosure extends StatelessWidget {
  final PermissionStatus? status;
  final VoidCallback onSkip;
  final VoidCallback onAllow;
  final VoidCallback onOpenSettings;

  const _ContactPermissionDisclosure({
    required this.status,
    required this.onSkip,
    required this.onAllow,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final permanentlyDenied = status == PermissionStatus.permanentlyDenied;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(kSpaceLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.primaryContainer.withValues(alpha: 0.3),
              ),
              child: Icon(
                Icons.contacts_rounded,
                size: 48,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: kSpaceMd),
            Text(
              'Contact Permission Required',
              textAlign: TextAlign.center,
              style: text.titleLarge,
            ),
            const SizedBox(height: kSpaceMd),
            Text(
              'Vartalap needs to access your contacts to show you which of your contacts are using Vartalap.',
              textAlign: TextAlign.center,
              style: text.bodyMedium,
            ),
            const SizedBox(height: kSpaceSm),
            Text(
              'Only phone numbers (hashed with SHA-256) are sent to our server to find matches. Your contact names, photos, and other details stay on this device.',
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: kSpaceSm),
            Text(
              'Phone number hashes are not stored on our servers — they are only used during the lookup.',
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (permanentlyDenied) ...[
              const SizedBox(height: kSpaceMd),
              Container(
                padding: const EdgeInsets.all(kSpaceMd),
                decoration: BoxDecoration(
                  color: scheme.errorContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(kRadiusMd),
                ),
                child: Text(
                  'Contacts permission was denied. Open Settings to enable it.',
                  textAlign: TextAlign.center,
                  style: text.bodySmall?.copyWith(
                    color: scheme.onErrorContainer,
                  ),
                ),
              ),
            ],
            const SizedBox(height: kSpaceLg),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(
                  onPressed: onSkip,
                  child: const Text('Skip'),
                ),
                if (permanentlyDenied)
                  FilledButton.icon(
                    onPressed: onOpenSettings,
                    icon: const Icon(Icons.settings),
                    label: const Text('Open Settings'),
                  )
                else
                  FilledButton.icon(
                    onPressed: onAllow,
                    icon: const Icon(Icons.lock_open),
                    label: const Text('Allow'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Groups tab
// ---------------------------------------------------------------------------

class _GroupsTab extends StatelessWidget {
  final ChatService chatService;
  final AuthService authService;

  const _GroupsTab({
    required this.chatService,
    required this.authService,
  });

  void _openGroup(BuildContext context, ChannelListEntry entry) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          channelId: entry.channelId,
          channelName: entry.name ?? entry.channelId,
          channelKind: 'group',
          chatService: chatService,
          authService: authService,
        ),
      ),
    );
  }

  void _newGroup(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GroupCreateScreen(
          chatService: chatService,
          authService: authService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final userId = authService.currentUserId;
    if (userId == null) {
      return const Center(child: Text('Not signed in.'));
    }

    return StreamBuilder<List<ChannelListEntry>>(
      stream: chatService.watchMemberChannels(userId: userId, kind: 'group'),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final groups = snapshot.data ?? const [];

        return ListView.separated(
          itemCount: groups.length + 1,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (ctx, i) {
            // Pinned action at the top.
            if (i == 0) {
              return ListTile(
                leading: CircleAvatar(
                  radius: kAvatarMd / 2,
                  backgroundColor: scheme.primaryContainer,
                  child: Icon(
                    Icons.group_add,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                title: const Text('New group'),
                onTap: () => _newGroup(context),
              );
            }
            final group = groups[i - 1];
            return _GroupTile(
              entry: group,
              onTap: () => _openGroup(context, group),
            );
          },
        );
      },
    );
  }
}

class _GroupTile extends StatelessWidget {
  final ChannelListEntry entry;
  final VoidCallback onTap;
  const _GroupTile({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = entry.name ?? entry.channelId;
    return ListTile(
      leading: Avator(text: name, width: kAvatarMd, height: kAvatarMd),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: onTap,
    );
  }
}
