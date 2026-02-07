import 'dart:typed_data';

import 'package:flutter/widgets.dart';

enum ContactStatus {
  active,
  deleted,
  unknown,
  other,
}

class Contact {
  final int id;
  final String? username;
  final String? uid;
  final String? phone;
  final String? name;
  final Uint8List? thumbnail;
  final String? photo;
  final Map<String, dynamic>? extraData;
  final ContactStatus status;

  const Contact({
    required this.id,
    required this.username,
    this.uid,
    this.phone,
    this.name,
    this.thumbnail,
    this.photo,
    this.extraData,
    required this.status,
  });

  // Constructor for creating Contact from database row
  const Contact.fromDb({
    required this.id,
    this.username,
    this.uid,
    this.phone,
    this.name,
    this.thumbnail,
    this.photo,
    this.extraData,
    required this.status,
  });

  String get displayName => name ?? phone ?? username ?? '';

  Image get displayImage => photo != null
      ? Image.network(photo!)
      : thumbnail != null
          ? Image.memory(thumbnail!)
          : Image.asset('user.png');

  bool get hasAccount => username != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Contact &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          uid == other.uid;

  @override
  int get hashCode => id.hashCode ^ uid.hashCode;
}

class ContactFilter {
  final String? username;
  final String? name;
  final String? phone;
  final ContactStatus? status;

  const ContactFilter({
    this.username,
    this.name,
    this.phone,
    this.status,
  });
}
