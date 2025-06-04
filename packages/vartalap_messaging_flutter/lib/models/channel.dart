import 'package:flutter/widgets.dart';
import 'package:vartalap_messaging/vartalap_messaging.dart';
import 'package:vartalap_messaging_flutter/models/member.dart';

class Channel {
  final int? id;
  String? name;
  Image? image;
  final ChannelType type;
  final List<Member> members;
  final String? cid;
  Map<String, dynamic> config;
  Map<String, dynamic>? extraData;

  Channel(
    this.type,
    this.members, {
    this.id,
    this.name,
    this.image,
    this.cid,
    this.config = const {},
    this.extraData,
  });

  Channel.fromDb({
    required this.id,
    required this.type,
    this.cid,
    this.config = const {},
    this.extraData,
    this.members = const [],
  }) {
    name = extraData?['name'];
    image = extraData?['image'];
  }

  get displayName {
    if (name != null) {
      return name!;
    }
    if (members.isNotEmpty) {
      return members.map((m) => m.user.displayName).join(", ");
    }
    return "Unknown";
  }
}

class ChannelFilter {
  final ChannelType? type;
  final String? name;

  ChannelFilter({
    this.type,
    this.name,
  });
}
