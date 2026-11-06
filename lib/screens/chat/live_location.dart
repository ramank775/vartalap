/// Live location's screens (SYNC_PROTOCOL §21): the attach sheet's
/// choice, how long to share, and the view a bubble opens. The bubble is
/// [LiveLocationCard], with the other cards in rich_messages.dart.
///
/// No map in the app: no Google SDK and no API key, and free map tiles
/// do not allow an app's traffic. "Open in Maps" hands the position to
/// whatever maps app the phone has (a `geo:` link), like a shared
/// location.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vartalap/screens/chat/rich_messages.dart';
import 'package:vartalap/services/live_location.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap_store/vartalap_store.dart';

String _time(BuildContext context, int ms) =>
    TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(ms))
        .format(context);

/// "Live until 10:42", or that it ended.
String liveUntilLabel(BuildContext context, LiveShare share, int nowMs) =>
    share.liveAt(nowMs)
        ? 'Live until ${_time(context, share.untilMs)}'
        : 'Live location ended';

/// How fresh the position is: "Updated just now", "Updated 2 min ago",
/// "Updated at 10:05".
String liveUpdatedLabel(BuildContext context, int? atMs, int nowMs) {
  if (atMs == null) return 'Waiting for the first position';
  final minutes = math.max(0, nowMs - atMs) ~/ 60000;
  if (minutes < 1) return 'Updated just now';
  if (minutes < 60) return 'Updated $minutes min ago';
  return 'Updated at ${_time(context, atMs)}';
}

String liveDurationLabel(Duration d) => d.inMinutes < 60
    ? '${d.inMinutes} minutes'
    : '${d.inHours} ${d.inHours == 1 ? 'hour' : 'hours'}';

void _toast(BuildContext context, String text) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(text)));

/// The attach sheet's Location: live (for a while) or where you are now
/// ([sendCurrent], the one-shot location message).
Future<void> showLocationSheet(
  BuildContext context, {
  required String channelId,
  required Future<void> Function() sendCurrent,
}) async {
  final live = await showModalBottomSheet<bool>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.share_location),
            title: const Text('Share live location'),
            subtitle: const Text('This chat sees where you are, for as '
                'long as you choose'),
            onTap: () => Navigator.of(ctx).pop(true),
          ),
          ListTile(
            leading: const Icon(Icons.location_on_outlined),
            title: const Text('Send your current location'),
            subtitle: const Text('Only where you are now'),
            onTap: () => Navigator.of(ctx).pop(false),
          ),
        ],
      ),
    ),
  );
  if (live == null || !context.mounted) return;
  if (!live) return sendCurrent();
  final duration =
      await pickLiveDuration(context, title: 'Share live location for');
  if (duration == null || !context.mounted) return;
  await shareLiveLocation(context, channelId, duration);
}

/// 15 minutes, 1 hour or 8 hours ([kLiveDurations]).
Future<Duration?> pickLiveDuration(
  BuildContext context, {
  required String title,
}) =>
    showModalBottomSheet<Duration>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  kSpaceMd, kSpaceMd, kSpaceMd, kSpaceSm),
              child: Text(title, style: Theme.of(ctx).textTheme.titleMedium),
            ),
            for (final d in kLiveDurations)
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: Text(liveDurationLabel(d)),
                onTap: () => Navigator.of(ctx).pop(d),
              ),
            const Padding(
              padding: EdgeInsets.fromLTRB(kSpaceMd, 0, kSpaceMd, kSpaceMd),
              child: Text('You can stop sharing at any time.'),
            ),
          ],
        ),
      ),
    );

/// Location access, then the position now (the one-shot location's
/// path), then the share; the service sends the rest.
Future<void> shareLiveLocation(
  BuildContext context,
  String channelId,
  Duration duration,
) async {
  final live = LiveLocation.instance;
  if (live == null) return;
  if (!await Permission.locationWhenInUse.request().isGranted) {
    if (context.mounted) {
      _toast(context, 'Vartalap needs location access to share where you are');
    }
    return;
  }
  // Android 13+: the ongoing notification, with its Stop, needs this.
  await Permission.notification.request();
  if (!context.mounted) return;
  _toast(context, 'Finding your location…');
  final point = await currentLocation();
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  if (point == null) {
    _toast(context, "Couldn't get your location. Is location turned on?");
    return;
  }
  final started = await live.share(channelId, duration, point: point);
  if (started != 'started' && context.mounted) {
    _toast(context, "Couldn't start live location. Please try again.");
  }
}

/// WhatsApp asks before a share stops.
Future<void> confirmStopSharing(
  BuildContext context,
  LiveLocation live,
  String messageId,
) async {
  final stop = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Stop sharing live location?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Stop'),
        ),
      ],
    ),
  );
  if (stop == true) await live.stop(messageId);
}

/// Where a share's sharer is, kept up to date as positions arrive: big
/// text, and one big button to the phone's maps app.
class LiveLocationScreen extends StatefulWidget {
  final String messageId;
  final LiveLocation live;

  const LiveLocationScreen({
    super.key,
    required this.messageId,
    required this.live,
  });

  @override
  State<LiveLocationScreen> createState() => _LiveLocationScreenState();
}

class _LiveLocationScreenState extends State<LiveLocationScreen> {
  MessageRow? _row;
  bool _loaded = false;
  StreamSubscription<Set<String>>? _changes;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _changes = widget.live.store.tableChanges
        .where((t) => t.contains('messages'))
        .listen((_) => _load());
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    _load();
  }

  Future<void> _load() async {
    final row = await widget.live.store.fetchMessage(widget.messageId);
    if (mounted) {
      setState(() {
        _row = row;
        _loaded = true;
      });
    }
  }

  @override
  void dispose() {
    _changes?.cancel();
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final row = _row;
    final share = LiveShare.parse(row?.body);
    final now = DateTime.now().millisecondsSinceEpoch;
    final mine = row?.authorUserId == widget.live.selfUserId;
    final p = share?.point;
    return Scaffold(
      appBar: AppBar(title: const Text('Live location')),
      body: share == null
          ? Center(
              child: _loaded
                  ? const Text('This live location is no longer in the chat')
                  : const CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(kSpaceLg),
              children: [
                Icon(
                  share.liveAt(now)
                      ? Icons.share_location
                      : Icons.location_off_outlined,
                  size: 72,
                  color: scheme.primary,
                ),
                const SizedBox(height: kSpaceMd),
                Text(liveUntilLabel(context, share, now),
                    style: text.headlineSmall, textAlign: TextAlign.center),
                const SizedBox(height: kSpaceSm),
                Text(liveUpdatedLabel(context, share.atMs, now),
                    style: text.titleMedium, textAlign: TextAlign.center),
                if (p != null) ...[
                  const SizedBox(height: kSpaceSm),
                  Text(
                    [
                      '${p.lat.toStringAsFixed(5)}, '
                          '${p.lng.toStringAsFixed(5)}',
                      if (p.accuracyM != null)
                        'Accurate to ${p.accuracyM!.round()} m',
                    ].join('\n'),
                    style: text.bodyLarge
                        ?.copyWith(color: scheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: kSpaceLg),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56)),
                    onPressed: () => openInMaps(p),
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Open in Maps'),
                  ),
                ],
                if (mine && share.liveAt(now)) ...[
                  const SizedBox(height: kSpaceMd),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      foregroundColor: scheme.error,
                    ),
                    onPressed: () => confirmStopSharing(
                        context, widget.live, widget.messageId),
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('Stop sharing'),
                  ),
                ],
              ],
            ),
    );
  }
}
