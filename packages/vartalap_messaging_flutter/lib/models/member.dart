import 'contact.dart';

class Member {
  final String? membershipId;
  final Contact user;
  final String role;
  final DateTime since;

  Member({
    required this.user,
    required this.role,
    required this.since,
    this.membershipId,
  });
}
