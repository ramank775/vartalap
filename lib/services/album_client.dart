/// Occasion albums' REST API (decision 233, chat-server docs/openapi.yaml
/// "v3.0 > Albums"): plain REST under `/v3.0/channels/{channelId}/albums`,
/// not the sync wire and not end-to-end encrypted, like the timeline. The
/// server decides who may see and change what; the phone keeps nothing.
library vartalap.services.album_client;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:vartalap_transport/vartalap_transport.dart';

class AlbumPhoto {
  /// A media-ms upload, category `album`; [AssetCache] resolves it.
  final String fileId;
  final String uploader;

  /// Server time, ms since epoch.
  final int addedAt;

  const AlbumPhoto(this.fileId, {required this.uploader, this.addedAt = 0});

  factory AlbumPhoto.fromJson(Map<String, dynamic> j) => AlbumPhoto(
        j['fileId'] as String,
        uploader: j['uploader'] as String? ?? '',
        addedAt: j['addedAt'] as int? ?? 0,
      );
}

class Album {
  final String albumId;
  final String channelId;
  final String title;

  /// The occasion's day, `YYYY-MM-DD`.
  final String? date;
  final String creator;
  final int createdAt;

  /// When the server deletes it, photos and all; null: kept for good.
  final int? keptUntil;
  final int photoCount;

  /// The newest photo.
  final AlbumPhoto? cover;

  const Album({
    required this.albumId,
    required this.channelId,
    required this.title,
    this.date,
    required this.creator,
    required this.createdAt,
    this.keptUntil,
    this.photoCount = 0,
    this.cover,
  });

  factory Album.fromJson(Map<String, dynamic> j) => Album(
        albumId: j['albumId'] as String,
        channelId: j['channelId'] as String,
        title: j['title'] as String,
        date: j['date'] as String?,
        creator: j['creator'] as String,
        createdAt: j['createdAt'] as int,
        keptUntil: j['keptUntil'] as int?,
        photoCount: j['photoCount'] as int? ?? 0,
        cover: j['cover'] == null
            ? null
            : AlbumPhoto.fromJson(j['cover'] as Map<String, dynamic>),
      );
}

typedef AlbumPage = ({Album album, List<AlbumPhoto> photos, String? next});

/// Bearer-authenticated like [TimelineClient], on the same http client.
/// Errors are [AuthClientException] (403 `forbidden`: not this chat's,
/// or not yours to change; 404: no such album).
class AlbumClient {
  final Uri baseUrl;
  final AuthTokenProvider auth;
  final http.Client client;

  AlbumClient(
      {required this.baseUrl, required this.auth, required this.client});

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${auth.currentAccesskey}',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };

  Uri _uri(String channelId, String path, [Map<String, String>? query]) =>
      baseUrl
          .resolve('/v3.0/channels/$channelId/albums$path')
          .replace(queryParameters: query);

  /// A 1:1 names its other person as [peer].
  Future<List<Album>> list(String channelId, {String? peer}) async {
    final resp = await client.get(
        _uri(channelId, '', {if (peer != null) 'peer': peer}),
        headers: _headers);
    return [
      for (final a in _json(resp, 'listAlbums')['albums'] as List)
        Album.fromJson(a as Map<String, dynamic>),
    ];
  }

  Future<Album> create(
    String channelId, {
    required String albumId,
    required String title,
    String? date,
    String? peer,
  }) async {
    final resp = await client.post(_uri(channelId, ''),
        headers: _headers,
        body: jsonEncode({
          'albumId': albumId,
          'title': title,
          if (date != null) 'date': date,
          if (peer != null) 'peer': peer,
        }));
    return Album.fromJson(_json(resp, 'createAlbum'));
  }

  Future<AlbumPage> open(
    String channelId,
    String albumId, {
    bool newestFirst = true,
    String? cursor,
    int limit = 60,
  }) async {
    final resp = await client.get(
        _uri(channelId, '/$albumId', {
          'order': newestFirst ? 'newest' : 'oldest',
          'limit': '$limit',
          if (cursor != null) 'cursor': cursor,
        }),
        headers: _headers);
    final json = _json(resp, 'openAlbum');
    return (
      album: Album.fromJson(json['album'] as Map<String, dynamic>),
      photos: [
        for (final p in json['photos'] as List)
          AlbumPhoto.fromJson(p as Map<String, dynamic>),
      ],
      next: json['next'] as String?,
    );
  }

  /// [date] '' clears it; null leaves it.
  Future<Album> edit(String channelId, String albumId,
      {String? title, String? date}) async {
    final resp = await client.patch(_uri(channelId, '/$albumId'),
        headers: _headers,
        body: jsonEncode({
          if (title != null) 'title': title,
          if (date != null) 'date': date.isEmpty ? null : date,
        }));
    return Album.fromJson(_json(resp, 'editAlbum'));
  }

  Future<void> delete(String channelId, String albumId) async {
    _check(await client.delete(_uri(channelId, '/$albumId'), headers: _headers),
        'deleteAlbum');
  }

  /// Uploaded [fileIds] (at most 50); the album after.
  Future<Album> addPhotos(
      String channelId, String albumId, List<String> fileIds) async {
    final resp = await client.post(_uri(channelId, '/$albumId/photos'),
        headers: _headers,
        body: jsonEncode({
          'photos': [
            for (final f in fileIds) {'fileId': f},
          ],
        }));
    return Album.fromJson(
        _json(resp, 'addPhotos')['album'] as Map<String, dynamic>);
  }

  Future<void> removePhoto(
      String channelId, String albumId, String fileId) async {
    _check(
        await client.delete(_uri(channelId, '/$albumId/photos/$fileId'),
            headers: _headers),
        'removePhoto');
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

/// The chat message that says an album was made (decision 233): its
/// body is [AlbumNote] as JSON, and a tap opens the album.
const kAlbumType = 'application/x-vartalap-album';

class AlbumNote {
  final String albumId;
  final String channelId;
  final String title;

  const AlbumNote(this.albumId, this.channelId, this.title);

  String encode() =>
      jsonEncode({'albumId': albumId, 'channelId': channelId, 'title': title});

  /// Null for a body that is not one.
  static AlbumNote? parse(String body) {
    try {
      final j = jsonDecode(body) as Map<String, dynamic>;
      return AlbumNote(j['albumId'] as String, j['channelId'] as String,
          j['title'] as String);
    } catch (_) {
      return null;
    }
  }
}
