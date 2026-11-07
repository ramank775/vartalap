/// Maps (decision 135 amended, owner 2026-11-07): OpenStreetMap's own
/// tiles through flutter_map, with no key and no Google SDK.
///
/// OSM's tile usage policy, and how it is kept: the app's id in the
/// User-Agent; "© OpenStreetMap contributors" on every map; tiles only
/// for a map on screen (flutter_map asks for the visible ones, nothing is
/// prefetched or bulk downloaded); the HTTP cache headers honoured
/// (flutter_map's built-in disk cache) over one kept-alive connection.
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:http/retry.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vartalap/utils/rich_message.dart';

const kOsmAttribution = '© OpenStreetMap contributors';

/// One client for every map, so tiles share a connection; never closed.
final http.Client _http = RetryClient(http.Client());

/// The tiles every map draws. Tests swap in a blank layer: no network.
Widget Function() mapTiles = () => TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.one9x.vartalap',
      maxNativeZoom: 19,
      // One per layer: a layer disposes its provider.
      tileProvider: NetworkTileProvider(
        httpClient: _http,
        silenceExceptions: true,
        cachingProvider: BuiltInMapCachingProvider.getOrCreateInstance(
            maxCacheSize: 50000000),
      ),
    );

/// [point] on a map: a red pin, the accuracy as a circle when known, and
/// OSM's attribution. Pans and zooms only when [interactive].
class LocationMap extends StatelessWidget {
  final GeoPoint point;
  final bool interactive;
  final double zoom;
  final MapController? controller;

  const LocationMap({
    super.key,
    required this.point,
    this.interactive = false,
    this.zoom = 16,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final at = LatLng(point.lat, point.lng);
    final accuracy = point.accuracyM;
    const blue = Color(0xFF1E88E5);
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: at,
        initialZoom: zoom,
        maxZoom: 19,
        interactionOptions: InteractionOptions(
          flags: interactive
              ? InteractiveFlag.all & ~InteractiveFlag.rotate
              : InteractiveFlag.none,
        ),
      ),
      children: [
        mapTiles(),
        if (accuracy != null && accuracy > 0)
          CircleLayer(circles: [
            CircleMarker(
              point: at,
              radius: accuracy,
              useRadiusInMeter: true,
              color: blue.withValues(alpha: 0.15),
              borderColor: blue.withValues(alpha: 0.5),
              borderStrokeWidth: 1,
            ),
          ]),
        MarkerLayer(markers: [
          Marker(
            point: at,
            width: 40,
            height: 40,
            // The pin's tip on the point.
            alignment: Alignment.topCenter,
            child: const Icon(Icons.location_on,
                color: Color(0xFFE53935), size: 40),
          ),
        ]),
        Align(
          alignment: Alignment.bottomRight,
          child: GestureDetector(
            onTap: interactive
                ? () => launchUrl(
                      Uri.parse('https://www.openstreetmap.org/copyright'),
                      mode: LaunchMode.externalApplication,
                    ).catchError((_) => false)
                : null,
            child: const ColoredBox(
              color: Color(0xB3FFFFFF),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                child: Text(kOsmAttribution,
                    style: TextStyle(fontSize: 10, color: Colors.black87)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The map on a bubble: fixed height so the chat never jumps, and dead to
/// touch so the bubble's tap and long press work over it. A new [point]
/// draws a new map ([FlutterMap] takes its centre only once). [ended]
/// greys it, like an ended live location.
class MapThumbnail extends StatelessWidget {
  final GeoPoint point;
  final bool ended;
  final double height;

  const MapThumbnail({
    super.key,
    required this.point,
    this.ended = false,
    this.height = 140,
  });

  @override
  Widget build(BuildContext context) {
    Widget map =
        LocationMap(key: ValueKey((point.lat, point.lng)), point: point);
    if (ended) {
      map = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          0.2126, 0.7152, 0.0722, 0, 0, //
          0.2126, 0.7152, 0.0722, 0, 0, //
          0.2126, 0.7152, 0.0722, 0, 0, //
          0, 0, 0, 0.6, 0,
        ]),
        child: map,
      );
    }
    return SizedBox(
      height: height,
      child: IgnorePointer(child: RepaintBoundary(child: map)),
    );
  }
}
