/// Share-to (WhatsApp's): photos, videos, documents and text another app
/// shares through Android's share sheet, sent to chats the user picks.
/// The files arrive already copied into our cache (SharedFiles.kt).
library vartalap.screens.chat.share_to;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vartalap/screens/chat/attachment_preview.dart';
import 'package:vartalap/screens/chat/chat.dart';
import 'package:vartalap/screens/chat/forward.dart';
import 'package:vartalap/services/asset_cache.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap_crypto/vartalap_crypto.dart'
    show sealedAttachmentOverhead;
import 'package:vartalap_transport/vartalap_transport.dart' show AssetClient;

/// At most this many files from one share (WhatsApp's 30).
const int kMaxShareFiles = 30;

const _channel = MethodChannel('vartalap/share');

/// What another app shared.
class SharedItems {
  /// Our copies, in the order shared, each named as the sender named it.
  final List<String> paths;

  /// A shared link or text; '' for none.
  final String text;

  /// Left out: names over the upload limit, how many past
  /// [kMaxShareFiles], how many could not be read.
  final List<String> tooBig;
  final int tooMany;
  final int unreadable;

  /// The folder holding [paths], deleted once sent or given up.
  final String? dir;

  const SharedItems({
    this.paths = const [],
    this.text = '',
    this.tooBig = const [],
    this.tooMany = 0,
    this.unreadable = 0,
    this.dir,
  });

  /// From the `vartalap/share` channel's `take`.
  factory SharedItems.fromMap(Map<Object?, Object?> map) => SharedItems(
        paths: [for (final p in map['files'] as List? ?? const []) '$p'],
        text: (map['text'] as String? ?? '').trim(),
        tooBig: [for (final n in map['tooBig'] as List? ?? const []) '$n'],
        tooMany: map['tooMany'] as int? ?? 0,
        unreadable: map['unreadable'] as int? ?? 0,
        dir: map['dir'] as String?,
      );

  bool get isEmpty => paths.isEmpty && text.isEmpty;

  /// What was left out and why, for the user; null when nothing was.
  String? get leftOut {
    final lines = [
      if (tooBig.isNotEmpty)
        'Too big to send (over '
            '${AssetClient.maxUploadBytes ~/ (1024 * 1024)} MB): '
            '${tooBig.join(', ')}',
      if (tooMany > 0)
        'You can send up to $kMaxShareFiles files at a time. '
            '$tooMany ${tooMany == 1 ? 'was' : 'were'} left out.',
      if (unreadable > 0)
        unreadable == 1
            ? "1 file couldn't be read."
            : "$unreadable files couldn't be read.",
    ];
    return lines.isEmpty ? null : lines.join('\n');
  }

  /// Our copies go, sent or not.
  Future<void> discard() async {
    final folder = dir;
    if (folder == null) return;
    try {
      await Directory(folder).delete(recursive: true);
    } on FileSystemException {
      // already gone
    }
  }
}

/// Calls [onShare] for each share: the one that started the app, and
/// each one made while it runs.
void listenForShares(void Function(SharedItems share) onShare) {
  Future<void> take() async {
    try {
      final map = await _channel.invokeMapMethod<Object?, Object?>('take', {
        'maxBytes': AssetClient.maxUploadBytes - sealedAttachmentOverhead,
        'maxFiles': kMaxShareFiles,
      });
      if (map != null) onShare(SharedItems.fromMap(map));
    } on MissingPluginException {
      // no Android side: a test
    } on PlatformException {
      // nothing to take
    }
  }

  _channel.setMethodCallHandler((call) async {
    if (call.method == 'ready') await take();
  });
  unawaited(take());
}

/// A shared photo or video goes as media, like one from the gallery (a
/// photo sized for sending, a video with its first frame); anything else
/// as a document, byte for byte.
bool isSharedMedia(String path) {
  final mime = mimeForPath(path);
  return mime.startsWith('image/') || mime.startsWith('video/');
}

/// WhatsApp's share-to: says what was left out, then "Send to…" (up to
/// [ChatService.maxForwardChats] chats), then the send preview for files
/// (back there returns to the picker). One chat opens with any shared text
/// in its composer; several get it as a message and the chat list shows.
/// The files are sent after the screen moves on, through the attach
/// path's [prepareAttachment] and [ChatService.sendAttachment]. [share]'s
/// copies are deleted at the end, whatever happens.
Future<void> sendShared(
  NavigatorState navigator,
  SharedItems share, {
  required ChatService chatService,
  required AuthService authService,
}) async {
  var handedOff = false;
  try {
    final messenger = ScaffoldMessenger.maybeOf(navigator.context);
    void say(String text) => messenger
      ?..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(text)));
    final note = share.leftOut;
    if (note != null) say(note);
    final self = authService.currentUserId;
    if (self == null || share.isEmpty) return;

    List<ForwardTarget>? targets;
    AttachmentChoice? choice;
    while (true) {
      targets = await navigator.push<List<ForwardTarget>>(MaterialPageRoute(
        builder: (_) => ForwardScreen(
          chatService: chatService,
          selfUserId: self,
          title: 'Send to…',
        ),
      ));
      if (targets == null || targets.isEmpty) return;
      if (share.paths.isEmpty) break;
      choice = await navigator.push<AttachmentChoice>(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AttachmentPreviewScreen(
          path: share.paths.first,
          more: share.paths.sublist(1),
          offerHd: share.paths
              .map(mimeForPath)
              .any((m) => m.startsWith('image/') && m != 'image/gif'),
        ),
      ));
      if (choice != null) break;
    }

    final one = targets.length == 1 ? targets.single : null;
    navigator.popUntil((route) => route.isFirst);
    if (one != null) {
      unawaited(navigator.push(MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          channelId: one.channelId,
          channelName: one.title,
          channelKind: one.group ? 'group' : 'dm',
          chatService: chatService,
          authService: authService,
          initialText: share.text.isEmpty ? null : share.text,
        ),
      )));
    }
    handedOff = true;
    unawaited(_send(chatService, self, share, targets, choice, say)
        .whenComplete(share.discard));
  } finally {
    if (!handedOff) await share.discard();
  }
}

/// Each file prepared once, then sent to every target in turn; the
/// caption with the first. Text goes as a message only to several chats
/// (one chat has it in its composer).
Future<void> _send(
  ChatService chat,
  String self,
  SharedItems share,
  List<ForwardTarget> targets,
  AttachmentChoice? choice,
  void Function(String) say,
) async {
  for (final (i, source) in share.paths.indexed) {
    try {
      final file = await prepareAttachment(chat.assets, source,
          media: isSharedMedia(source), hd: choice?.hd ?? false);
      final caption = i == 0 ? choice?.caption ?? '' : '';
      for (final t in targets) {
        await chat.sendAttachment(
          channelId: t.channelId,
          authorUserId: self,
          path: file.path,
          caption: caption.isEmpty ? null : caption,
          width: file.width,
          height: file.height,
          durationMs: file.durationMs,
          thumbnail: file.thumbnail,
        );
      }
    } on ArgumentError catch (e) {
      say('${source.split('/').last}: ${e.message}');
    } catch (_) {
      say("Couldn't send ${source.split('/').last}");
    }
  }
  if (targets.length > 1 && share.text.isNotEmpty) {
    for (final t in targets) {
      await chat.sendMessage(
          channelId: t.channelId, body: share.text, authorUserId: self);
    }
  }
}
