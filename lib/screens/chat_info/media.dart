/// "Media, links and docs" — every attachment in one channel: images
/// in a grid, everything else as a file list below it.
///
/// Thumbnails come off the same [AssetCache] the chat bubbles use, so
/// opening this screen after scrolling the thread costs no network.
library vartalap.screens.chat_info.media;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vartalap/services/asset_cache.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/theme/theme.dart';
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
  late final Future<List<List<MessageRow>>> _contents = Future.wait([
    widget.chatService.fetchMedia(widget.channelId),
    widget.chatService.fetchFiles(widget.channelId),
  ]);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Media, links and docs')),
      body: FutureBuilder<List<List<MessageRow>>>(
        future: _contents,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final media = snap.data?[0] ?? const <MessageRow>[];
          final files = snap.data?[1] ?? const <MessageRow>[];
          if (media.isEmpty && files.isEmpty) return const _NothingShared();
          return ListView(
            padding: const EdgeInsets.all(kSpaceSm),
            children: [
              if (media.isNotEmpty)
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: kSpaceSm,
                    crossAxisSpacing: kSpaceSm,
                  ),
                  itemCount: media.length,
                  itemBuilder: (ctx, i) =>
                      _MediaTile(message: media[i], cache: widget.cache),
                ),
              if (files.isNotEmpty) ...[
                const SizedBox(height: kSpaceMd),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: kSpaceSm),
                  child: Text(
                    'Documents',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                for (final m in files) _FileRow(message: m),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  final MessageRow message;
  const _FileRow({required this.message});

  @override
  Widget build(BuildContext context) {
    final a = firstAttachment(message);
    final name = (a == null || a.filename.isEmpty) ? 'Attachment' : a.filename;
    return ListTile(
      leading: const Icon(Icons.insert_drive_file_outlined),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(DateFormat.yMMMd().format(
        DateTime.fromMillisecondsSinceEpoch(
          message.serverTimestampMs ?? message.clientTimestampMs,
        ),
      )),
    );
  }
}

class _MediaTile extends StatelessWidget {
  final MessageRow message;
  final AssetCache? cache;
  const _MediaTile({required this.message, this.cache});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final when = DateTime.fromMillisecondsSinceEpoch(
      message.serverTimestampMs ?? message.clientTimestampMs,
    );
    final a = firstAttachment(message);
    final dateGlyph = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.image_outlined, color: scheme.onSurfaceVariant),
        const SizedBox(height: kSpaceXs),
        Text(
          DateFormat.MMMd().format(when),
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
      ],
    );
    return GestureDetector(
      onTap: a == null
          ? null
          : () => showAssetViewer(context, uri: a.url, cache: cache),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(kRadiusSm),
        ),
        clipBehavior: Clip.antiAlias,
        alignment: Alignment.center,
        child: a == null
            ? dateGlyph
            : AssetImageView(
                uri: a.url,
                cache: cache,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                placeholder: dateGlyph,
              ),
      ),
    );
  }
}

class _NothingShared extends StatelessWidget {
  const _NothingShared();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(kSpaceXl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.perm_media_outlined,
              size: 48,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: kSpaceMd),
            Text(
              'Nothing shared yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: kSpaceSm),
            Text(
              'Photos and files shared in this chat show up here.',
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
