/// Decision 233's screens: chat info's Albums, an album's grid with its
/// Add photos button, the full-screen viewer, and the chat message that
/// opens an album. Over a fake service; the REST calls themselves are
/// test/services/album_service_test.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap/screens/albums/albums.dart';
import 'package:vartalap/screens/chat/rich_messages.dart';
import 'package:vartalap/services/album_client.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/asset_image.dart';
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_transport/vartalap_transport.dart'
    show AuthClientException;

const _me = '00000000a';
const _asha = '00000000b';
const _group = '0190aaaa-bbbb-7ccc-8ddd-000000000001';

final _keptUntil = DateTime(2027, 2, 5).millisecondsSinceEpoch;

Album _album({String creator = _asha, int photos = 2}) => Album(
      albumId: 'a1',
      channelId: _group,
      title: 'Diwali 2026',
      date: '2026-11-01',
      creator: creator,
      createdAt: 1,
      keptUntil: _keptUntil,
      photoCount: photos,
      cover: photos == 0 ? null : const AlbumPhoto('f2', uploader: _me),
    );

Future<void> _pump(WidgetTester tester, Widget home) async {
  await tester.pumpWidget(MaterialApp(theme: lightThemeData, home: home));
  await tester.pumpAndSettle();
}

Widget _tile(_FakeChat svc, {String? peer}) => Scaffold(
      body: ListView(children: [
        AlbumsTile(chatService: svc, channelId: _group, peer: peer),
      ]),
    );

void main() {
  testWidgets("chat info's Albums row: how many and the covers; opens them",
      (tester) async {
    final svc = _FakeChat()..albums = [_album()];
    await _pump(tester, _tile(svc));

    expect(find.text('Albums'), findsOneWidget);
    expect(find.text('1 album'), findsOneWidget);
    expect(find.byType(AssetImageView), findsOneWidget, reason: 'its cover');
    expect(svc.calls, ['albumsOf($_group, null)']);

    await tester.tap(find.text('Albums'));
    await tester.pumpAndSettle();
    expect(find.byType(AlbumsScreen), findsOneWidget);
    expect(find.text('Diwali 2026'), findsOneWidget);
    expect(find.text('1 Nov 2026 · 2 photos'), findsOneWidget);
    expect(find.text('New album'), findsOneWidget);
  });

  testWidgets('a 1:1 the server shuts (not connected, blocked): no row',
      (tester) async {
    final svc = _FakeChat()..refuse = 403;
    await _pump(tester, _tile(svc, peer: _asha));
    expect(find.text('Albums'), findsNothing);
    expect(svc.calls, ['albumsOf($_group, $_asha)']);
  });

  testWidgets('New album: a name and an optional day, then the album opens',
      (tester) async {
    final svc = _FakeChat()..page = [];
    await _pump(
        tester, AlbumsScreen(chatService: svc, channelId: _group, peer: _asha));
    expect(find.text('No albums yet'), findsOneWidget);

    await tester.tap(find.text('New album'));
    await tester.pumpAndSettle();
    final create = find.widgetWithText(TextButton, 'Create');
    expect(tester.widget<TextButton>(create).onPressed, isNull,
        reason: 'no name yet');
    await tester.enterText(find.byType(TextField), '  Diwali 2026 ');
    await tester.pump();
    await tester.tap(create);
    await tester.pumpAndSettle();

    expect(svc.calls, contains('create($_group, $_asha, Diwali 2026, null)'));
    expect(find.byType(AlbumScreen), findsOneWidget);
    expect(find.text('No photos yet'), findsOneWidget);
    expect(find.text('Album kept until 5 Feb 2027'), findsOneWidget);
  });

  testWidgets(
      "someone else's album: add photos, remove only your own, no rename",
      (tester) async {
    final svc = _FakeChat()
      ..page = const [
        AlbumPhoto('f2', uploader: _me, addedAt: 2),
        AlbumPhoto('f1', uploader: _asha, addedAt: 1),
      ];
    await _pump(
        tester,
        AlbumScreen(
          chatService: svc,
          channelId: _group,
          albumId: 'a1',
          pickPhotos: (camera) async => ['/photos/$camera.jpg'],
        ));

    expect(find.byType(PopupMenuButton<String>), findsNothing,
        reason: 'not the creator, not an admin');
    expect(find.byType(GridView), findsOneWidget);

    await tester.tap(find.text('Add photos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose from gallery'));
    await tester.pumpAndSettle();
    expect(svc.calls, contains('add(a1, [/photos/false.jpg])'));

    // the viewer: ours first, with Remove; swipe to Asha's, without
    await tester.tap(find.byType(AssetImageView).first);
    await tester.pumpAndSettle();
    expect(find.text('You'), findsOneWidget);
    expect(find.byTooltip('Save to phone'), findsOneWidget);
    expect(find.byTooltip('Remove photo'), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('Asha'), findsOneWidget);
    expect(find.byTooltip('Remove photo'), findsNothing);

    await tester.drag(find.byType(PageView), const Offset(600, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(svc.calls.last, 'remove(a1, f2)');
    expect(find.text('Asha'), findsOneWidget, reason: 'the next photo shows');
  });

  testWidgets('a group admin renames and deletes an album', (tester) async {
    final svc = _FakeChat()
      ..role = 'admin'
      ..page = const [AlbumPhoto('f1', uploader: _asha, addedAt: 1)];
    await tester.pumpWidget(MaterialApp(
      theme: lightThemeData,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => AlbumScreen(
                  chatService: svc, channelId: _group, albumId: 'a1'),
            )),
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Diwali at home');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(svc.calls.last, 'edit(a1, Diwali at home)');

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete album'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(svc.calls.last, 'delete(a1)');
    expect(find.byType(AlbumScreen), findsNothing, reason: 'back to the chat');
  });

  testWidgets('an album that is gone says so, with no Add photos',
      (tester) async {
    final svc = _FakeChat()..refuse = 404;
    await _pump(tester,
        AlbumScreen(chatService: svc, channelId: _group, albumId: 'a1'));
    expect(find.text('This album is not here any more'), findsOneWidget);
    expect(find.text('Add photos'), findsNothing);
  });

  testWidgets('the chat message says which album and offers to open it',
      (tester) async {
    await _pump(
        tester,
        Scaffold(
          body: RichMessageView(
            contentType: kAlbumType,
            body: const AlbumNote('a1', _group, 'Diwali 2026').encode(),
            tint: Colors.black,
          ),
        ));
    expect(find.text('Diwali 2026'), findsOneWidget);
    expect(find.text('Created a new album'), findsOneWidget);
    expect(find.text('Open album'), findsOneWidget);
  });
}

class _FakeChat implements ChatService {
  final calls = <String>[];
  List<Album> albums = const [];
  List<AlbumPhoto> page = const [];
  String role = 'member';

  /// Every album call fails with this status.
  int? refuse;

  void _check() {
    if (refuse != null) {
      throw AuthClientException('album', refuse!, 'forbidden', null);
    }
  }

  @override
  String? get selfUserId => _me;

  @override
  Future<List<Album>> albumsOf(String channelId, {String? peer}) async {
    calls.add('albumsOf($channelId, $peer)');
    _check();
    return albums;
  }

  @override
  Future<Album> createAlbum({
    required String channelId,
    String? peer,
    required String title,
    String? date,
  }) async {
    calls.add('create($channelId, $peer, $title, $date)');
    return _album(creator: _me, photos: 0);
  }

  @override
  Future<AlbumPage> albumPage(String channelId, String albumId,
      {bool newestFirst = true, String? cursor}) async {
    _check();
    return (album: _album(photos: page.length), photos: page, next: null);
  }

  @override
  Future<Album> addAlbumPhotos(Album album, List<String> paths,
      {void Function(int added)? onAdded}) async {
    calls.add('add(${album.albumId}, $paths)');
    onAdded?.call(paths.length);
    return album;
  }

  @override
  Future<void> removeAlbumPhoto(Album album, AlbumPhoto photo) async =>
      calls.add('remove(${album.albumId}, ${photo.fileId})');

  @override
  Future<Album> editAlbum(Album album, {String? title, String? date}) async {
    calls.add('edit(${album.albumId}, $title)');
    return _album();
  }

  @override
  Future<void> deleteAlbum(Album album) async =>
      calls.add('delete(${album.albumId})');

  @override
  Future<List<ChannelMemberRow>> fetchChannelMembers(String channelId) async =>
      [
        ChannelMemberRow(
            channelId: channelId,
            userId: _me,
            role: role,
            joinedAt: 1,
            contact: null),
        ChannelMemberRow(
            channelId: channelId,
            userId: _asha,
            role: 'owner',
            joinedAt: 1,
            contact: ContactRow(
                userId: _asha, contactBookName: 'Asha', lastRefreshedMs: 0)),
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
