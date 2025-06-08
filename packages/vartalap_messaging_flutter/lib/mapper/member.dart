import 'package:vartalap_messaging_flutter/db/chat_db.dart';
import 'package:vartalap_messaging_flutter/models/models.dart';

extension MemberEntityX on MemberEntity {
  /// Converts a [MemberEntity] to a [MemberModel].
  Member toModel({required Contact contact}) {
    return Member(
      user: contact,
      role: role,
      since: since,
      updatedAt: updatedAt,
    );
  }
}

extension MemberModelX on Member {
  /// Converts a [Member] to a [MemberEntity].
  MemberEntity toEntity({required int channelId}) {
    return MemberEntity(
      channelId: channelId,
      memberId: user.id,
      role: role,
      since: since,
      updatedAt: updatedAt,
    );
  }
}
