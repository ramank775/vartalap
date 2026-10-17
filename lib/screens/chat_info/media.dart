/// "Media, links and docs" — WhatsApp's three tabs over one channel:
/// photos and videos in a grid, documents, and messages with links,
/// each under month headers, newest first.
///
/// Thumbnails come off the same [AssetCache] the chat bubbles use, so
/// opening this screen after scrolling the thread costs no network.
library vartalap.screens.chat_info.media;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vartalap/screens/chat/voice_note.dart' show mmss;
import 'package:vartalap/services/asset_cache.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/utils/attachment_text.dart';
import 'package:vartalap/widgets/asset_image.dart';
import 'package:vartalap_proto/vartalap_proto.dart' as pb;
import 'package:vartalap_store/vartalap_store.dart';

/// First attachment on a message row, or null. Same shape the chat
/// bubble decodes — a `ChatPayload` holding only `attachments`.
pb.Attachment? firstAttachment(MessageRow m) {
  final bytes = m.attachments;
  if (bytes == null || bytes.isEmpty) return null;
  try {
    final list = pb.ChatPayload.fromBuffer(bytes).attachments;
    return list.isEmpty ? null : list.first;
  } catch (_) {
    return null;
  }
}

/// WhatsApp's section headers: "This month", "Last month", then the
/// month's name, with its year once it is not this year.
String monthLabel(DateTime when, DateTime now) {
  final back = (now.year - when.year) * 12 + now.month - when.month;
  if (back <= 0) return 'This month';
  if (back == 1) return 'Last month';
  return when.year == now.year
      ? DateFormat.MMMM().format(when)
      : DateFormat.yMMMM().format(when);
}

DateTime _sentAt(MessageRow m) => DateTime.fromMillisecondsSinceEpoch(
      m.serverTimestampMs ?? m.clientTimestampMs,
    );

String _nameOf(pb.Attachment? a) =>
    (a == null || a.filename.isEmpty) ? 'Attachment' : a.filename;

/// Hand a document or video to the phone, as the chat bubble does.
Future<void> _open(
  BuildContext context,
  pb.Attachment a,
  AssetCache? cache,
) async {
  final c = cache ?? AssetCache.instance;
  if (c == null) return;
  final messenger = ScaffoldMessenger.of(context);
  final name = _nameOf(a);
  final ok = await openAttachment(c, uri: a.url, name: name, mime: a.mimeType);
  if (!ok) {
    messenger.showSnackBar(SnackBar(content: Text("Couldn't open $name")));
  }
}

class MediaScreen extends StatefulWidget {
  final String channelId;
  final ChatService chatService;

  /// Injected by tests; screens in the app leave it null and the
  /// widgets fall through to [AssetCache.instance].
  final AssetCache? cache;

  const MediaScreen({
    super.key,
    required this.channelId,
    required this.chatService,
    this.cache,
  });

  @override
  State<MediaScreen> createState() => _MediaScreenState();
}

class _MediaScreenState extends State<MediaScreen> {
  late final _media = widget.chatService.fetchMedia(widget.channelId);
  late final _docs = widget.chatService.fetchFiles(widget.channelId);
  late final _links = widget.chatService.fetchLinks(widget.channelId);

  @override
  Widget build(BuildContext context) {
    final cache = widget.cache;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Media, links and docs'),
          bottom: const TabBar(
            tabs: [Tab(text: 'Media'), Tab(text: 'Docs'), Tab(text: 'Links')],
          ),
        ),
        body: TabBarView(
          children: [
            _MonthlyTab(
              rows: _media,
              empty: const _Empty(
                icon: Icons.perm_media_outlined,
                title: 'No media',
                line: 'Photos and videos shared in this chat show up here.',
              ),
              section: (rows) => SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 2,
                  crossAxisSpacing: 2,
                ),
                itemCount: rows.length,
                itemBuilder: (_, i) =>
                    _MediaTile(message: rows[i], cache: cache),
              ),
            ),
            _MonthlyTab(
              rows: _docs,
              empty: const _Empty(
                icon: Icons.description_outlined,
                title: 'No docs',
                line: 'Documents shared in this chat show up here.',
              ),
              section: (rows) => SliverList.builder(
                itemCount: rows.length,
                itemBuilder: (_, i) => _DocRow(message: rows[i], cache: cache),
              ),
            ),
            _MonthlyTab(
              rows: _links,
              empty: const _Empty(
                icon: Icons.link,
                title: 'No links',
                line: 'Links shared in this chat show up here.',
              ),
              section: (rows) => SliverList.builder(
                itemCount: rows.length,
                itemBuilder: (_, i) => _LinkRow(message: rows[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One tab: [rows] (newest first) under month headers, or [empty]. The
/// list ends clear of the system nav bar.
class _MonthlyTab extends StatelessWidget {
  final Future<List<MessageRow>> rows;
  final Widget empty;

  /// The sliver for one month's rows.
  final Widget Function(List<MessageRow> rows) section;

  const _MonthlyTab({
    required this.rows,
    required this.empty,
    required this.section,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MessageRow>>(
      future: rows,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
        final list = snap.data;
        if (list == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (list.isEmpty) return empty;
        final now = DateTime.now();
        final months = <String, List<MessageRow>>{};
        for (final m in list) {
          months.putIfAbsent(monthLabel(_sentAt(m), now), () => []).add(m);
        }
        return CustomScrollView(
          slivers: [
            for (final month in months.entries) ...[
              SliverToBoxAdapter(child: _MonthHeader(month.key)),
              section(month.value),
            ],
            SliverToBoxAdapter(
              child: SizedBox(
                height: kSpaceSm + MediaQuery.paddingOf(context).bottom,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MonthHeader extends StatelessWidget {
  final String label;
  const _MonthHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: kSpaceMd,
        vertical: kSpaceSm,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

/// A square grid tile. Photos show their thumbnail and open the
/// viewer; videos have no thumbnail yet, so they are a dark tile with
/// a camera glyph and their length, and open in the phone's player.
class _MediaTile extends StatelessWidget {
  final MessageRow message;
  final AssetCache? cache;
  const _MediaTile({required this.message, this.cache});

  @override
  Widget build(BuildContext context) {
    final a = firstAttachment(message);
    if (message.contentType?.startsWith('video/') ?? false) {
      final length = a?.durationMs ?? 0;
      return GestureDetector(
        onTap: a == null ? null : () => _open(context, a, cache),
        child: ColoredBox(
          color: Colors.black87,
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.all(kSpaceXs),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.videocam,
                    size: 16,
                    color: Colors.white,
                    semanticLabel: 'Video',
                  ),
                  if (length > 0) ...[
                    const SizedBox(width: kSpaceXs),
                    Text(
                      mmss(Duration(milliseconds: length)),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }
    const placeholder = AssetImagePlaceholder();
    return GestureDetector(
      onTap: a == null
          ? null
          : () => showAssetViewer(context, uri: a.url, cache: cache),
      child: a == null
          ? placeholder
          : AssetImageView(
              uri: a.url,
              cache: cache,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              placeholder: placeholder,
              fallback: const AssetImagePlaceholder(
                icon: Icons.broken_image_outlined,
              ),
            ),
    );
  }
}

/// Square glyph box leading a docs or links row.
class _Badge extends StatelessWidget {
  final Widget child;
  const _Badge({required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(kRadiusSm),
      ),
      child: IconTheme.merge(
        data: IconThemeData(color: scheme.primary),
        child: DefaultTextStyle.merge(
          style: TextStyle(
            color: scheme.primary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// WhatsApp's document row: extension badge, name, then
/// "size · TYPE · date".
class _DocRow extends StatelessWidget {
  final MessageRow message;
  final AssetCache? cache;
  const _DocRow({required this.message, this.cache});

  @override
  Widget build(BuildContext context) {
    final a = firstAttachment(message);
    final name = _nameOf(a);
    final ext = name.contains('.') ? extForPath(name).toUpperCase() : '';
    final details = [
      humanFileSize(a?.sizeBytes.toInt() ?? 0),
      ext,
      DateFormat.yMMMd().format(_sentAt(message)),
    ].where((s) => s.isNotEmpty).join(' · ');
    return ListTile(
      leading: _Badge(
        child: ext.isEmpty || ext.length > 4
            ? const Icon(Icons.description_outlined)
            : Text(ext),
      ),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(details),
      onTap: a == null ? null : () => _open(context, a, cache),
    );
  }
}

/// A message's first link: its host, the URL, and the message text when
/// there is more to it than the URL. Opens in the browser.
class _LinkRow extends StatelessWidget {
  final MessageRow message;
  const _LinkRow({required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = (message.body ?? '').trim();
    final url = ChatStore.linkPattern.firstMatch(text)?.group(0) ?? text;
    final uri = Uri.tryParse(url);
    final host = uri?.host ?? '';
    final more = text != url;
    return ListTile(
      leading: const _Badge(child: Icon(Icons.link)),
      title: Text(
        host.isEmpty ? url : host,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: more,
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            url,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: scheme.primary),
          ),
          if (more) Text(text, maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ),
      onTap: uri == null
          ? null
          : () async {
              final messenger = ScaffoldMessenger.of(context);
              final ok = await launchUrl(
                uri,
                mode: LaunchMode.externalApplication,
              ).catchError((_) => false);
              if (!ok) {
                messenger.showSnackBar(
                  const SnackBar(content: Text("Couldn't open this link")),
                );
              }
            },
    );
  }
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String line;

  const _Empty({required this.icon, required this.title, required this.line});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(kSpaceXl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: scheme.onSurfaceVariant),
            const SizedBox(height: kSpaceMd),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: kSpaceSm),
            Text(
              line,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
