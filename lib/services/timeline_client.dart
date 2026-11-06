/// The private timeline's REST API (decision 223, chat-server
/// docs/openapi.yaml "v3.0 > Timeline"): plain REST, not the sync wire,
/// not end-to-end encrypted. The phone names the audience as user ids it
/// resolved from its own labels; the server never sees a label.
library vartalap.services.timeline_client;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:vartalap_transport/vartalap_transport.dart';

class TimelinePhoto {
  /// A media-ms upload, category `timeline`; [AssetCache] resolves it.
  final String fileId;
  final int width;
  final int height;

  const TimelinePhoto(this.fileId, {this.width = 0, this.height = 0});

  factory TimelinePhoto.fromJson(Map<String, dynamic> j) => TimelinePhoto(
        j['fileId'] as String,
        width: j['width'] as int? ?? 0,
        height: j['height'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() =>
      {'fileId': fileId, 'width': width, 'height': height};
}

class TimelinePost {
  final String postId;
  final String author;
  final String? text;
  final List<TimelinePhoto> photos;

  /// Server time, ms since epoch.
  final int createdAt;

  /// Someone else's post: our own reaction, if any.
  final String? myReaction;

  /// Our own post: who it went to. Null on someone else's.
  final List<String>? audience;

  /// Our own post: who reacted, oldest first. Nobody else gets these.
  final List<({String userId, String emoji})> reactions;

  const TimelinePost({
    required this.postId,
    required this.author,
    this.text,
    this.photos = const [],
    required this.createdAt,
    this.myReaction,
    this.audience,
    this.reactions = const [],
  });

  bool get mine => audience != null;

  factory TimelinePost.fromJson(Map<String, dynamic> j) => TimelinePost(
        postId: j['postId'] as String,
        author: j['author'] as String,
        text: j['text'] as String?,
        photos: [
          for (final p in (j['photos'] as List? ?? const []))
            TimelinePhoto.fromJson(p as Map<String, dynamic>),
        ],
        createdAt: j['createdAt'] as int,
        myReaction: j['myReaction'] as String?,
        audience: (j['audience'] as List?)?.cast<String>(),
        reactions: [
          for (final r in (j['reactions'] as List? ?? const []))
            (
              userId: (r as Map<String, dynamic>)['userId'] as String,
              emoji: r['emoji'] as String,
            ),
        ],
      );

  TimelinePost withMyReaction(String? emoji) => TimelinePost(
        postId: postId,
        author: author,
        text: text,
        photos: photos,
        createdAt: createdAt,
        myReaction: emoji,
        audience: audience,
        reactions: reactions,
      );
}

typedef TimelinePage = ({List<TimelinePost> posts, String? next});

/// Bearer-authenticated like [AssetClient], on the same http client (so
/// the app build header rides along). Errors are [AuthClientException].
class TimelineClient {
  final Uri baseUrl;
  final AuthTokenProvider auth;
  final http.Client client;

  TimelineClient({
    required this.baseUrl,
    required this.auth,
    required this.client,
  });

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${auth.currentAccesskey}',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };

  Uri _uri(String path, [Map<String, String>? query]) =>
      baseUrl.resolve('/v3.0/timeline$path').replace(queryParameters: query);

  Future<TimelinePost> createPost({
    required String postId,
    String? text,
    List<TimelinePhoto> photos = const [],
    required List<String> audience,
  }) async {
    final resp = await client.post(_uri('/posts'),
        headers: _headers,
        body: jsonEncode({
          'postId': postId,
          'text': text,
          'photos': [for (final p in photos) p.toJson()],
          'audience': audience,
        }));
    return TimelinePost.fromJson(_json(resp, 'createPost'));
  }

  /// Posts shared with us, newest first.
  Future<TimelinePage> feed({String? before, int limit = 50}) =>
      _page('/feed', before, limit);

  /// Our own posts, newest first, with who reacted.
  Future<TimelinePage> mine({String? before, int limit = 50}) =>
      _page('/posts/mine', before, limit);

  Future<TimelinePage> _page(String path, String? before, int limit) async {
    final resp = await client.get(
        _uri(path, {'limit': '$limit', if (before != null) 'before': before}),
        headers: _headers);
    final json = _json(resp, path);
    return (
      posts: [
        for (final p in json['posts'] as List)
          TimelinePost.fromJson(p as Map<String, dynamic>),
      ],
      next: json['next'] as String?,
    );
  }

  Future<void> deletePost(String postId) async {
    final resp = await client.delete(_uri('/posts/$postId'), headers: _headers);
    _check(resp, 'deletePost');
  }

  /// [emoji] null takes ours back.
  Future<void> react(String postId, String? emoji) async {
    final uri = _uri('/posts/$postId/reaction');
    final resp = emoji == null
        ? await client.delete(uri, headers: _headers)
        : await client.put(uri,
            headers: _headers, body: jsonEncode({'emoji': emoji}));
    _check(resp, 'react');
  }

  Map<String, dynamic> _json(http.Response resp, String method) {
    _check(resp, method);
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  void _check(http.Response resp, String method) {
    if (resp.statusCode >= 200 && resp.statusCode < 300) return;
    String? code;
    try {
      code = ((jsonDecode(resp.body) as Map<String, dynamic>)['error']
          as Map<String, dynamic>)['code'] as String?;
    } catch (_) {
      // not our JSON envelope (a proxy page): the status stands
    }
    throw AuthClientException(method, resp.statusCode, code, null);
  }
}
