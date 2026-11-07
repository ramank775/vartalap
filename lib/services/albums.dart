part of 'chat_service.dart';

/// Occasion albums in a chat (decision 233), over the server's album REST
/// API ([AlbumClient]): online only, nothing kept on the phone, photos
/// uploaded through media-ms unencrypted. A mixin of [ChatService] so the
/// screens' fakes can stand in for it.
mixin AlbumService on TimelineService {
  /// Replaced by tests.
  late AlbumClient albumClient = AlbumClient(
    baseUrl: _authClient.baseUrl,
    auth: _authClient,
    client: _authClient.httpClient,
  );

  /// Who is signed in, for the screens' own-photo checks.
  String? get selfUserId => _authClient.currentUserId;

  /// [ChatService.sendMessage].
  Future<void> sendMessage({
    required String channelId,
    required String body,
    required String authorUserId,
    String contentType,
  });

  /// A chat's albums, newest first. A 1:1 names its other person as [peer].
  Future<List<Album>> albumsOf(String channelId, {String? peer}) =>
      albumClient.list(channelId, peer: peer);

  /// Make an album, then say so in the chat with a message that opens it
  /// ("Asha created the album Diwali 2026"). [date] is `YYYY-MM-DD`.
  Future<Album> createAlbum({
    required String channelId,
    String? peer,
    required String title,
    String? date,
  }) async {
    final album = await albumClient.create(
      channelId,
      albumId: _uuidGen.next(nowMs: _clock.nowMs()),
      title: title,
      date: date,
      peer: peer,
    );
    final me = _authClient.currentUserId;
    if (me != null) {
      await sendMessage(
        channelId: channelId,
        body: AlbumNote(album.albumId, channelId, album.title).encode(),
        authorUserId: me,
        contentType: kAlbumType,
      );
    }
    return album;
  }

  /// The album and a page of its photos ([cursor]: the page before's `next`).
  Future<AlbumPage> albumPage(String channelId, String albumId,
          {bool newestFirst = true, String? cursor}) =>
      albumClient.open(channelId, albumId,
          newestFirst: newestFirst, cursor: cursor);

  /// Upload and add [paths] one by one, so what went in stays in if the
  /// connection drops halfway. [onAdded] counts them. The album after.
  Future<Album> addAlbumPhotos(Album album, List<String> paths,
      {void Function(int added)? onAdded}) async {
    var latest = album;
    for (final (i, path) in paths.indexed) {
      final fileId = await _uploadPhoto(path, 'album');
      latest =
          await albumClient.addPhotos(album.channelId, album.albumId, [fileId]);
      onAdded?.call(i + 1);
    }
    return latest;
  }

  Future<void> removeAlbumPhoto(Album album, AlbumPhoto photo) =>
      albumClient.removePhoto(album.channelId, album.albumId, photo.fileId);

  /// [date] '' clears it.
  Future<Album> editAlbum(Album album, {String? title, String? date}) =>
      albumClient.edit(album.channelId, album.albumId,
          title: title, date: date);

  Future<void> deleteAlbum(Album album) =>
      albumClient.delete(album.channelId, album.albumId);
}
