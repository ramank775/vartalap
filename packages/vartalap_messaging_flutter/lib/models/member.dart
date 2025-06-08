import 'contact.dart';

class Member {
  final Contact user;
  final String? role;
  final DateTime since;
  DateTime updatedAt;

  Member({
    required this.user,
    this.role,
    required this.since,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();
}
