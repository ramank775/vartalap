import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap_messaging_flutter/db/chat_db.dart';
import 'package:vartalap_messaging_flutter/mapper/mapper.dart';
import 'package:vartalap_messaging_flutter/models/models.dart';

void main() {
  group('Member Mapper Tests', () {
    test('MemberEntity.toModel maps fields correctly', () {
      final since = DateTime.utc(2025, 1, 1, 12, 0, 0);
      final updatedAt = DateTime.utc(2025, 1, 2, 12, 0, 0);

      const contact = Contact(
        id: 42,
        username: 'alice',
        uid: 'uid_alice',
        status: ContactStatus.active,
      );

      final entity = MemberEntity(
        channelId: 7,
        memberId: 42,
        role: 'admin',
        since: since,
        updatedAt: updatedAt,
        deletedAt: null,
      );

      final model = entity.toModel(contact: contact);

      expect(model.user.id, 42);
      expect(model.user.username, 'alice');
      expect(model.user.uid, 'uid_alice');
      expect(model.role, 'admin');
      expect(model.since, since);
      expect(model.updatedAt, updatedAt);
    });

    test('Member.toEntity maps fields correctly', () {
      final since = DateTime.utc(2025, 2, 1, 10, 0, 0);
      final updatedAt = DateTime.utc(2025, 2, 2, 10, 0, 0);

      const contact = Contact(
        id: 7,
        username: 'bob',
        uid: 'uid_bob',
        status: ContactStatus.active,
      );

      final member = Member(
        user: contact,
        role: 'member',
        since: since,
        updatedAt: updatedAt,
      );

      final entity = member.toEntity(channelId: 99);

      expect(entity.channelId, 99);
      expect(entity.memberId, 7);
      expect(entity.role, 'member');
      expect(entity.since, since);
      expect(entity.updatedAt, updatedAt);
    });
  });
}
