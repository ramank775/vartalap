/// Live location (SYNC_PROTOCOL §21, decision 223).
///
/// A share is a message: content type [kLiveLocationType], its body the
/// share as JSON ([LiveShare]). Later ops act on it: newer positions
/// (TYPE_LIVE_LOCATION_UPDATE) and an early stop. In a 1:1 chat a contact
/// the user allowed can turn the user's live location on and off from
/// their own phone (TYPE_LIVE_LOCATION_CONTROL); the permission lives on
/// this phone and is checked here on every request, never taken from the
/// sender. TYPE_LIVE_LOCATION_PERMISSION only tells the contact's phone,
/// so its chat info can offer the control.
///
/// On Android the positions come from `LiveLocationService` (Kotlin): a
/// foreground service with an ongoing notification and its own Flutter
/// engine (`--live-location`), which hands each fix to [LiveLocation.onFix]
/// there, so sharing goes on with the app closed. Every engine reaches it
/// over [LiveLocationPlatform.channel].
library vartalap.services.live_location;

import 'dart:convert';
import 'dart:math' as math;

import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vartalap/utils/rich_message.dart';
import 'package:vartalap_proto/vartalap_proto.dart' as pb;
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_sync/vartalap_sync.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

/// What a share can run for (WhatsApp's choices); a remote start is held
/// to the longest.
const kLiveDurations = [
  Duration(minutes: 15),
  Duration(hours: 1),
  Duration(hours: 8),
];

/// A point on Earth, or null.
GeoPoint? _point(double lat, double lng, double? accuracyM) =>
    lat.isFinite && lng.isFinite && lat.abs() <= 90 && lng.abs() <= 180
        ? GeoPoint(lat, lng, accuracyM: accuracyM)
        : null;

/// One share's state, as its message body holds it: JSON with short keys.
/// The sharer's create carries `until` and, when it has them, the first
/// position (`lat`, `lng`, `acc` metres, `at`) and `by`; each phone then
/// keeps the newest position in it, and `end` once the sharer stopped.
@immutable
class LiveShare {
  /// When sharing ends, ms since epoch (the sharer's clock).
  final int untilMs;
  final GeoPoint? point;

  /// When [point] was taken, ms since epoch (the sharer's clock).
  final int? atMs;

  /// The contact who turned it on from their phone; null when the sharer
  /// did.
  final String? by;

  /// When the sharer stopped it before [untilMs].
  final int? endedMs;

  const LiveShare({
    required this.untilMs,
    this.point,
    this.atMs,
    this.by,
    this.endedMs,
  });

  bool liveAt(int nowMs) => endedMs == null && nowMs < untilMs;

  static LiveShare? parse(String? body) {
    if (body == null) return null;
    try {
      final m = jsonDecode(body) as Map<String, dynamic>;
      final lat = m['lat'] as num?;
      final lng = m['lng'] as num?;
      return LiveShare(
        untilMs: (m['until'] as num).toInt(),
        point: lat == null || lng == null
            ? null
            : _point(
                lat.toDouble(), lng.toDouble(), (m['acc'] as num?)?.toDouble()),
        atMs: (m['at'] as num?)?.toInt(),
        by: m['by'] as String?,
        endedMs: (m['end'] as num?)?.toInt(),
      );
    } catch (_) {
      return null;
    }
  }

  String encode() => jsonEncode({
        'until': untilMs,
        if (point case final p?) ...{
          'lat': p.lat,
          'lng': p.lng,
          if (p.accuracyM != null) 'acc': p.accuracyM!.round(),
        },
        if (atMs != null) 'at': atMs,
        if (by != null) 'by': by,
        if (endedMs != null) 'end': endedMs,
      });

  LiveShare moved(GeoPoint p, int at) =>
      LiveShare(untilMs: untilMs, point: p, atMs: at, by: by, endedMs: endedMs);

  LiveShare ended(int at) => LiveShare(
      untilMs: untilMs, point: point, atMs: atMs, by: by, endedMs: at);
}

/// The Android half (`LiveLocationService.kt`, registered on the app's
/// engine, a push wake's and the service's own). Tests hand
/// [LiveLocation] a fake.
class LiveLocationPlatform {
  const LiveLocationPlatform();

  static const channel = MethodChannel('vartalap/live_location');

  /// Start the foreground service, or have a running one re-read the
  /// shares. 'started', or why not: 'permission' (no location access, or
  /// with [background] not "all the time"), 'off' (location is off) or
  /// 'refused' (Android would not start it). Unless started, a
  /// [refusedTitle] goes up as a notification asking to open the app.
  /// [title]: a contact's start, which the notification announces at once
  /// (with a sound), before the service's engine is up.
  Future<String> start({
    bool background = false,
    String? refusedTitle,
    String? title,
  }) async {
    try {
      return await channel.invokeMethod<String>('start', {
            'background': background,
            'refusedTitle': refusedTitle,
            'title': title,
          }) ??
          'refused';
    } on PlatformException {
      return 'refused';
    } on MissingPluginException {
      return 'refused';
    }
  }

  /// Shares changed in this engine: the service re-reads them (and stops
  /// once none is left), and the other engines' screens refresh.
  Future<void> changed() async {
    try {
      await channel.invokeMethod<void>('changed');
    } on PlatformException {
      // nothing listening
    } on MissingPluginException {
      // no Android side (tests, desktop)
    }
  }

  /// The service's own engine is up and can take fixes.
  static Future<void> ready() async {
    try {
      await channel.invokeMethod<void>('ready');
    } on MissingPluginException {
      // not started by the service
    }
  }
}

/// A running share of this phone's (or another sharer's, [LiveLocation.shares]).
typedef LiveShareRow = ({String messageId, String channelId, LiveShare share});

class LiveLocation {
  /// The signed-in account's, set by `AppServices.openAccount`: widgets
  /// that get no service passed read it, as with `AssetCache.instance`.
  static LiveLocation? instance;

  final ChatStore store;
  final String selfUserId;

  /// The scheduler's `tickSoon`: what this queues goes out now.
  final void Function() tick;
  final Clock clock;
  final LiveLocationPlatform platform;
  final Uuid7Gen _ids;

  LiveLocation({
    required this.store,
    required this.selfUserId,
    required this.tick,
    this.clock = Clock.system,
    this.platform = const LiveLocationPlatform(),
  }) : _ids = Uuid7Gen(userIdBits: Uuid7Gen.parseUserIdHex(selfUserId));

  // --- Remote on/off permission --------------------------------------------

  /// Per contact, on this phone only: may they turn our live location on
  /// and off (`i_allow`), and have they said we may turn theirs
  /// (`allows_me`). Made here, like the crypto records' table, so no
  /// store migration is needed.
  late final Future<void> _table = store.db.execute('''
    CREATE TABLE IF NOT EXISTS live_location_grants (
      user_id   TEXT PRIMARY KEY,
      i_allow   INTEGER NOT NULL DEFAULT 0,
      allows_me INTEGER NOT NULL DEFAULT 0
    )''');

  Future<bool> _flag(String userId, String column) async {
    await _table;
    final rows = await store.db.query('live_location_grants',
        columns: [column], where: 'user_id = ?', whereArgs: [userId]);
    return rows.firstOrNull?[column] == 1;
  }

  Future<void> _setFlag(String userId, String column, bool on) async {
    await _table;
    await store.db.rawInsert(
        'INSERT INTO live_location_grants (user_id, $column) VALUES (?, ?) '
        'ON CONFLICT(user_id) DO UPDATE SET $column = excluded.$column',
        [userId, on ? 1 : 0]);
  }

  /// May [userId] turn this phone's live location on and off? Read on
  /// every request, so a revoke counts at once, in every engine.
  Future<bool> allows(String userId) => _flag(userId, 'i_allow');

  /// Has [userId] let this phone turn theirs on and off?
  Future<bool> allowedBy(String userId) => _flag(userId, 'allows_me');

  /// The chat-info switch: let [peer] turn ours on and off, or no longer,
  /// and tell their phone so its chat info shows the control.
  Future<void> allow(String peer, bool allowed) async {
    await _setFlag(peer, 'i_allow', allowed);
    await store.enqueueOutboundOp(_op(
      dmChannelId(selfUserId, peer),
      pb.ChatPayload(
        version: 1,
        type: pb.ChatPayloadType.TYPE_LIVE_LOCATION_PERMISSION,
        liveLocationAllowed: allowed,
      ),
      peer: peer,
    ));
    tick();
  }

  /// Ask [peer]'s phone to turn their live location on in our chat for
  /// [duration], or off (null). Their phone decides: it acts only if it
  /// allows us.
  Future<void> remote(String peer, Duration? duration) async {
    await store.enqueueOutboundOp(_op(
      dmChannelId(selfUserId, peer),
      pb.ChatPayload(
        version: 1,
        type: pb.ChatPayloadType.TYPE_LIVE_LOCATION_CONTROL,
        liveLocationDurationSec: duration?.inSeconds,
      ),
      peer: peer,
    ));
    tick();
  }

  // --- Sharing ---------------------------------------------------------------

  /// Running shares of [author] (this phone by default), in [channelId]
  /// only when given.
  Future<List<LiveShareRow>> shares({String? channelId, String? author}) async {
    final rows = await store.db.query(
      'messages',
      columns: const ['message_id', 'channel_id', 'body'],
      where: 'author_user_id = ? AND content_type = ? AND tombstoned = 0'
          '${channelId == null ? '' : ' AND channel_id = ?'}',
      whereArgs: [
        author ?? selfUserId,
        kLiveLocationType,
        if (channelId != null) channelId,
      ],
    );
    final now = clock.nowMs();
    return [
      for (final r in rows)
        if (LiveShare.parse(r['body'] as String?) case final s?
            when s.liveAt(now))
          (
            messageId: r['message_id'] as String,
            channelId: r['channel_id'] as String,
            share: s,
          ),
    ];
  }

  /// Start sharing in [channelId] for [duration]: the share's message
  /// goes out now, with [point] when the position is known, and the
  /// service sends the rest. [by]: the contact who turned it on from their
  /// phone. Returns the platform's answer ([LiveLocationPlatform.start]);
  /// a share that could not start is stopped again.
  Future<String> share(
    String channelId,
    Duration duration, {
    GeoPoint? point,
    String? by,
    String? refusedTitle,
    String? title,
  }) async {
    final now = clock.nowMs();
    final id = _ids.next(nowMs: now);
    final body = LiveShare(
      untilMs: now + duration.inMilliseconds,
      point: point,
      atMs: point == null ? null : now,
      by: by,
    ).encode();
    await store.enqueueLocalMessage(
      message: MessageRow(
        messageId: id,
        channelId: channelId,
        authorUserId: selfUserId,
        body: body,
        contentType: kLiveLocationType,
        replyToMessageId: null,
        clientTimestampMs: now,
        serverTimestampMs: null,
        state: MessageState.pending,
        stateUpdatedAt: now,
        isEdited: false,
        lastEditMs: null,
        tombstoned: false,
        tombstonePendingUntil: null,
      ),
      // A message like any other: it shows a notification and wakes.
      op: _op(
        channelId,
        pb.ChatPayload(
          version: 1,
          type: pb.ChatPayloadType.TYPE_MESSAGE_CREATE,
          messageId: uuidBytes(id),
          body: body,
          contentType: kLiveLocationType,
        ),
        messageId: id,
      ),
      nowMs: now,
    );
    tick();
    final started = await platform.start(
        background: by != null, refusedTitle: refusedTitle, title: title);
    if (started != 'started') await stop(id);
    return started;
  }

  /// Stop sharing [messageId] before its end time. Nothing for one that
  /// is not this phone's or no longer runs.
  Future<void> stop(String messageId) async {
    if (!await _end(messageId)) return;
    tick();
    await platform.changed();
  }

  /// The ongoing notification's Stop: every share of this phone's. The
  /// service waits for the stops to go out, so no [LiveLocationPlatform.changed].
  Future<void> stopAll() async {
    for (final s in await shares()) {
      await _end(s.messageId);
    }
    tick();
  }

  Future<bool> _end(String messageId) async {
    final row = await store.fetchMessage(messageId);
    final share = LiveShare.parse(row?.body);
    final now = clock.nowMs();
    if (row == null ||
        row.authorUserId != selfUserId ||
        row.contentType != kLiveLocationType ||
        share == null ||
        !share.liveAt(now)) {
      return false;
    }
    await _setBody(messageId, share.ended(now));
    await store.enqueueOutboundOp(_op(
      row.channelId,
      pb.ChatPayload(
        version: 1,
        type: pb.ChatPayloadType.TYPE_LIVE_LOCATION_STOP,
        messageId: uuidBytes(messageId),
      ),
    ));
    return true;
  }

  /// Positions queued but not yet sent (no network), per share: a newer
  /// one replaces it, so a phone that was offline sends where it is, not
  /// where it has been.
  final Map<String, String> _unsent = {};

  /// A new position from the service: into every running share, here and
  /// on the wire.
  Future<void> onFix(GeoPoint point, int atMs) async {
    for (final s in await shares()) {
      await _setBody(s.messageId, s.share.moved(point, atMs));
      final stale = _unsent.remove(s.messageId);
      if (stale != null) {
        await store.db.delete('outbound_ops',
            where: "op_id = ? AND status IN ('pending', 'retrying')",
            whereArgs: [stale]);
      }
      final op = _op(
        s.channelId,
        pb.ChatPayload(
          version: 1,
          type: pb.ChatPayloadType.TYPE_LIVE_LOCATION_UPDATE,
          messageId: uuidBytes(s.messageId),
          liveLocationPoint: pb.LiveLocationPoint(
            lat: point.lat,
            lng: point.lng,
            accuracyM: point.accuracyM?.round(),
            atMs: fixnum.Int64(atMs),
          ),
        ),
      );
      _unsent[s.messageId] = op.opId;
      await store.enqueueOutboundOp(op);
    }
    tick();
  }

  /// What the service's notification says, or null once nothing is
  /// shared (it stops). A share whose time is up simply drops out.
  Future<Map<String, Object?>?> status() async {
    final all = await shares();
    if (all.isEmpty) return null;
    final remote = all.where((s) => s.share.by != null).firstOrNull;
    return {
      'title': remote == null
          ? 'Sharing live location'
          : '${await _chatName(remote.channelId)} turned on your live location',
      'text': all.length == 1
          ? 'With ${await _chatName(all.single.channelId)}'
          : 'In ${all.length} chats',
      'until': all.map((s) => s.share.untilMs).reduce(math.max),
      'remote': remote != null,
    };
  }

  /// App start: shares still running (the phone restarted, or Android
  /// stopped the service) get the service back; if it cannot run (location
  /// access taken away, location off), they stop, so nobody watches a
  /// position that no longer moves.
  Future<void> resume() async {
    if ((await shares()).isEmpty) return;
    if (await platform.start() != 'started') await stopAll();
  }

  // --- Inbound ---------------------------------------------------------------

  /// `InboundReceiver.liveLocation`: an op on a share, or a contact's
  /// on/off or permission. Every check is this phone's own.
  Future<void> apply(InboundEnvelope env, pb.ChatPayload chat) async {
    final sender = env.senderUserId;
    if (sender.isEmpty || sender == selfUserId) return;
    switch (chat.type) {
      case pb.ChatPayloadType.TYPE_LIVE_LOCATION_UPDATE:
      case pb.ChatPayloadType.TYPE_LIVE_LOCATION_STOP:
        if (chat.messageId.length != 16) return;
        final id = uuidText(chat.messageId);
        final row = await store.fetchMessage(id);
        final share = LiveShare.parse(row?.body);
        // Only its sharer moves or stops a share, in its own chat
        // (SYNC_PROTOCOL §6a.3), and an ended one stays ended.
        if (row == null ||
            share == null ||
            row.authorUserId != sender ||
            row.channelId != env.channelId ||
            row.contentType != kLiveLocationType ||
            share.endedMs != null) {
          return;
        }
        if (chat.type == pb.ChatPayloadType.TYPE_LIVE_LOCATION_STOP) {
          final at = env.serverTimestampMs;
          await _setBody(id, share.ended(at > 0 ? at : clock.nowMs()));
          return;
        }
        final p = chat.liveLocationPoint;
        final point = _point(
            p.lat, p.lng, p.accuracyM == 0 ? null : p.accuracyM.toDouble());
        final at = p.atMs.toInt();
        // Positions can arrive out of order (a pull after a live one).
        if (point == null || at <= (share.atMs ?? 0)) return;
        await _setBody(id, share.moved(point, at));
      case pb.ChatPayloadType.TYPE_LIVE_LOCATION_CONTROL:
        // A 1:1 chat only, from a contact this phone allows: the sender's
        // word is never taken for it.
        if (!isDmChannelId(env.channelId) || !await allows(sender)) {
          debugPrint('Live location: refused an on/off from $sender');
          return;
        }
        final mine = await shares(channelId: env.channelId);
        final seconds = chat.liveLocationDurationSec;
        if (seconds == 0) {
          for (final s in mine) {
            await _end(s.messageId);
          }
          if (mine.isNotEmpty) {
            tick();
            await platform.changed();
          }
          return;
        }
        if (mine.isNotEmpty) return; // already sharing with them
        final name = await _chatName(env.channelId);
        await share(
          env.channelId,
          Duration(seconds: math.min(seconds, kLiveDurations.last.inSeconds)),
          by: sender,
          refusedTitle: '$name asked to see your live location',
          title: '$name turned on your live location',
        );
      case pb.ChatPayloadType.TYPE_LIVE_LOCATION_PERMISSION:
        if (!isDmChannelId(env.channelId)) return;
        await _setFlag(sender, 'allows_me', chat.liveLocationAllowed);
        store.notifyChanged(const {'live_location_grants'});
      default:
        return;
    }
  }

  // ---------------------------------------------------------------------------

  Future<void> _setBody(String messageId, LiveShare share) async {
    await store.db.update('messages', {'body': share.encode()},
        where: 'message_id = ?', whereArgs: [messageId]);
    store.notifyChanged(const {'messages'});
  }

  Future<String> _chatName(String channelId) async =>
      (await store.fetchChannel(channelId))?.title ?? 'A contact';

  /// One queued op. [messageId]: the share it creates, which its ACK
  /// marks sent; the rest settle nothing.
  OutboundOpRow _op(
    String channelId,
    pb.ChatPayload payload, {
    String? peer,
    String? messageId,
  }) {
    final now = clock.nowMs();
    return OutboundOpRow(
      opId: _ids.next(nowMs: now),
      transport: OpTransport.ws,
      kind: OpKind.chatPayload,
      restMethod: null,
      restPath: null,
      resourceId: channelId,
      payload: payload.writeToBuffer(),
      status: OpStatus.pending,
      attempts: 0,
      nextRetryAt: now,
      dispatchedAt: null,
      lastError: null,
      acknowledgedAt: null,
      createdAt: now,
      targetMessageId: messageId,
      targetChannelId: channelId,
      peer: peer,
    );
  }
}

/// The Dart side of [LiveLocationPlatform.channel] in the app's engine
/// and the service's. The service hands over fixes and asks what its
/// notification says ('fix', 'sync'; null stops it); its Stop sends
/// 'stopAll', then [flush] gets the stops out before the engine ends.
/// 'changed': another engine changed a share, so the screens re-read.
void handleLiveLocationCalls({Future<void> Function()? flush}) {
  LiveLocationPlatform.channel.setMethodCallHandler((call) async {
    final live = LiveLocation.instance;
    if (live == null) return null; // signed out or locked: nothing to share
    switch (call.method) {
      case 'fix':
        final m = (call.arguments as Map).cast<String, Object?>();
        final point = _point((m['lat'] as num).toDouble(),
            (m['lng'] as num).toDouble(), (m['accuracy'] as num?)?.toDouble());
        if (point != null) await live.onFix(point, (m['at'] as num).toInt());
        return live.status();
      case 'sync':
        return live.status();
      case 'stopAll':
        await live.stopAll();
        await flush?.call();
        return null;
      case 'changed':
        live.store.notifyChanged(const {'messages'});
        return null;
    }
    return null;
  });
}
