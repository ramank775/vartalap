/// Labels (decision 223): Family, Friends, Close and any the user adds.
/// They stay on this phone: they pick who a timeline post goes to and
/// filter the chat list, and the server never learns of them.
library vartalap.screens.labels;

import 'package:flutter/material.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/avator.dart';
import 'package:vartalap/widgets/name_dialog.dart';
import 'package:vartalap_store/vartalap_store.dart';

String _people(int n) => n == 1 ? '1 person' : '$n people';

/// Add, rename and delete labels; tap one to choose who is in it.
class LabelsScreen extends StatefulWidget {
  final ChatService chatService;

  const LabelsScreen({super.key, required this.chatService});

  @override
  State<LabelsScreen> createState() => _LabelsScreenState();
}

class _LabelsScreenState extends State<LabelsScreen> {
  late final Stream<List<Label>> _labels = widget.chatService.watchLabels();

  Future<String?> _askName(String title, [String initial = '']) =>
      showDialog<String>(
        context: context,
        builder: (_) => NameDialog(
            title: title, initial: initial, maxLength: 30, hint: 'Label name'),
      );

  Future<void> _add() async {
    final name = await _askName('New label');
    if (name != null && name.isNotEmpty) {
      await widget.chatService.createLabel(name);
    }
  }

  Future<void> _rename(Label label) async {
    final name = await _askName('Rename label', label.name);
    if (name != null && name.isNotEmpty && name != label.name) {
      await widget.chatService.renameLabel(label.labelId, name);
    }
  }

  Future<void> _delete(Label label) async {
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
    if (ok == true) await widget.chatService.deleteLabel(label.labelId);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Labels')),
      body: StreamBuilder<List<Label>>(
        stream: _labels,
        builder: (context, snap) {
          final labels = snap.data ?? const <Label>[];
          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              Padding(
                padding: const EdgeInsets.all(kSpaceMd),
                child: Text(
                  'Labels stay on this phone. Use them to choose who sees a '
                  'timeline post, and to find chats quickly.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
              for (final label in labels)
                ListTile(
                  leading: Icon(Icons.label_outline, color: scheme.primary),
                  title: Text(label.name),
                  subtitle: Text(_people(label.userIds.length)),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => LabelMembersScreen(
                        chatService: widget.chatService, label: label),
                  )),
                  trailing: PopupMenuButton<String>(
                    tooltip: 'More',
                    onSelected: (v) =>
                        v == 'rename' ? _rename(label) : _delete(label),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'rename', child: Text('Rename')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ),
            ],
          );
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

/// Who carries one label: every contact, ticked or not. Each tick is
/// saved at once, so there is no Save to forget.
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
  late final Future<List<ContactRow>> _contacts =
      widget.chatService.discoverContacts();
  late final Set<String> _members = {...widget.label.userIds};

  Future<void> _toggle(String userId, bool on) async {
    setState(() => on ? _members.add(userId) : _members.remove(userId));
    await widget.chatService
        .setLabelMembers(widget.label.labelId, {..._members});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.label.name)),
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
          return ListView(
            children: [
              for (final c in contacts)
                CheckboxListTile(
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
                ),
            ],
          );
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
      builder: (_) => _LabelPicker(
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

class _LabelPicker extends StatefulWidget {
  final List<Label> labels;
  final Set<int> initial;
  final VoidCallback onManage;

  const _LabelPicker({
    required this.labels,
    required this.initial,
    required this.onManage,
  });

  @override
  State<_LabelPicker> createState() => _LabelPickerState();
}

class _LabelPickerState extends State<_LabelPicker> {
  late final Set<int> _picked = {...widget.initial};

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Labels'),
        contentPadding: const EdgeInsets.only(top: kSpaceSm),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final l in widget.labels)
                CheckboxListTile(
                  value: _picked.contains(l.labelId),
                  title: Text(l.name),
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
