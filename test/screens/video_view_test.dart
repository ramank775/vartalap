/// The in-app video player and the send preview's video, over a fake
/// player platform (no ExoPlayer under `flutter test`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap/screens/chat/attachment_preview.dart';
import 'package:vartalap/screens/chat/video_view.dart';
import 'package:vartalap_proto/vartalap_proto.dart' as pb;
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../fake_asset_cache.dart';

class _FakeVideos extends VideoPlayerPlatform {
  final calls = <String>[];
  Duration position = Duration.zero;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    calls.add('open ${options.dataSource.uri}');
    return 1;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => Stream.value(VideoEvent(
        eventType: VideoEventType.initialized,
        duration: const Duration(seconds: 75),
        size: const Size(320, 180),
      ));

  @override
  Future<void> play(int playerId) async => calls.add('play');

  @override
  Future<void> pause(int playerId) async => calls.add('pause');

  @override
  Future<void> seekTo(int playerId, Duration to) async {
    calls.add('seek');
    position = to;
  }

  @override
  Future<Duration> getPosition(int playerId) async => position;

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<void> dispose(int playerId) async => calls.add('dispose');

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const ColoredBox(color: Colors.blue, key: Key('frames'));
}

/// The opened copy of a received video is at /videos/<url>; 'gone' has
/// none.
class _Cache extends FakeAssetCache {
  _Cache() : super({});

  @override
  Future<String?> file(String uri) async =>
      uri == 'gone' ? null : '/videos/$uri';
}

void main() {
  late _FakeVideos videos;

  setUp(() => VideoPlayerPlatform.instance = videos = _FakeVideos());

  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  pb.Attachment video(String url) => pb.Attachment(
        url: url,
        mimeType: 'video/mp4',
        filename: 'clip.mp4',
        thumbnail: onePixelPng,
      );

  testWidgets(
      'a video plays at once from its opened file: pause, seek, time, '
      'and Open with… in the menu', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: VideoPlayerScreen(video: video('file-1'), cache: _Cache())));
    await frames(tester);

    expect(videos.calls.first, 'open file:///videos/file-1');
    expect(videos.calls.last, 'play');
    expect(find.byKey(const Key('frames')), findsOneWidget);
    expect(find.text('00:00'), findsOneWidget);
    expect(find.text('01:15'), findsOneWidget);
    expect(find.text('clip.mp4'), findsOneWidget);

    await tester.tap(find.byTooltip('Pause'));
    await frames(tester);
    expect(videos.calls.last, 'pause');
    expect(find.byTooltip('Play video'), findsOneWidget,
        reason: 'paused: the big play button is back');

    await tester.tap(find.byType(Slider));
    await frames(tester);
    expect(videos.calls.last, 'seek');
    expect(videos.position.inSeconds, closeTo(37, 2),
        reason: 'the middle of a 75 s video');

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    expect(find.text('Open with…'), findsOneWidget);
  });

  testWidgets('nothing to play says so; Open with… stays', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: VideoPlayerScreen(video: video('gone'), cache: _Cache())));
    await frames(tester);
    expect(find.text("Couldn't play this video"), findsOneWidget);
    expect(videos.calls, isEmpty);
    expect(find.byTooltip('More options'), findsOneWidget);
  });

  testWidgets(
      'the send preview shows a video with a play button and plays it in '
      'place; Send still sends', (tester) async {
    final popped = <AttachmentChoice?>[];
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => popped.add(await Navigator.of(context)
              .push<AttachmentChoice>(MaterialPageRoute(
                  builder: (_) => const AttachmentPreviewScreen(
                      path: '/picked/clip.mp4')))),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await frames(tester);
    expect(videos.calls, isEmpty, reason: 'nothing plays until asked');

    await tester.tap(find.byTooltip('Play video'));
    await frames(tester);
    expect(videos.calls.first, 'open file:///picked/clip.mp4');
    expect(videos.calls.last, 'play');
    expect(find.byKey(const Key('frames')), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Send'));
    await tester.pumpAndSettle();
    // The player's dispose awaits a root-zone future: let real time run.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(popped, [(caption: '', hd: false)]);
    expect(videos.calls.last, 'dispose', reason: 'the player let go');
  });
}
