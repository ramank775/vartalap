/// Contact, location and event messages (decision 133): `content_type`
/// names the kind and `body` carries a standard text format, so system
/// apps can take them as-is and the protocol needs no new fields.
library;

import 'package:flutter_contacts/flutter_contacts.dart';

const kContactType = 'text/vcard';
const kLocationType = 'text/x-geo';
const kEventType = 'text/calendar';

/// Name on a shared vCard, or 'Contact' when it has none.
String contactName(String vcard) {
  try {
    final name = FlutterContacts.vCard.import(vcard).firstOrNull?.displayName;
    return (name == null || name.isEmpty) ? 'Contact' : name;
  } catch (_) {
    return 'Contact';
  }
}

/// An RFC 5870 geo URI: `geo:<lat>,<lng>[;u=<metres>]`.
class GeoPoint {
  final double lat;
  final double lng;
  final double? accuracyM;

  const GeoPoint(this.lat, this.lng, {this.accuracyM});

  String toUri() => 'geo:${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}'
      '${accuracyM == null ? '' : ';u=${accuracyM!.round()}'}';

  /// Null for anything that is not a geo URI on Earth.
  static GeoPoint? parse(String uri) {
    final m = RegExp(r'^geo:(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)(?:,[^;]*)?(.*)$')
        .firstMatch(uri.trim());
    if (m == null) return null;
    final lat = double.parse(m[1]!);
    final lng = double.parse(m[2]!);
    if (lat.abs() > 90 || lng.abs() > 180) return null;
    final u = RegExp(r';u=(\d+(?:\.\d+)?)').firstMatch(m[3]!);
    return GeoPoint(lat, lng, accuracyM: u == null ? null : double.parse(u[1]!));
  }
}

/// One iCalendar VEVENT — what an event message carries.
class EventInfo {
  final String title;
  final DateTime start;
  final DateTime? end;
  final String location;
  final String description;

  const EventInfo({
    required this.title,
    required this.start,
    this.end,
    this.location = '',
    this.description = '',
  });

  /// A one-event VCALENDAR. Times go out in UTC.
  ///
  /// ponytail: no 75-octet line folding; readers unfold anyway and the
  /// calendar hand-off uses intent extras, not this text.
  String toIcs({required String uid, required DateTime stamp}) => [
        'BEGIN:VCALENDAR',
        'VERSION:2.0',
        'PRODID:-//Vartalap//EN',
        'BEGIN:VEVENT',
        'UID:$uid',
        'DTSTAMP:${_utc(stamp)}',
        'DTSTART:${_utc(start)}',
        if (end != null) 'DTEND:${_utc(end!)}',
        'SUMMARY:${_escape(title)}',
        if (location.isNotEmpty) 'LOCATION:${_escape(location)}',
        if (description.isNotEmpty) 'DESCRIPTION:${_escape(description)}',
        'END:VEVENT',
        'END:VCALENDAR',
      ].join('\r\n');

  /// The first VEVENT in [ics], or null without a readable DTSTART.
  static EventInfo? parse(String ics) {
    final props = <String, String>{};
    var inEvent = false;
    for (final line
        in ics.replaceAll(RegExp(r'\r?\n[ \t]'), '').split(RegExp(r'\r?\n'))) {
      if (line == 'BEGIN:VEVENT') {
        inEvent = true;
      } else if (line == 'END:VEVENT') {
        break;
      } else if (inEvent) {
        final colon = line.indexOf(':');
        if (colon < 0) continue;
        final name = line.substring(0, colon).split(';').first.toUpperCase();
        props.putIfAbsent(name, () => line.substring(colon + 1));
      }
    }
    final start = _time(props['DTSTART']);
    if (start == null) return null;
    return EventInfo(
      title: _unescape(props['SUMMARY'] ?? ''),
      start: start,
      end: _time(props['DTEND']),
      location: _unescape(props['LOCATION'] ?? ''),
      description: _unescape(props['DESCRIPTION'] ?? ''),
    );
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _utc(DateTime d) {
    final u = d.toUtc();
    return '${u.year.toString().padLeft(4, '0')}${_two(u.month)}${_two(u.day)}'
        'T${_two(u.hour)}${_two(u.minute)}${_two(u.second)}Z';
  }

  /// `…Z` is UTC; a bare date-time (or one with a TZID we don't
  /// resolve) is read as local; a bare date is local midnight.
  static DateTime? _time(String? v) {
    if (v == null) return null;
    final m = RegExp(r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z)?)?$')
        .firstMatch(v.trim());
    if (m == null) return null;
    final p = [for (var i = 1; i <= 6; i++) int.parse(m[i] ?? '0')];
    return m[7] != null
        ? DateTime.utc(p[0], p[1], p[2], p[3], p[4], p[5]).toLocal()
        : DateTime(p[0], p[1], p[2], p[3], p[4], p[5]);
  }

  static String _escape(String s) => s
      .replaceAll(r'\', r'\\')
      .replaceAll(';', r'\;')
      .replaceAll(',', r'\,')
      .replaceAll('\n', r'\n');

  static String _unescape(String s) => s.replaceAllMapped(
        RegExp(r'\\([\\;,nN])'),
        (m) => (m[1] == 'n' || m[1] == 'N') ? '\n' : m[1]!,
      );
}
