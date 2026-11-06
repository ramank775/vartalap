/// Chat info (1:1): remote on/off for live location (SYNC_PROTOCOL §21).
///
/// "Let Rahul turn on my live location" is this phone's permission,
/// revocable at any time and checked here whenever Rahul's phone asks.
/// When Rahul has let us, his chat info here offers "Turn on" / "Turn off".
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vartalap/screens/battery/background_access.dart';
import 'package:vartalap/screens/chat/live_location.dart';
import 'package:vartalap/services/live_location.dart';

/// Location while the app is in use, then "all the time" (Android 10's
/// dialog; from Android 11 the system's settings page, where the user
/// picks "Allow all the time"), then notifications so the ongoing one
/// shows (Android 13+). Before Android 10 location access is all of it.
Future<bool> askLocationAllTheTime() async {
  if (!await Permission.locationWhenInUse.request().isGranted) return false;
  if (!await Permission.locationAlways.request().isGranted) return false;
  await Permission.notification.request();
  return true;
}

class LiveLocationControls extends StatefulWidget {
  /// The 1:1 chat with [peerUserId].
  final String channelId;
  final String peerUserId;
  final String peerName;

  /// [LiveLocation.instance] unless given (tests).
  final LiveLocation? live;

  /// The location "all the time" ask; replaced in tests.
  final Future<bool> Function() askAllTheTime;

  const LiveLocationControls({
    super.key,
    required this.channelId,
    required this.peerUserId,
    required this.peerName,
    this.live,
    this.askAllTheTime = askLocationAllTheTime,
  });

  @override
  State<LiveLocationControls> createState() => _LiveLocationControlsState();
}

class _LiveLocationControlsState extends State<LiveLocationControls> {
  LiveLocation? get _live => widget.live ?? LiveLocation.instance;

  /// Null until read.
  bool? _allow;
  bool _allowedBy = false;
  bool _peerSharing = false;
  StreamSubscription<Set<String>>? _changes;

  @override
  void initState() {
    super.initState();
    _changes = _live?.store.tableChanges
        .where(
            (t) => t.contains('messages') || t.contains('live_location_grants'))
        .listen((_) => _load());
    _load();
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final live = _live;
    if (live == null) return;
    final peer = widget.peerUserId;
    final allow = await live.allows(peer);
    final allowedBy = await live.allowedBy(peer);
    final sharing =
        (await live.shares(channelId: widget.channelId, author: peer))
            .isNotEmpty;
    if (!mounted) return;
    setState(() {
      _allow = allow;
      _allowedBy = allowedBy;
      _peerSharing = sharing;
    });
  }

  void _toast(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _setAllow(bool on) async {
    final live = _live!;
    final name = widget.peerName;
    if (!on) {
      await live.allow(widget.peerUserId, false);
      if (mounted) setState(() => _allow = false);
      return;
    }
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Let $name turn on your live location?'),
        content: Text(
          '$name will be able to see where you are, even when you are '
          'not using Vartalap.\n\n'
          'Your phone will always show a notification while it is on, '
          'and you can stop it at any time.\n\n'
          'On the next screen, choose "Allow all the time" for location.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    if (!await widget.askAllTheTime()) {
      if (mounted) {
        _toast('$name can turn it on only if Vartalap may use your '
            'location all the time');
      }
      return;
    }
    await live.allow(widget.peerUserId, true);
    if (!mounted) return;
    setState(() => _allow = true);
    // Starting from a push needs the app left out of battery saving
    // (Android 12+, unless the push came from Google).
    if (backgroundAccess.value?.allowed == false) {
      await askBackgroundAccess(context);
    }
  }

  Future<void> _turnOn() async {
    final name = widget.peerName;
    final duration = await pickLiveDuration(context,
        title: "Turn on $name's live location for");
    if (duration == null || !mounted) return;
    await _live!.remote(widget.peerUserId, duration);
    if (mounted) {
      _toast("Asked $name's phone to share. It starts when their phone "
          'gets the message.');
    }
  }

  Future<void> _turnOff() async {
    await _live!.remote(widget.peerUserId, null);
    if (mounted) _toast("Asked ${widget.peerName}'s phone to stop sharing.");
  }

  @override
  Widget build(BuildContext context) {
    if (_live == null) return const SizedBox.shrink();
    final name = widget.peerName;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(),
        SwitchListTile(
          secondary: const Icon(Icons.share_location),
          title: Text('Let $name turn on my live location'),
          subtitle: Text('$name can see where you are when needed. You '
              'always see a notification and can stop it.'),
          value: _allow ?? false,
          onChanged: _allow == null ? null : _setAllow,
        ),
        if (_allowedBy)
          ListTile(
            leading: const Icon(Icons.person_pin_circle_outlined),
            title: Text("$name's live location"),
            subtitle: Text(_peerSharing
                ? '$name is sharing it with you now'
                : '$name lets you turn it on'),
            trailing: TextButton(
              onPressed: _peerSharing ? _turnOff : _turnOn,
              child: Text(_peerSharing ? 'Turn off' : 'Turn on'),
            ),
          ),
      ],
    );
  }
}
