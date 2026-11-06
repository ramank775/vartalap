/// Who can find you by your phone number (decision 223): the step right
/// after the username at signup, and Settings › Privacy. Finding someone
/// by @username is never affected.
library vartalap.screens.login.discoverability;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/device_contacts.dart';
import 'package:vartalap/theme/theme.dart';

/// An address-book entry the chosen list is picked from.
typedef PickableContact = ({String name, List<String> phones});

/// The address book by name, or null without the contacts permission.
typedef ContactsReader = Future<List<PickableContact>?> Function();

String discoverabilityLabel(Discoverability mode) => switch (mode) {
      Discoverability.everyone => 'Everyone',
      Discoverability.chosen => 'Only people I choose',
      Discoverability.nobody => 'Nobody',
    };

/// Asks for the permission, then groups the numbers by contact name.
/// ponytail: two contacts with the same name show as one row with both
/// numbers; pick by contact id if that ever confuses anyone.
Future<List<PickableContact>?> readAddressBook() async {
  if (!await Permission.contacts.request().isGranted) return null;
  final (phones, names) = await readDeviceContacts();
  final byName = <String, List<String>>{};
  for (final phone in phones) {
    byName.putIfAbsent(names[phone] ?? phone, () => []).add(phone);
  }
  return [
    for (final e in byName.entries) (name: e.key, phones: e.value),
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}

class DiscoverabilityScreen extends StatefulWidget {
  final AuthService authService;

  /// Signup: called once the choice is saved. From Settings the screen
  /// pops itself instead.
  final VoidCallback? onDone;
  final ContactsReader readContacts;

  const DiscoverabilityScreen({
    super.key,
    required this.authService,
    this.onDone,
    this.readContacts = readAddressBook,
  });

  @override
  State<DiscoverabilityScreen> createState() => _DiscoverabilityScreenState();
}

class _DiscoverabilityScreenState extends State<DiscoverabilityScreen> {
  late Discoverability _mode = widget.authService.discoverability;
  late List<String> _chosen = widget.authService.chosenPhones;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // another phone of this account may have changed it
    widget.authService.refreshDiscoverability().then((mode) {
      if (mounted && !_saving) setState(() => _mode = mode);
    });
  }

  Future<void> _pick() async {
    final picked = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => ChooseContactsScreen(
          initial: _chosen,
          readContacts: widget.readContacts,
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _chosen = picked;
      _mode = Discoverability.chosen;
      _error = null;
    });
  }

  void _select(Discoverability? mode) {
    if (mode == null) return;
    // the list comes first: an empty "only people I choose" helps nobody
    if (mode == Discoverability.chosen && _chosen.isEmpty) {
      _pick();
      return;
    }
    setState(() {
      _mode = mode;
      _error = null;
    });
  }

  Future<void> _save(bool fromSettings) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.authService.setDiscoverability(_mode,
          chosen: _mode == Discoverability.chosen ? _chosen : null);
      if (!mounted) return;
      widget.onDone?.call();
      if (fromSettings) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not save. Check your connection '
            'and try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _describe(Discoverability mode) => switch (mode) {
        Discoverability.everyone => 'Anyone who has your number saved',
        Discoverability.chosen => _chosen.isEmpty
            ? (_mode == Discoverability.chosen
                ? 'Chosen earlier. Pick again to change them.'
                : 'People you pick from your contacts')
            : '${_chosen.length} '
                '${_chosen.length == 1 ? 'number' : 'numbers'} chosen',
        Discoverability.nobody => 'People can find you only by your @username',
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    // Pushed from Settings → a back arrow; at signup → none.
    final fromSettings = ModalRoute.of(context)?.canPop ?? false;
    final canSave =
        !_saving && (_mode != Discoverability.chosen || _chosen.isNotEmpty);

    return PopScope(
      canPop: fromSettings,
      child: Scaffold(
        appBar: fromSettings ? AppBar() : null,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                      kSpaceLg, kSpaceLg, kSpaceLg, 0),
                  children: [
                    Icon(Icons.person_search_outlined,
                        size: 48, color: scheme.primary),
                    const SizedBox(height: kSpaceMd),
                    Text('Who can find you by your number?',
                        style: text.headlineSmall),
                    const SizedBox(height: kSpaceSm),
                    Text(
                      'Your number is never shown to anyone. This decides who '
                      'can find your account when they have your number. '
                      'Anyone can still find you by your @username.',
                      style: text.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: kSpaceMd),
                    RadioGroup<Discoverability>(
                      groupValue: _mode,
                      onChanged: _saving ? (_) {} : _select,
                      child: Column(
                        children: [
                          for (final mode in Discoverability.values)
                            RadioListTile<Discoverability>(
                              value: mode,
                              contentPadding: EdgeInsets.zero,
                              title: Text(discoverabilityLabel(mode)),
                              subtitle: Text(_describe(mode)),
                            ),
                        ],
                      ),
                    ),
                    if (_mode == Discoverability.chosen)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _saving ? null : _pick,
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Choose people'),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(kSpaceLg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null) ...[
                      Text(_error!,
                          textAlign: TextAlign.center,
                          style: text.bodySmall?.copyWith(color: scheme.error)),
                      const SizedBox(height: kSpaceSm),
                    ],
                    FilledButton(
                      onPressed: canSave ? () => _save(fromSettings) : null,
                      child: _saving
                          ? SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: scheme.onPrimary,
                              ),
                            )
                          : Text(fromSettings ? 'Save' : 'Continue'),
                    ),
                    if (!fromSettings) ...[
                      const SizedBox(height: kSpaceSm),
                      Text(
                        'You can change this later in Settings › Privacy.',
                        textAlign: TextAlign.center,
                        style: text.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Picks the numbers that may find you from the address book; pops with
/// the chosen E.164 numbers, or nothing when backed out of.
class ChooseContactsScreen extends StatefulWidget {
  final List<String> initial;
  final ContactsReader readContacts;

  const ChooseContactsScreen({
    super.key,
    required this.initial,
    this.readContacts = readAddressBook,
  });

  @override
  State<ChooseContactsScreen> createState() => _ChooseContactsScreenState();
}

class _ChooseContactsScreenState extends State<ChooseContactsScreen> {
  late final Set<String> _selected = {...widget.initial};
  late Future<List<PickableContact>?> _contacts = widget.readContacts();
  String _query = '';

  void _toggle(PickableContact contact) {
    final all = contact.phones.every(_selected.contains);
    if (!all &&
        _selected.union(contact.phones.toSet()).length > kChosenPhonesMax) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('You can choose up to $kChosenPhonesMax numbers.')));
      return;
    }
    setState(() => all
        ? _selected.removeAll(contact.phones)
        : _selected.addAll(contact.phones));
  }

  bool _matches(PickableContact c) {
    final q = _query.trim().toLowerCase();
    return q.isEmpty ||
        c.name.toLowerCase().contains(q) ||
        c.phones.any((p) => p.contains(q));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose people'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_selected.toList()),
            child: const Text('Done'),
          ),
        ],
      ),
      body: FutureBuilder<List<PickableContact>?>(
        future: _contacts,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final contacts = snap.data;
          if (contacts == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(kSpaceLg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Allow Vartalap to read your contacts to choose people.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: kSpaceMd),
                    FilledButton(
                      onPressed: () =>
                          setState(() => _contacts = widget.readContacts()),
                      child: const Text('Allow'),
                    ),
                  ],
                ),
              ),
            );
          }
          final shown = contacts.where(_matches).toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    kSpaceMd, kSpaceSm, kSpaceMd, kSpaceSm),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search name or number',
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: kSpaceMd),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${_selected.length} chosen. Only these numbers can find '
                    'you by your number.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
              Expanded(
                child: contacts.isEmpty
                    ? const Center(child: Text('No contacts with a number.'))
                    : ListView.builder(
                        itemCount: shown.length,
                        itemBuilder: (context, i) {
                          final c = shown[i];
                          return CheckboxListTile(
                            value: c.phones.every(_selected.contains),
                            onChanged: (_) => _toggle(c),
                            title: Text(c.name),
                            subtitle: Text(c.phones.join(', ')),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
