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

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart' hide PermissionStatus;
import 'package:permission_handler/permission_handler.dart';
import 'package:vartalap/screens/chat/chat.dart';
import 'package:vartalap/screens/contact_info/contact_info.dart';
import 'package:vartalap/screens/group_create/group_create.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/utils/phone_number.dart';
import 'package:vartalap/widgets/avator.dart';
import 'package:vartalap/utils/username.dart';
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

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

  final TextEditingController _search = TextEditingController();

  /// phone_hash → the saved E.164 number, kept in memory only. Lets the
  /// search match digits the user types without the number ever being
  /// rendered or stored (AUTH_CONTRACT §2.5).
  final Map<String, String> _phoneByHash = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _permissionFuture = Permission.contacts.status;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
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
    final (phones, names) = await _readDeviceContacts();
    _phoneByHash
      ..clear()
      ..addEntries(phones.map(
          (p) => MapEntry(sha256.convert(utf8.encode(p)).toString(), p)));
    return widget.chatService.discoverContacts(
      normalizedPhones: phones,
      contactBookNamesByPhone: names,
    );
  }

  /// Contacts tab filter — contact-book name, `@username`, and the
  /// digits of a number already saved on this device. An unsaved number
  /// is never matched and never shown (mockup c1).
  List<ContactRow> _filter(List<ContactRow> all) {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return all;
    final digits = q.replaceAll(RegExp(r'[^0-9]'), '');
    return all.where((c) {
      if (c.displayLabel.toLowerCase().contains(q)) return true;
      if ((c.username ?? '').toLowerCase().contains(q)) return true;
      if (digits.isNotEmpty && c.phoneHash != null) {
        final phone = _phoneByHash[c.phoneHash];
        if (phone != null && phone.replaceAll('+', '').contains(digits)) {
          return true;
        }
      }
      return false;
    }).toList();
  }

  /// Walks the device address book once and returns:
  ///   * `phones` — every readable normalized E.164 phone (input to the
  ///     hashed lookup).
  ///   * `names` — phone → contact-book label, only when the address
  ///     book actually has a non-empty name. The name wins display
  ///     priority over username/userId per AUTH_CONTRACT §2.4 — without
  ///     this map, the UI falls back to whatever the server returned
  ///     (username) and unfortunately to user_id when even that is
  ///     missing.
  Future<(List<String>, Map<String, String>)> _readDeviceContacts() async {
    final contacts = await FlutterContacts.getAll(
      properties: {ContactProperty.phone, ContactProperty.name},
    );
    final phones = <String>{};
    final names = <String, String>{};
    for (final c in contacts) {
      final dn = c.displayName?.trim() ?? '';
      final fn = c.name?.first?.trim() ?? '';
      final label = dn.isNotEmpty ? dn : (fn.isNotEmpty ? fn : null);
      for (final p in c.phones) {
        final raw = (p.normalizedNumber?.isNotEmpty ?? false)
            ? p.normalizedNumber!
            : p.number;
        final normalized = normalizePhoneNumber(raw);
        if (normalized == null) continue;
        phones.add(normalized);
        if (label != null) names.putIfAbsent(normalized, () => label);
      }
    }
    return (phones.toList(), names);
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
        peerName: contact.displayLabel,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            channelId: channelId,
            channelName: contact.displayLabel,
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
          // The handle lookup rides along under the disclosure. It is
          // the only in-app route to somebody who is not in the address
          // book (AUTH_CONTRACT §7.6), and it needs no contacts
          // permission at all — gating it behind one meant a user who
          // declined could never find anybody, with "Skip" dropping
          // them on the Groups tab instead.
          return Column(
            children: [
              Expanded(
                child: _ContactPermissionDisclosure(
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
                ),
              ),
              _FindByUsername(
                chatService: widget.chatService,
                authService: widget.authService,
              ),
            ],
          );
        }
        // Permission granted — fetch on first build.
        _contactsFuture ??= _fetchAndDiscover();
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  kSpaceMd, kSpaceSm, kSpaceMd, kSpaceXs),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search name, @username or phone',
                  isDense: true,
                ),
              ),
            ),
            Expanded(
              child: _ContactsList(
                contactsFuture: _contactsFuture!,
                creating: _creating,
                onTap: _onContactTap,
                onRetry: _loadContacts,
                filter: _filter,
                footer: _FindByUsername(
                  chatService: widget.chatService,
                  authService: widget.authService,
                ),
              ),
            ),
          ],
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
  final List<ContactRow> Function(List<ContactRow>) filter;

  /// Pinned below the rows — the "Not in your contacts" escape hatch.
  final Widget footer;

  const _ContactsList({
    required this.contactsFuture,
    required this.creating,
    required this.onTap,
    required this.onRetry,
    required this.filter,
    required this.footer,
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

        final contacts = filter(snapshot.data ?? []);
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
                  footer,
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          itemCount: contacts.length + 1,
          itemBuilder: (ctx, i) {
            if (i == contacts.length) return footer;
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
    final name = contact.displayLabel;
    // Suppress the @username subtitle when the title already shows it
    // (i.e. when the contact has no contactBookName/displayName so
    // displayLabel itself fell back to "@username"). Otherwise we'd
    // render the same handle twice.
    final subtitle = (contact.username != null && !name.startsWith('@'))
        ? '@${contact.username}'
        : null;
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
// "Not in your contacts" — reach anyone by exact @handle.
// AUTH_CONTRACT §7.6, mockup frame c1.
// ---------------------------------------------------------------------------

class _FindByUsername extends StatefulWidget {
  final ChatService chatService;
  final AuthService authService;

  const _FindByUsername({
    required this.chatService,
    required this.authService,
  });

  @override
  State<_FindByUsername> createState() => _FindByUsernameState();
}

class _FindByUsernameState extends State<_FindByUsername> {
  final TextEditingController _handle = TextEditingController();
  final TextEditingController _key = TextEditingController();

  /// The server told us this handle is gated by a 4-digit key. Only
  /// then does the Key field exist — the design is explicit that it
  /// appears "only when the server says that handle requires one".
  bool _keyRequired = false;
  bool _searching = false;
  String? _error;

  @override
  void dispose() {
    _handle.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    final handle = _handle.text.trim().toLowerCase();
    final invalid = validateUsername(handle);
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final contact = await widget.chatService.findByUsername(
        handle,
        key: _keyRequired ? _key.text.trim() : null,
      );
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ContactInfoScreen(
            contact: contact,
            chatService: widget.chatService,
            authService: widget.authService,
          ),
        ),
      );
    } on AuthClientException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.errorCode == 'USERNAME_KEY_REQUIRED') {
          _keyRequired = true;
          _error = '@$handle asks for a 4-digit key';
        } else if (e.statusCode == 404) {
          // §7.6: a wrong key is deliberately indistinguishable from a
          // handle that does not exist, so this copy covers both.
          _error = _keyRequired
              ? 'No match — check the handle and the key'
              : 'No one on Vartalap uses @$handle';
        } else {
          _error = e.message ?? 'Lookup failed. Try again.';
        }
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Lookup failed. Try again.');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: kSpaceLg),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: kSpaceMd),
          child: Text(
            'Not in your contacts',
            style: text.titleSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              kSpaceMd, kSpaceSm, kSpaceMd, kSpaceXs),
          child: TextField(
            controller: _handle,
            autocorrect: false,
            textCapitalization: TextCapitalization.none,
            onSubmitted: (_) => _lookup(),
            onChanged: (_) {
              // A new handle needs its own key verdict.
              if (_keyRequired || _error != null) {
                setState(() {
                  _keyRequired = false;
                  _error = null;
                });
              }
            },
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.alternate_email_rounded),
              hintText: 'Find by @username',
              isDense: true,
              suffixIcon: IconButton(
                onPressed: _searching ? null : _lookup,
                icon: _searching
                    ? SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.onSurfaceVariant,
                        ),
                      )
                    : const Icon(Icons.arrow_forward),
                tooltip: 'Find',
              ),
            ),
          ),
        ),
        if (_keyRequired)
          Padding(
            padding: const EdgeInsets.fromLTRB(kSpaceMd, 0, kSpaceMd, kSpaceXs),
            child: SizedBox(
              width: 140,
              child: TextField(
                controller: _key,
                keyboardType: TextInputType.number,
                maxLength: 4,
                onSubmitted: (_) => _lookup(),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.lock_outline),
                  hintText: 'Key',
                  counterText: '',
                  isDense: true,
                ),
              ),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(kSpaceMd, 0, kSpaceMd, kSpaceSm),
            child: Text(
              _error!,
              style: text.bodySmall?.copyWith(
                color: _keyRequired ? scheme.onSurfaceVariant : scheme.error,
              ),
            ),
          ),
        const SizedBox(height: kSpaceMd),
      ],
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

class _GroupsTab extends StatefulWidget {
  final ChatService chatService;
  final AuthService authService;

  const _GroupsTab({
    required this.chatService,
    required this.authService,
  });

  @override
  State<_GroupsTab> createState() => _GroupsTabState();
}

class _GroupsTabState extends State<_GroupsTab> {
  /// Created once so this tab's own rebuilds don't resubscribe and
  /// re-run the underlying SQL query.
  Stream<List<ChannelListEntry>>? _groupsStream;

  @override
  void initState() {
    super.initState();
    final userId = widget.authService.currentUserId;
    if (userId != null) {
      _groupsStream =
          widget.chatService.watchMemberChannels(userId: userId, kind: 'group');
    }
  }

  void _openGroup(BuildContext context, ChannelListEntry entry) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          channelId: entry.channelId,
          channelName: entry.title,
          channelKind: 'group',
          chatService: widget.chatService,
          authService: widget.authService,
        ),
      ),
    );
  }

  void _newGroup(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GroupCreateScreen(
          chatService: widget.chatService,
          authService: widget.authService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final userId = widget.authService.currentUserId;
    if (userId == null) {
      return const Center(child: Text('Not signed in.'));
    }

    return StreamBuilder<List<ChannelListEntry>>(
      stream: _groupsStream,
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
    final name = entry.title;
    return ListTile(
      leading: Avator(text: name, width: kAvatarMd, height: kAvatarMd),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: onTap,
    );
  }
}
