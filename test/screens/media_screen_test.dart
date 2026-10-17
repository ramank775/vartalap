/// "Media, links and docs" laid out as WhatsApp does: Media, Docs and
/// Links tabs, month headers, and the last row clear of the nav bar.
///
/// The service is a fake handing back fixed rows; the store tests in
/// vartalap_store cover which message lands in which tab.
library vartalap.screens.media_screen_test;

import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap/screens/chat_info/media.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/widgets/asset_image.dart';
import 'package:vartalap_proto/vartalap_proto.dart' as pb;
import 'package:vartalap_store/vartalap_store.dart';

import '../fake_asset_cache.dart';

void main() {
  Future<void> pump(WidgetTester tester, _FakeChatService chat) async {
    await tester.pumpWidget(MaterialApp(
      home: MediaScreen(
        channelId: 'c-1',
        chatService: chat,
        cache: FakeAssetCache({'shot.png': onePixelPng}),
      ),
    ));
    await tester.pumpAndSettle();
  }

  test('month headers read as WhatsApp words them', () {
    final now = DateTime(2026, 10, 17);
    expect(monthLabel(DateTime(2026, 10, 1), now), 'This month');
    expect(monthLabel(DateTime(2026, 9, 30), now), 'Last month');
    expect(monthLabel(DateTime(2026, 8, 3), now), 'August');
    expect(monthLabel(DateTime(2025, 12, 31), now), 'December 2025');
    expect(monthLabel(DateTime(2025, 12, 31), DateTime(2026, 1, 2)),
        'Last month');
  });

  testWidgets('Media grids photos and videos under month headers',
      (tester) async {
    // Tall enough for all three months without scrolling.
    tester.view.physicalSize = const Size(2400, 4800);
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    await pump(
      tester,
      _FakeChatService(media: [
        _attachment('m-1', 'image/png', 'shot.png', now),
        _attachment('m-2', 'video/mp4', 'clip.mp4',
            DateTime(now.year, now.month - 1, 15),
            durationMs: 7300),
        _attachment('m-3', 'image/png', 'shot.png', DateTime(2025, 9, 15)),
      ]),
    );

    expect(find.text('This month'), findsOneWidget);
    expect(find.text('Last month'), findsOneWidget);
    expect(find.text('September 2025'), findsOneWidget);
    expect(find.byType(AssetImageView), findsNWidgets(2));
    final tile = tester.getSize(find.byType(AssetImageView).first);
    expect(tile.width, tile.height, reason: 'Tiles are square.');
    expect(
      tile.width,
      closeTo((800 - 2 * 2) / 3, 0.01),
      reason: 'Three across, edge to edge, 2 dp apart.',
    );

    // No thumbnail for a video yet: a dark tile with a camera and its
    // length.
    expect(find.byIcon(Icons.videocam), findsOneWidget);
    expect(find.text('00:07'), findsOneWidget);
  });

  testWidgets('Docs lists name, then size · TYPE · date', (tester) async {
    final when = DateTime(2025, 9, 15);
    await pump(
      tester,
      _FakeChatService(files: [
        _attachment('m-1', 'application/pdf', 'accounts.pdf', when),
      ]),
    );
    await tester.tap(find.text('Docs'));
    await tester.pumpAndSettle();

    expect(find.text('accounts.pdf'), findsOneWidget);
    expect(find.text('PDF'), findsOneWidget, reason: 'Extension badge.');
    expect(find.text('2 KB · PDF · Sep 15, 2025'), findsOneWidget);
  });

  testWidgets('Links shows host, URL and the message', (tester) async {
    await pump(
      tester,
      _FakeChatService(links: [
        _text('m-1', '  Tickets: https://example.com/t?id=1.  ',
            DateTime.now()),
      ]),
    );
    await tester.tap(find.text('Links'));
    await tester.pumpAndSettle();

    expect(find.text('example.com'), findsOneWidget);
    expect(find.text('https://example.com/t?id=1'), findsOneWidget);
    expect(find.text('Tickets: https://example.com/t?id=1.'), findsOneWidget);
  });

  testWidgets('each tab has its own empty state', (tester) async {
    await pump(tester, _FakeChatService());

    expect(find.text('No media'), findsOneWidget);
    await tester.tap(find.text('Docs'));
    await tester.pumpAndSettle();
    expect(find.text('No docs'), findsOneWidget);
    await tester.tap(find.text('Links'));
    await tester.pumpAndSettle();
    expect(find.text('No links'), findsOneWidget);
  });

  testWidgets('the last row scrolls clear of the nav bar', (tester) async {
    // 48 dp of gesture/nav bar at the bottom (the test view is 3x).
    tester.view.padding = const FakeViewPadding(bottom: 144);
    addTearDown(tester.view.reset);
    final when = DateTime(2025, 9, 15);
    await pump(
      tester,
      _FakeChatService(files: [
        for (var i = 0; i < 20; i++)
          _attachment('m-$i', 'application/pdf', 'doc-$i.pdf', when),
      ]),
    );
    await tester.tap(find.text('Docs'));
    await tester.pumpAndSettle();
    await tester.drag(find.text('doc-0.pdf'), const Offset(0, -5000));
    await tester.pumpAndSettle();

    final last = find.ancestor(
      of: find.text('doc-19.pdf'),
      matching: find.byType(ListTile),
    );
    expect(tester.getRect(last).bottom, lessThanOrEqualTo(600 - 48));
  });
}

MessageRow _row(
  String id,
  String contentType,
  DateTime at, {
  String? body,
  pb.Attachment? attachment,
}) =>
    MessageRow(
      messageId: id,
      channelId: 'c-1',
      authorUserId: 'u-peer',
      body: body,
      contentType: contentType,
      replyToMessageId: null,
      clientTimestampMs: at.millisecondsSinceEpoch,
      serverTimestampMs: at.millisecondsSinceEpoch,
      state: MessageState.sent,
      stateUpdatedAt: at.millisecondsSinceEpoch,
      isEdited: false,
      lastEditMs: null,
      tombstoned: false,
      tombstonePendingUntil: null,
      attachments: attachment == null
          ? null
          : pb.ChatPayload(attachments: [attachment]).writeToBuffer(),
    );

MessageRow _attachment(
  String id,
  String mime,
  String filename,
  DateTime at, {
  int durationMs = 0,
}) =>
    _row(id, mime, at,
        attachment: pb.Attachment(
          url: filename,
          mimeType: mime,
          filename: filename,
          sizeBytes: fixnum.Int64(2048),
          durationMs: durationMs,
        ));

MessageRow _text(String id, String body, DateTime at) =>
    _row(id, 'text/plain', at, body: body);

class _FakeChatService implements ChatService {
  final List<MessageRow> media;
  final List<MessageRow> files;
  final List<MessageRow> links;

  _FakeChatService({
    this.media = const [],
    this.files = const [],
    this.links = const [],
  });

  @override
  Future<List<MessageRow>> fetchMedia(String channelId) async => media;

  @override
  Future<List<MessageRow>> fetchFiles(String channelId) async => files;

  @override
  Future<List<MessageRow>> fetchLinks(String channelId) async => links;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
