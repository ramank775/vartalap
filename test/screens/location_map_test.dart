/// Map previews (OpenStreetMap, item 135): the location bubble, its full
/// map, and the Send location screen. Tiles are blank in tests
/// (flutter_test_config.dart).
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:vartalap/screens/chat/live_location.dart';
import 'package:vartalap/screens/chat/rich_messages.dart';
import 'package:vartalap/utils/rich_message.dart';
import 'package:vartalap/widgets/location_map.dart';

void main() {
  testWidgets(
      'a location bubble shows a fixed, still map with the pin; '
      'a tap opens the full map with Open in Maps', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RichMessageView(
          contentType: kLocationType,
          body: const GeoPoint(12.9716, 77.5946, accuracyM: 12).toUri(),
          tint: Colors.black,
        ),
      ),
    ));
    expect(find.byKey(const Key('map-tiles')), findsOneWidget,
        reason: 'the test tiles, never the network');
    expect(tester.getSize(find.byType(MapThumbnail)).height, 140);
    expect(
        tester
            .widget<MarkerLayer>(find.byType(MarkerLayer))
            .markers
            .single
            .point,
        const LatLng(12.9716, 77.5946));
    expect(find.text(kOsmAttribution), findsOneWidget);
    expect(find.text('Accurate to 12 m'), findsOneWidget);
    expect(
        tester
            .widget<FlutterMap>(find.byType(FlutterMap))
            .options
            .interactionOptions
            .flags,
        InteractiveFlag.none);

    await tester.tap(find.byType(MapThumbnail));
    await tester.pumpAndSettle();
    expect(find.byType(LocationMapScreen), findsOneWidget);
    expect(find.text('Open in Maps'), findsOneWidget);
    expect(find.text(kOsmAttribution), findsOneWidget);
    expect(find.textContaining('Accurate to 12 m'), findsOneWidget);
    expect(find.byType(CircleLayer), findsOneWidget, reason: 'the accuracy');
    expect(
        tester
                .widget<FlutterMap>(find.byType(FlutterMap))
                .options
                .interactionOptions
                .flags &
            InteractiveFlag.pinchZoom,
        isNonZero,
        reason: 'the full map pans and zooms');
  });

  testWidgets('an unreadable location has no map', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: RichMessageView(
            contentType: kLocationType, body: 'oops', tint: Colors.black),
      ),
    ));
    expect(find.text('Unreadable location'), findsOneWidget);
    expect(find.byType(FlutterMap), findsNothing);
  });

  group('Send location', () {
    Future<List<Object?>> open(
        WidgetTester tester, Future<GeoPoint?> Function() locate) async {
      final popped = <Object?>[];
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => popped.add(await Navigator.of(context)
                .push<Object>(MaterialPageRoute(
                    builder: (_) => SendLocationScreen(locate: locate)))),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return popped;
    }

    testWidgets('shows where you are, then sends that point', (tester) async {
      const here = GeoPoint(28.61, 77.2, accuracyM: 9);
      final popped = await open(tester, () async => here);
      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.text('Accurate to 9 m'), findsOneWidget);
      expect(find.text(kOsmAttribution), findsOneWidget);
      await tester.tap(find.text('Send your current location'));
      await tester.pumpAndSettle();
      expect(popped, [here]);
    });

    testWidgets('Share live location pops live', (tester) async {
      final popped = await open(tester, () async => const GeoPoint(1, 2));
      await tester.tap(find.text('Share live location'));
      await tester.pumpAndSettle();
      expect(popped, [SendLocationScreen.kShareLive]);
    });

    testWidgets('no fix: says so, cannot send, and Try again finds it',
        (tester) async {
      GeoPoint? fix;
      final popped = await open(tester, () async => fix);
      expect(find.textContaining("Couldn't get your location"), findsOneWidget);
      expect(find.byType(FlutterMap), findsNothing);
      await tester.tap(find.text('Send your current location'));
      await tester.pumpAndSettle();
      expect(popped, isEmpty, reason: 'nothing to send yet');

      fix = const GeoPoint(1, 2);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.byType(FlutterMap), findsOneWidget);
    });
  });
}
