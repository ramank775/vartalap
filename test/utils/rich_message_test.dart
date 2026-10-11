import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap/utils/attachment_text.dart';
import 'package:vartalap/utils/rich_message.dart';

void main() {
  test('geo URIs round-trip and reject what is not one', () {
    const p = GeoPoint(12.9716, 77.5946, accuracyM: 14.6);
    expect(p.toUri(), 'geo:12.971600,77.594600;u=15');
    final back = GeoPoint.parse(p.toUri())!;
    expect((back.lat, back.lng, back.accuracyM), (12.9716, 77.5946, 15.0));

    expect(GeoPoint.parse('geo:-33.86,151.2')!.accuracyM, isNull);
    expect(GeoPoint.parse('geo:91,0'), isNull);
    expect(GeoPoint.parse('https://evil.example'), isNull);
  });

  test('an event survives the iCalendar round trip, escapes included', () {
    final start = DateTime(2026, 10, 18, 7, 30);
    final event = EventInfo(
      title: 'Cricket; nets, then match',
      start: start,
      end: start.add(const Duration(hours: 2)),
      location: r'Ground 2\B',
      description: 'Bring a bat\nand water',
    );
    final ics = event.toIcs(uid: 'm-1@vartalap', stamp: DateTime(2026));
    expect(ics, contains(r'SUMMARY:Cricket\; nets\, then match'));
    expect(ics, contains('DTSTART:${_utc(start)}'));

    final back = EventInfo.parse(ics)!;
    expect(back.title, event.title);
    expect(back.start, start);
    expect(back.end, event.end);
    expect(back.location, event.location);
    expect(back.description, event.description);
  });

  test('a foreign VEVENT parses: folded lines, params, all-day dates', () {
    final back = EventInfo.parse('BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\n'
        'DTSTART;VALUE=DATE:20261225\r\n'
        'SUMMARY;LANGUAGE=en:Christ\r\n mas\r\n'
        'END:VEVENT\r\nEND:VCALENDAR')!;
    expect(back.title, 'Christmas');
    expect(back.start, DateTime(2026, 12, 25));
    expect(EventInfo.parse('BEGIN:VEVENT\nSUMMARY:no start\nEND:VEVENT'),
        isNull);
  });

  test('one-line previews say what the message is', () {
    const vcard = 'BEGIN:VCARD\r\nVERSION:3.0\r\nN:Iyer;Asha;;;\r\n'
        'FN:Asha Iyer\r\nTEL:+919000000003\r\nEND:VCARD';
    expect(messagePreview(vcard, kContactType, attachment: false),
        '👤 Asha Iyer');
    expect(messagePreview('geo:1,2', kLocationType, attachment: false),
        '📍 Location');
    final ics = EventInfo(title: 'Nets', start: DateTime(2026))
        .toIcs(uid: 'u', stamp: DateTime(2026));
    expect(messagePreview(ics, kEventType, attachment: false), '📅 Nets');
    expect(messagePreview('hi', 'text/plain', attachment: false), 'hi');
    expect(messagePreview('', 'text/plain', attachment: true), '📄 File');
    expect(messagePreview('Sunset', 'image/jpeg', attachment: true),
        '📷 Sunset');
  });
}

String _utc(DateTime d) {
  final u = d.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${u.year}${two(u.month)}${two(u.day)}T${two(u.hour)}'
      '${two(u.minute)}${two(u.second)}Z';
}
