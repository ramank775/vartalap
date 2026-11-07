/// Labels (decision 223): Family, Friends, Close and any the user adds.
/// They stay on this phone: they pick who a timeline post goes to and
/// who sees your last seen, and filter the chat list; the server never
/// learns of them (it gets user ids).
library vartalap.screens.labels;

import 'package:flutter/material.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/avator.dart';
import 'package:vartalap/widgets/compact_tiles.dart';
import 'package:vartalap/widgets/name_dialog.dart';
import 'package:vartalap_store/vartalap_store.dart';

String _people(int n) => n == 1 ? '1 person' : '$n people';

Future<String?> _askName(BuildContext context, String title,
        [String initial = '']) =>
    showDialog<String>(
      context: context,
      builder: (_) => NameDialog(
          title: title, initial: initial, maxLength: 30, hint: 'Label name'),
    );

/// Rename [label]; the new name, or null when unchanged.
Future<String?> _rename(
    BuildContext context, ChatService chat, Label label) async {
  final name = await _askName(context, 'Rename label', label.name);
  if (name == null || name.isEmpty || name == label.name) return null;
  await chat.renameLabel(label.labelId, name);
  return name;
}

/// Delete [label] once confirmed; whether it went.
Future<bool> _delete(
    BuildContext context, ChatService chat, Label label) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Delete "${label.name}"?'),
      content: const Text('The people in it and your chats with them stay. '
          'Only the label goes.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  await chat.deleteLabel(label.labelId);
  return true;
}

/// Rename and Delete, behind ⋮.
Widget _labelMenu(BuildContext context, ChatService chat, Label label,
        {VoidCallback? onDeleted,
        ValueChanged<String>? onRenamed,
        Color? iconColor}) =>
    PopupMenuButton<String>(
      tooltip: 'More',
      iconColor: iconColor,
      onSelected: (v) async {
        if (v == 'rename') {
          final name = await _rename(context, chat, label);
          if (name != null) onRenamed?.call(name);
        } else if (await _delete(context, chat, label)) {
          onDeleted?.call();
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'rename', child: Text('Rename')),
        PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );

/// The one place labels are managed (WhatsApp's Lists): each with how
/// many people carry it; add, rename, delete; tap one to choose who is
/// in it.
class LabelsScreen extends StatefulWidget {
  final ChatService chatService;

  const LabelsScreen({super.key, required this.chatService});

  @override
  State<LabelsScreen> createState() => _LabelsScreenState();
}

class _LabelsScreenState extends State<LabelsScreen> {
  late final Stream<List<Label>> _labels = widget.chatService.watchLabels();

  void _open(Label label) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => LabelMembersScreen(
            chatService: widget.chatService, label: label),
      ));

  /// A new label goes straight to choosing its people.
  Future<void> _add() async {
    final name = await _askName(context, 'New label');
    if (name == null || name.isEmpty) return;
    final id = await widget.chatService.createLabel(name);
    if (mounted) _open(Label(labelId: id, name: name));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chat = widget.chatService;
    return Scaffold(
      appBar: AppBar(title: const Text('Labels')),
      body: StreamBuilder<List<Label>>(
        stream: _labels,
        builder: (context, snap) {
          final labels = snap.data ?? const <Label>[];
          return compactTiles(ListView(
            // the FAB, then Android's own bar (edge to edge)
            padding: EdgeInsets.only(
                bottom: 88 + MediaQuery.paddingOf(context).bottom),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    kSpaceMd, kSpaceSm, kSpaceMd, kSpaceSm),
                child: Text(
                  'Labels stay on this phone. Use them to find chats '
                  'quickly, and to choose who sees a timeline post or '
                  'your last seen.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
              if (snap.hasData && labels.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(kSpaceMd),
                  child: Text('No labels yet. Tap New label to make one.',
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                ),
              for (final label in labels)
                ListTile(
                  leading: Icon(Icons.label_outline, color: scheme.primary),
                  title: Text(label.name),
                  subtitle: Text(_people(label.userIds.length)),
                  onTap: () => _open(label),
                  trailing: _labelMenu(context, chat, label),
                ),
            ],
          ));
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('New label'),
      ),
    );
  }
}

/// Who carries one label: its people first, then every other contact,
/// with a search. Each tick is saved at once, so there is no Save to
/// forget. Rename and Delete sit in ⋮.
class LabelMembersScreen extends StatefulWidget {
  final ChatService chatService;
  final Label label;

  const LabelMembersScreen({
    super.key,
    required this.chatService,
    required this.label,
  });

  @override
  State<LabelMembersScreen> createState() => _LabelMembersScreenState();
}

class _LabelMembersScreenState extends State<LabelMembersScreen> {
  late final Set<String> _members = {...widget.label.userIds};
  late String _name = widget.label.name;
  final _search = TextEditingController();

  /// Ordered once, so a tick does not move the row under the finger.
  late final Future<List<ContactRow>> _contacts =
      widget.chatService.discoverContacts().then((all) => [
            ...all.where((c) => _members.contains(c.userId)),
            ...all.where((c) => !_members.contains(c.userId)),
          ]);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _toggle(String userId, bool on) async {
    setState(() => on ? _members.add(userId) : _members.remove(userId));
    await widget.chatService
        .setLabelMembers(widget.label.labelId, {..._members});
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_name),
            Text(_people(_members.length),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).appBarTheme.foregroundColor)),
          ],
        ),
        actions: [
          _labelMenu(
            context,
            widget.chatService,
            Label(labelId: widget.label.labelId, name: _name),
            onRenamed: (name) => setState(() => _name = name),
            onDeleted: () => Navigator.of(context).pop(),
            // M3 colours it onSurfaceVariant, dark on the green bar
            iconColor: Theme.of(context).appBarTheme.foregroundColor,
          ),
        ],
      ),
      body: FutureBuilder<List<ContactRow>>(
        future: _contacts,
        builder: (context, snap) {
          final contacts = snap.data ?? const <ContactRow>[];
          if (snap.connectionState == ConnectionState.done &&
              contacts.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(kSpaceXl),
                child: Text('No contacts on Vartalap yet',
                    textAlign: TextAlign.center),
              ),
            );
          }
          final shown = q.isEmpty
              ? contacts
              : [
                  for (final c in contacts)
                    if (c.displayLabel.toLowerCase().contains(q) ||
                        (c.username ?? '').toLowerCase().contains(q))
                      c,
                ];
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  kSpaceMd, kSpaceSm, kSpaceMd, kSpaceXs),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search name or @username',
                  isDense: true,
                ),
              ),
            ),
            Expanded(
              child: compactTiles(ListView.builder(
                itemCount: shown.length,
                itemBuilder: (context, i) {
                  final c = shown[i];
                  return CheckboxListTile(
                    value: _members.contains(c.userId),
                    onChanged: (on) => _toggle(c.userId, on ?? false),
                    secondary: Avator(
                      text: c.displayLabel,
                      seed: personSeed(context, c.userId),
                      avatarUrl: c.avatarUrl,
                      width: kAvatarMd,
                      height: kAvatarMd,
                    ),
                    title: Text(c.displayLabel),
                  );
                },
              )),
            ),
          ]);
        },
      ),
    );
  }
}

/// "Labels" on a person's info screen: which they carry; a tap picks.
class ContactLabelsTile extends StatelessWidget {
  final ChatService chatService;
  final String userId;

  const ContactLabelsTile({
    super.key,
    required this.chatService,
    required this.userId,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return StreamBuilder<List<Label>>(
      stream: chatService.watchLabels(),
      builder: (context, snap) {
        final labels = snap.data ?? const <Label>[];
        final mine = [
          for (final l in labels)
            if (l.userIds.contains(userId)) l.name
        ];
        return ListTile(
          leading: Icon(Icons.label_outline, color: scheme.onSurfaceVariant),
          title: const Text('Labels'),
          subtitle: Text(mine.isEmpty ? 'None' : mine.join(', ')),
          onTap: () => _pick(context, labels),
        );
      },
    );
  }

  Future<void> _pick(BuildContext context, List<Label> labels) async {
    final picked = await showDialog<Set<int>>(
      context: context,
      builder: (_) => LabelPicker(
        labels: labels,
        initial: {
          for (final l in labels)
            if (l.userIds.contains(userId)) l.labelId
        },
        onManage: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => LabelsScreen(chatService: chatService),
        )),
      ),
    );
    if (picked != null) await chatService.setContactLabels(userId, picked);
  }
}

/// Tick labels: a person's, or whose people see your last seen.
class LabelPicker extends StatefulWidget {
  final String title;
  final List<Label> labels;
  final Set<int> initial;
  final VoidCallback onManage;

  const LabelPicker({
    super.key,
    this.title = 'Labels',
    required this.labels,
    required this.initial,
    required this.onManage,
  });

  @override
  State<LabelPicker> createState() => _LabelPickerState();
}

class _LabelPickerState extends State<LabelPicker> {
  late final Set<int> _picked = {...widget.initial};

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        contentPadding: const EdgeInsets.only(top: kSpaceSm),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.labels.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(kSpaceMd),
                  child: Text('No labels yet. Make one in Manage labels.'),
                ),
              for (final l in widget.labels)
                CheckboxListTile(
                  value: _picked.contains(l.labelId),
                  title: Text(l.name),
                  subtitle: Text(_people(l.userIds.length)),
                  onChanged: (on) => setState(() => on == true
                      ? _picked.add(l.labelId)
                      : _picked.remove(l.labelId)),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              widget.onManage();
            },
            child: const Text('Manage labels'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_picked),
            child: const Text('OK'),
          ),
        ],
      );
}
