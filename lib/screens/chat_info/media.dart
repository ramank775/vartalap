/// "Media, links and docs" — every image message in one channel.
///
/// The query is real (`ChatStore.fetchChannelMedia`); what is not here
/// yet is the pixels. Attachment blobs and their thumbnails arrive with
/// the attachment work, so a tile renders its glyph and date today and
/// gains a thumbnail then, with no change to this screen's shape.
library vartalap.screens.chat_info.media;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap_store/vartalap_store.dart';

class MediaScreen extends StatefulWidget {
  final String channelId;
  final ChatService chatService;

  const MediaScreen({
    super.key,
    required this.channelId,
    required this.chatService,
  });

  @override
  State<MediaScreen> createState() => _MediaScreenState();
}

class _MediaScreenState extends State<MediaScreen> {
  late final Future<List<MessageRow>> _media =
      widget.chatService.fetchMedia(widget.channelId);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Media, links and docs')),
      body: FutureBuilder<List<MessageRow>>(
        future: _media,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final media = snap.data ?? const <MessageRow>[];
          if (media.isEmpty) return const _NothingShared();
          return GridView.builder(
            padding: const EdgeInsets.all(kSpaceSm),
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: kSpaceSm,
              crossAxisSpacing: kSpaceSm,
            ),
            itemCount: media.length,
            itemBuilder: (ctx, i) => _MediaTile(message: media[i]),
          );
        },
      ),
    );
  }
}

class _MediaTile extends StatelessWidget {
  final MessageRow message;
  const _MediaTile({required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final when = DateTime.fromMillisecondsSinceEpoch(
      message.serverTimestampMs ?? message.clientTimestampMs,
    );
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(kRadiusSm),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // ponytail: glyph placeholder until attachment blobs land;
          // swap for the thumbnail then, same tile.
          Icon(Icons.image_outlined, color: scheme.onSurfaceVariant),
          const SizedBox(height: kSpaceXs),
          Text(
            DateFormat.MMMd().format(when),
            style: TextStyle(
              fontSize: 11,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
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
