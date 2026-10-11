import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap/utils/attachment_text.dart';
import 'package:vartalap_store/vartalap_store.dart';

void main() {
  String text(GroupEvent e, {String actor = 'u-asha'}) => groupEventText(
        e,
        actorUserId: actor,
        selfUserId: 'u-me',
        nameOf: (id) => {'u-asha': 'Asha', 'u-ravi': 'Ravi', 'u-li': 'Li'}[id]!,
      );

  test('words each event the way WhatsApp does', () {
    expect(text(const GroupEvent(GroupEventKind.created, text: 'Trip')),
        'Asha created group "Trip"');
    expect(text(const GroupEvent(GroupEventKind.added, users: ['u-me'])),
        'Asha added you');
    expect(
        text(const GroupEvent(GroupEventKind.added,
            users: ['u-ravi', 'u-li', 'u-me'])),
        'Asha added Ravi, Li and you');
    expect(text(const GroupEvent(GroupEventKind.removed, users: ['u-ravi']),
            actor: 'u-me'),
        'You removed Ravi');
    expect(text(const GroupEvent(GroupEventKind.left, users: ['u-ravi'])),
        'Ravi left');
    expect(text(const GroupEvent(GroupEventKind.renamed, text: 'Trip 2')),
        'Asha changed the group name to "Trip 2"');
    expect(text(const GroupEvent(GroupEventKind.photo, text: 'f1')),
        "Asha changed this group's icon");
    expect(text(const GroupEvent(GroupEventKind.photo, text: '')),
        "Asha deleted this group's icon");
  });

  test('a body round-trips, and one from a newer client reads as null', () {
    const e = GroupEvent(GroupEventKind.added, users: ['u-ravi']);
    final back = GroupEvent.parse(e.encode())!;
    expect(back.kind, GroupEventKind.added);
    expect(back.users, ['u-ravi']);
    expect(GroupEvent.parse('{"k":"pinned"}'), isNull);
    expect(GroupEvent.parse('not json'), isNull);
  });
}
