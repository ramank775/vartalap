part of 'chat_service.dart';

/// Labels (on this phone only) and the private timeline (decision 223,
/// over the server's timeline REST API, [TimelineClient]). A post names
/// its audience as the user ids the chosen labels resolve to here; the
/// server never sees a label. A mixin of [ChatService] so the screens'
/// fakes can stand in for it.
mixin TimelineService {
  ChatStore get _store;
  AuthClient get _authClient;
  Clock get _clock;
  Uuid7Gen get _uuidGen;
  AssetCache get assets;

  /// Replaced by tests.
  late TimelineClient timelineClient = TimelineClient(
    baseUrl: _authClient.baseUrl,
    auth: _authClient,
    client: _authClient.httpClient,
  );

  // --- labels ---------------------------------------------------------------

  Stream<List<Label>> watchLabels() => _store.watchLabels();
  Future<List<Label>> fetchLabels() => _store.fetchLabels();
  Future<int> createLabel(String name) => _store.createLabel(name);
  Future<void> renameLabel(int labelId, String name) =>
      _store.renameLabel(labelId, name);
  Future<void> deleteLabel(int labelId) => _store.deleteLabel(labelId);
  Future<void> setLabelMembers(int labelId, Set<String> userIds) =>
      _store.setLabelMembers(labelId, userIds);
  Future<void> setContactLabels(String userId, Set<int> labelIds) =>
      _store.setContactLabels(userId, labelIds);

  // --- the timeline ---------------------------------------------------------

  /// Who a post to [labelIds] (null: all contacts) would reach.
  Future<List<String>> timelineAudience(Set<int>? labelIds) async {
    final self = _authClient.currentUserId;
    if (self == null) return const [];
    return _store.timelineAudience(selfUserId: self, labelIds: labelIds);
  }

  String get _audienceKey => 'v3.timelineAudience.${_authClient.currentUserId}';
  String get _seenKey => 'v3.timelineSeen.${_authClient.currentUserId}';

  /// The audience last posted to, so the next post starts there (null:
  /// all contacts, also before the first post).
  Future<Set<int>?> lastTimelineAudience() async {
    try {
      final saved =
          (await SharedPreferences.getInstance()).getString(_audienceKey);
      if (saved == null || saved == 'all') return null;
      return {for (final id in saved.split(',')) int.parse(id)};
    } catch (_) {
      return null;
    }
  }

  /// Ours and what was shared with us, newest first: the first page of
  /// each. What it shows counts as seen ([timelineHasNew]).
  /// ponytail: one page of 100 each, no "load older"; a month's
  /// retention keeps a family's timeline under that. Page with `next`
  /// if one ever is not.
  Future<List<TimelinePost>> loadTimeline() async {
    final (shared, mine) = await (
      timelineClient.feed(limit: 100),
      timelineClient.mine(limit: 100),
    ).wait;
    final newest = shared.posts.firstOrNull?.createdAt;
    if (newest != null) await _setSeen(newest);
    return [...shared.posts, ...mine.posts]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// A post shared with us since the timeline was last looked at: the
  /// tab's dot. False when the server cannot be reached.
  Future<bool> timelineHasNew() async {
    try {
      final newest =
          (await timelineClient.feed(limit: 1)).posts.firstOrNull?.createdAt;
      if (newest == null) return false;
      final prefs = await SharedPreferences.getInstance();
      return newest > (prefs.getInt(_seenKey) ?? 0);
    } catch (_) {
      return false;
    }
  }

  Future<void> _setSeen(int createdAt) async {
    try {
      await (await SharedPreferences.getInstance()).setInt(_seenKey, createdAt);
    } catch (_) {
      // No platform channel (widget tests): the dot just comes back.
    }
  }

  /// Post [body] and [photoPaths] to the people [labelIds] name (null:
  /// all contacts). Photos go up first, through the media upload path but
  /// not encrypted (the timeline is not end-to-end encrypted). Throws
  /// [StateError] when nobody would see it, and the upload's or the
  /// server's error otherwise (offline included): nothing is queued, the
  /// composer stays open to try again.
  Future<TimelinePost> postToTimeline({
    String? body,
    List<String> photoPaths = const [],
    Set<int>? labelIds,
  }) async {
    final audience = await timelineAudience(labelIds);
    if (audience.isEmpty) throw StateError('Nobody to share this with');
    final photos = [
      for (final path in photoPaths) TimelinePhoto(await _uploadPhoto(path)),
    ];
    final text = body?.trim();
    final post = await timelineClient.createPost(
      postId: _uuidGen.next(nowMs: _clock.nowMs()),
      text: text == null || text.isEmpty ? null : text,
      photos: photos,
      audience: audience,
    );
    try {
      await (await SharedPreferences.getInstance()).setString(_audienceKey,
          labelIds == null ? 'all' : (labelIds.toList()..sort()).join(','));
    } catch (_) {
      // No platform channel (widget tests): not remembered.
    }
    return post;
  }

  /// media-ms, category `timeline`: the server deletes it with the post.
  Future<String> _uploadPhoto(String path) async {
    final bytes = await File(path).readAsBytes();
    final client = assets.client;
    final upload = await client.presignUpload(
        ext: extForPath(path), category: 'timeline', size: bytes.length);
    if (!upload.existing) {
      await client.putBytes(
        url: upload.url,
        bytes: bytes,
        contentType: upload.contentType ?? mimeForPath(path),
      );
      await client.markUploaded(upload.fileId);
    }
    // if the picked file is in memory, the photo is: no download back
    assets.rekey(path, upload.fileId);
    return upload.fileId;
  }

  /// Our reaction to someone else's post ([emoji] null: take it back).
  /// Only its poster sees it.
  Future<void> reactToPost(TimelinePost post, String? emoji) =>
      timelineClient.react(post.postId, emoji);

  /// Take our post back, for everyone, photos and all.
  Future<void> deletePost(TimelinePost post) =>
      timelineClient.deletePost(post.postId);
}
