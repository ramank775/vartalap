/// Contact, location and event messages (decision 133): their bubbles,
/// the event form, and the hand-offs to system apps (contacts, maps,
/// calendar) that make the standard formats worth having.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vartalap/screens/albums/albums.dart';
import 'package:vartalap/screens/chat/live_location.dart';
import 'package:vartalap/services/album_client.dart';
import 'package:vartalap/services/live_location.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/utils/rich_message.dart';
import 'package:vartalap/widgets/location_map.dart';

bool isRichType(String? contentType) =>
    contentType == kContactType ||
    contentType == kLocationType ||
    contentType == kLiveLocationType ||
    contentType == kAlbumType ||
    contentType == kEventType;

/// Current position, or null when location is off, denied or unfixed
/// (MainActivity, platform LocationManager).
Future<GeoPoint?> currentLocation() async {
  try {
    final m = await const MethodChannel('vartalap/location')
        .invokeMapMethod<String, Object?>('current');
    if (m == null) return null;
    return GeoPoint(
      (m['lat'] as num).toDouble(),
      (m['lng'] as num).toDouble(),
      accuracyM: (m['accuracy'] as num?)?.toDouble(),
    );
  } on PlatformException {
    return null;
  }
}

/// Body of a bubble whose `content_type` is one of [isRichType].
/// [onMessage] opens a chat with a shared contact (the screen owns the
/// lookup and navigation).
class RichMessageView extends StatelessWidget {
  final String contentType;
  final String body;
  final Color tint;

  /// The bubble's time + tick, set above the card's buttons.
  final Widget? footer;
  final ValueChanged<String>? onMessage;

  /// A live location's message, and whether it is this phone's share:
  /// its view follows the message, and its sharer can stop it.
  final String? messageId;
  final bool mine;

  /// An event's answers (user_id → going), ours among them as
  /// [selfUserId]; [onRsvp] answers (decision 134), [nameOf] names who.
  final Map<String, bool> rsvps;
  final String? selfUserId;
  final ValueChanged<bool>? onRsvp;
  final String Function(String userId)? nameOf;

  const RichMessageView({
    super.key,
    required this.contentType,
    required this.body,
    required this.tint,
    this.footer,
    this.onMessage,
    this.messageId,
    this.mine = false,
    this.rsvps = const {},
    this.selfUserId,
    this.onRsvp,
    this.nameOf,
  });

  @override
  Widget build(BuildContext context) => switch (contentType) {
        kContactType => _ContactCard(
            vcard: body, tint: tint, footer: footer, onMessage: onMessage),
        kLocationType => _LocationCard(
            point: GeoPoint.parse(body), tint: tint, footer: footer),
        kLiveLocationType => LiveLocationCard(
            body: body,
            tint: tint,
            footer: footer,
            messageId: messageId,
            mine: mine),
        kAlbumType => _AlbumCard(
            note: AlbumNote.parse(body), tint: tint, footer: footer),
        _ => _EventCard(
            event: EventInfo.parse(body),
            tint: tint,
            footer: footer,
            rsvps: rsvps,
            mine: rsvps[selfUserId],
            onRsvp: onRsvp,
            nameOf: nameOf),
      };
}

/// A 44 px rounded tile with an icon: the location / fallback leading.
Widget _tile(IconData icon, Color tint) => Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: tint),
    );

/// Leading + lines, the time, then a row of actions: the shape all
/// three cards share (WhatsApp's contact card).
class _Card extends StatelessWidget {
  final Widget leading;
  final Color tint;
  final List<Widget> lines;
  final Widget? footer;
  final List<(String, VoidCallback)> actions;

  /// A row of its own above [actions] (an event's Going / Not going).
  final List<(String, VoidCallback)> topActions;
  final VoidCallback? onTap;

  /// Above everything, edge to edge (a location's map).
  final Widget? top;

  const _Card({
    required this.leading,
    required this.tint,
    required this.lines,
    this.footer,
    this.actions = const [],
    this.topActions = const [],
    this.onTap,
    this.top,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final rule = tint.withValues(alpha: 0.15);
    return SizedBox(
      width: 240,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (top != null)
            GestureDetector(
              // The map ignores touch: the tap is the card's.
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: ClipRRect(
                // The bubble's 18 px corner less its 4 px frame.
                borderRadius: BorderRadius.circular(14),
                child: top,
              ),
            ),
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  leading,
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: lines,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 2, 6, 4),
            child: Align(
              alignment: Alignment.centerRight,
              child: footer ?? const SizedBox.shrink(),
            ),
          ),
          for (final row in [topActions, actions])
            if (row.isNotEmpty) ...[
              Divider(
                height: 1,
                thickness: 1,
                indent: 0,
                endIndent: 0,
                color: rule,
              ),
              SizedBox(
                height: 40,
                child: Row(
                  children: [
                    for (final (i, (label, onPressed)) in row.indexed) ...[
                      if (i > 0)
                        VerticalDivider(
                          width: 1,
                          thickness: 1,
                          indent: 8,
                          endIndent: 8,
                          color: rule,
                        ),
                      Expanded(
                        child: TextButton(
                          onPressed: onPressed,
                          style: TextButton.styleFrom(
                            foregroundColor: accent,
                            minimumSize: const Size.fromHeight(40),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: const RoundedRectangleBorder(),
                            textStyle: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          child: Text(label),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
        ],
      ),
    );
  }
}

Text _title(String s, Color tint) => Text(
      s,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: tint, fontSize: 16, fontWeight: FontWeight.w600),
    );

Text _line(String s, Color tint, {int maxLines = 1}) => Text(
      s,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: tint.withValues(alpha: 0.75), fontSize: 13),
    );

/// A pre-filled system-app hand-off (MainActivity `vartalap/intents`);
/// false when no installed app takes it.
Future<bool> _intent(String method, Map<String, Object?> args) async {
  try {
    return await const MethodChannel('vartalap/intents')
            .invokeMethod<bool>(method, args) ??
        false;
  } on PlatformException {
    return false;
  }
}

void _toast(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

class _ContactCard extends StatelessWidget {
  final String vcard;
  final Color tint;
  final Widget? footer;
  final ValueChanged<String>? onMessage;

  const _ContactCard({
    required this.vcard,
    required this.tint,
    this.footer,
    this.onMessage,
  });

  @override
  Widget build(BuildContext context) {
    Contact? contact;
    try {
      contact = FlutterContacts.vCard.import(vcard).firstOrNull;
    } catch (_) {}
    final phones = contact?.phones.map((p) => p.number).toList() ?? const [];
    final name = contactName(vcard);
    return _Card(
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: tint.withValues(alpha: 0.12),
        child: Text(
          name.characters.first.toUpperCase(),
          style: TextStyle(
            color: tint,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      tint: tint,
      footer: footer,
      lines: [
        _title(contactName(vcard), tint),
        for (final p in phones.take(2)) _line(p, tint),
      ],
      actions: [
        if (onMessage != null && phones.isNotEmpty)
          ('Message', () => onMessage!(vcard)),
        if (contact != null)
          (
            'Add contact',
            () async {
              final added = await _intent('addContact', {
                'name': contactName(vcard),
                'phones': phones,
                'email': contact!.emails.firstOrNull?.address,
              });
              if (!added && context.mounted) {
                _toast(context, 'No contacts app to add it to');
              }
            }
          ),
      ],
    );
  }
}

class _LocationCard extends StatelessWidget {
  final GeoPoint? point;
  final Color tint;
  final Widget? footer;

  const _LocationCard({required this.point, required this.tint, this.footer});

  @override
  Widget build(BuildContext context) {
    final p = point;
    if (p == null) {
      return _Card(
        leading: _tile(Icons.location_off_outlined, tint),
        tint: tint,
        footer: footer,
        lines: [_title('Location', tint), _line('Unreadable location', tint)],
      );
    }
    return _Card(
      top: MapThumbnail(point: p),
      leading: _tile(Icons.location_on_outlined, tint),
      tint: tint,
      footer: footer,
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => LocationMapScreen(point: p))),
      lines: [
        _title('Location', tint),
        if (p.accuracyM != null)
          _line('Accurate to ${p.accuracyM!.round()} m', tint),
        _line('${p.lat.toStringAsFixed(5)}, ${p.lng.toStringAsFixed(5)}', tint),
      ],
      actions: [('Open in maps', () => openInMaps(p))],
    );
  }
}

/// A shared location full screen (WhatsApp): the map, where and how
/// accurate, and the hand-off to the phone's maps app.
class LocationMapScreen extends StatelessWidget {
  final GeoPoint point;

  const LocationMapScreen({super.key, required this.point});

  @override
  Widget build(BuildContext context) {
    final p = point;
    return Scaffold(
      appBar: AppBar(title: const Text('Location')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: LocationMap(point: p, interactive: true)),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(kSpaceMd),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    [
                      '${p.lat.toStringAsFixed(5)}, '
                          '${p.lng.toStringAsFixed(5)}',
                      if (p.accuracyM != null)
                        'Accurate to ${p.accuracyM!.round()} m',
                    ].join('\n'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: kSpaceMd),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56)),
                    onPressed: () => openInMaps(p),
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Open in Maps'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Asha created the album Diwali 2026" (decision 233): opens it.
class _AlbumCard extends StatelessWidget {
  final AlbumNote? note;
  final Color tint;
  final Widget? footer;

  const _AlbumCard({required this.note, required this.tint, this.footer});

  @override
  Widget build(BuildContext context) {
    final n = note;
    void open() => openAlbumNote(context, n!);
    return _Card(
      leading: _tile(Icons.photo_library_outlined, tint),
      tint: tint,
      footer: footer,
      onTap: n == null ? null : open,
      lines: [
        _title(n?.title ?? 'Album', tint),
        _line('Created a new album', tint),
      ],
      actions: n == null ? const [] : [('Open album', open)],
    );
  }
}

/// Whatever maps app is installed; the OSM website when there is none.
Future<void> openInMaps(GeoPoint p) async {
  final at = '${p.lat},${p.lng}';
  final opened =
      await launchUrl(Uri.parse('geo:$at?q=$at')).catchError((_) => false);
  if (opened) return;
  await launchUrl(
    Uri.parse('https://www.openstreetmap.org/?mlat=${p.lat}&mlon=${p.lng}'
        '#map=17/${p.lat}/${p.lng}'),
    mode: LaunchMode.externalApplication,
  ).catchError((_) => false);
}

/// A live location share (SYNC_PROTOCOL §21): until when, how fresh the
/// position is, View (the position, kept up to date) and, for its
/// sharer, Stop sharing. Re-reads the clock every 30 s so "Updated 2 min
/// ago" and the end stay true without a new message.
class LiveLocationCard extends StatefulWidget {
  final String body;
  final Color tint;
  final Widget? footer;
  final String? messageId;
  final bool mine;

  const LiveLocationCard({
    super.key,
    required this.body,
    required this.tint,
    this.footer,
    this.messageId,
    this.mine = false,
  });

  @override
  State<LiveLocationCard> createState() => _LiveLocationCardState();
}

class _LiveLocationCardState extends State<LiveLocationCard> {
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tint = widget.tint;
    final share = LiveShare.parse(widget.body);
    if (share == null) {
      return _Card(
        leading: _tile(Icons.location_off_outlined, tint),
        tint: tint,
        footer: widget.footer,
        lines: [
          _title('Live location', tint),
          _line('Unreadable location', tint),
        ],
      );
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final live = share.liveAt(now);
    final id = widget.messageId;
    final service = LiveLocation.instance;
    void view() => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => LiveLocationScreen(messageId: id!, live: service!)));
    final canView =
        id != null && service != null && (live || share.point != null);
    final p = share.point;
    return _Card(
      top: p == null ? null : MapThumbnail(point: p, ended: !live),
      leading: _tile(
          live ? Icons.share_location : Icons.location_off_outlined, tint),
      tint: tint,
      footer: widget.footer,
      onTap: canView ? view : null,
      lines: [
        _title('Live location', tint),
        _line(liveUntilLabel(context, share, now), tint),
        // A sharer's own position is the service's to update, in its own
        // engine: only the people watching get "Updated …".
        if (live && !widget.mine)
          _line(liveUpdatedLabel(context, share.atMs, now), tint),
        if (share.by != null && share.by == service?.selfUserId)
          _line('Turned on by you', tint),
      ],
      actions: [
        if (canView) ('View', view),
        if (live && widget.mine && id != null && service != null)
          ('Stop sharing', () => confirmStopSharing(context, service, id)),
      ],
    );
  }
}

class _EventCard extends StatelessWidget {
  final EventInfo? event;
  final Color tint;
  final Widget? footer;

  /// Who answered what (decision 134); [mine] our own answer, if any.
  final Map<String, bool> rsvps;
  final bool? mine;
  final ValueChanged<bool>? onRsvp;
  final String Function(String userId)? nameOf;

  const _EventCard({
    required this.event,
    required this.tint,
    this.footer,
    this.rsvps = const {},
    this.mine,
    this.onRsvp,
    this.nameOf,
  });

  /// Who is going and who is not, by name.
  void _showAnswers(BuildContext context) {
    final nameOf = this.nameOf ?? (String id) => id;
    List<String> who(bool going) => [
          for (final e in rsvps.entries)
            if (e.value == going) nameOf(e.key),
        ]..sort();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(event?.title.isNotEmpty == true ? event!.title : 'Event'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (label, names) in [
                ('Going', who(true)),
                ('Not going', who(false)),
              ])
                if (names.isNotEmpty) ...[
                  Text('$label (${names.length})',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  for (final n in names) Text(n),
                  const SizedBox(height: 12),
                ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _addToCalendar(BuildContext context, EventInfo e) async {
    final added = await _intent('addEvent', {
      'title': e.title,
      'begin': e.start.millisecondsSinceEpoch,
      'end': e.end?.millisecondsSinceEpoch,
      'location': e.location,
      'description': e.description,
    });
    if (!added && context.mounted) {
      _toast(context, 'No calendar app to add it to');
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = event;
    if (e == null) {
      return _Card(
        leading: _tile(Icons.event_busy_outlined, tint),
        tint: tint,
        footer: footer,
        lines: [_title('Event', tint), _line('Unreadable event', tint)],
      );
    }
    final going = rsvps.values.where((g) => g).length;
    final notGoing = rsvps.length - going;
    final answers = [
      if (going > 0) '$going going',
      if (notGoing > 0) '$notGoing not going',
    ].join(' · ');
    final rsvp = onRsvp;
    final time = TimeOfDay.fromDateTime(e.start).format(context);
    final end = e.end == null
        ? ''
        : ' – ${TimeOfDay.fromDateTime(e.end!).format(context)}';
    return _Card(
      // A tear-off calendar page: month over day.
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              DateFormat.MMM().format(e.start).toUpperCase(),
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
            Text(
              '${e.start.day}',
              style: TextStyle(
                color: tint,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
      tint: tint,
      footer: footer,
      lines: [
        _title(e.title.isEmpty ? 'Event' : e.title, tint),
        _line('${DateFormat.MMMEd().format(e.start)} · $time$end', tint,
            maxLines: 2),
        if (e.location.isNotEmpty) _line(e.location, tint),
        if (e.description.isNotEmpty) _line(e.description, tint, maxLines: 3),
        if (answers.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            answers,
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
      onTap: rsvps.isEmpty ? null : () => _showAnswers(context),
      topActions: [
        if (rsvp != null) ...[
          (mine == true ? '✓ Going' : 'Going', () => rsvp(true)),
          (mine == false ? '✓ Not going' : 'Not going', () => rsvp(false)),
        ],
      ],
      actions: [('Add to calendar', () => _addToCalendar(context, e))],
    );
  }
}

/// New event form; pops the [EventInfo] to send, or null.
class EventComposerScreen extends StatefulWidget {
  const EventComposerScreen({super.key});

  @override
  State<EventComposerScreen> createState() => _EventComposerScreenState();
}

class _EventComposerScreenState extends State<EventComposerScreen> {
  final _title = TextEditingController();
  final _location = TextEditingController();
  final _description = TextEditingController();
  late DateTime _start = _nextHour();
  late DateTime _end = _start.add(const Duration(hours: 1));

  static DateTime _nextHour() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, now.hour + 1);
  }

  @override
  void initState() {
    super.initState();
    _title.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (d == null) return;
    final length = _end.difference(_start);
    setState(() {
      _start = DateTime(d.year, d.month, d.day, _start.hour, _start.minute);
      _end = _start.add(length);
    });
  }

  Future<void> _pickTime({required bool start}) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(start ? _start : _end),
    );
    if (t == null) return;
    setState(() {
      if (start) {
        final length = _end.difference(_start);
        _start = DateTime(_start.year, _start.month, _start.day, t.hour, t.minute);
        _end = _start.add(length);
      } else {
        var end = DateTime(_start.year, _start.month, _start.day, t.hour, t.minute);
        // An end before the start means it runs past midnight.
        if (!end.isAfter(_start)) end = end.add(const Duration(days: 1));
        _end = end;
      }
    });
  }

  void _send() => Navigator.of(context).pop(EventInfo(
        title: _title.text.trim(),
        start: _start,
        end: _end,
        location: _location.text.trim(),
        description: _description.text.trim(),
      ));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('New event'),
      ),
      body: ListView(
        // Clear the Android 15+ gesture/nav bar (edge to edge).
        padding: const EdgeInsets.all(kSpaceMd) +
            EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
        children: [
          TextField(
            controller: _title,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Event name'),
          ),
          const SizedBox(height: kSpaceSm),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_today_outlined),
            title: Text(DateFormat.yMMMEd().format(_start)),
            onTap: _pickDate,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule),
            title: Text('Starts ${TimeOfDay.fromDateTime(_start).format(context)}'),
            onTap: () => _pickTime(start: true),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule_outlined),
            title: Text('Ends ${TimeOfDay.fromDateTime(_end).format(context)}'),
            onTap: () => _pickTime(start: false),
          ),
          TextField(
            controller: _location,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Location (optional)',
              prefixIcon: Icon(Icons.location_on_outlined),
            ),
          ),
          const SizedBox(height: kSpaceSm),
          TextField(
            controller: _description,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Description (optional)'),
          ),
          const SizedBox(height: kSpaceLg),
          FilledButton.icon(
            onPressed: _title.text.trim().isEmpty ? null : _send,
            icon: const Icon(Icons.send_rounded),
            label: const Text('Send event'),
          ),
        ],
      ),
    );
  }
}
