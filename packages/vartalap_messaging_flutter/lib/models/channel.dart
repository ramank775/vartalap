import 'package:flutter/widgets.dart';
import 'package:vartalap_messaging/vartalap_messaging.dart';
import 'package:vartalap_messaging_flutter/entity/entity.dart';

class Channel {
  final int? id;
  final String? name;
  final Image? image;
  final ChannelType type;
  final List<Members> members;
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
}
