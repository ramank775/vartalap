import 'dart:typed_data';

import 'package:flutter/widgets.dart';

enum ContactStatus {
  active,
  deleted,
  unknown,
  other,
}

class Contact {
  final int? id;
  final String? username;
  final String? uid;
  final String? phone;
  final String? name;
  final Uint8List? thumbnail;
  final String? photo;
  final Map<String, dynamic>? extraData;
  final ContactStatus status;

  const Contact({
    this.id,
    required this.username,
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
