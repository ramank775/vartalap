import 'dart:convert';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:vartalap_messaging/core/proto/message.pb.dart';
part 'event.g.dart';

enum ChannelType {
  none,
  individual,
  group,
  other,
}

@JsonSerializable()
class Head {
  Head({
    required this.type,
    required this.to,
    required this.from,
    this.category = 'message',
    this.ephemeral = false,
  });

  late ChannelType type;
  late String to;
  late String from;
  late String category;
  late bool ephemeral;

  static Head fromJson(Map<String, dynamic> json) => _$HeadFromJson(json);

  Map<String, dynamic> toJson() => _$HeadToJson(this);
}

class _MetaJsonConverter implements JsonConverter<Meta, Map<String, dynamic>> {
  const _MetaJsonConverter();
  @override
  Meta fromJson(Map<String, dynamic> json) {
    return Meta()..raw = json;
  }

  @override
  Map<String, dynamic> toJson(Meta object) {
    return object.raw;
  }
}

@JsonSerializable()
class Meta {
  @JsonKey(includeFromJson: false, includeToJson: false)
  Map<String, dynamic> raw = {};
  @JsonKey(includeFromJson: false, includeToJson: false)
  String get hash => raw['hash'];
  @JsonKey(includeFromJson: false, includeToJson: false)
  String get contentHash => raw['contentHash'];
  @JsonKey(includeFromJson: false, includeToJson: false)
  int get createdAt => raw.containsKey('createdAt')
      ? raw['createdAt']
      : DateTime.now().millisecondsSinceEpoch;

  Meta({String? hash, String? contentHash, int? createdAt}) {
    if (hash != null) {
      raw['hash'] = hash;
    }
    if (contentHash != null) {
      raw['contentHash'] = contentHash;
    }
    raw['createdAt'] = createdAt ?? DateTime.now().millisecondsSinceEpoch;
  }

  static Meta fromJson(Map<String, dynamic> json) => _$MetaFromJson(json);

  Map<String, dynamic> toJson() => _$MetaToJson(this);
}

@JsonSerializable()
class RemoteMessage {
  @JsonKey(name: '_v')
  late double version = 2.1;
  late String id;
  late Head head;
  @JsonKey()
  @_MetaJsonConverter()
  late Meta meta;
  late dynamic body;

  static RemoteMessage fromString(String str) {
    final json = jsonDecode(str);
    return RemoteMessage.fromJson(json);
  }

  static RemoteMessage fromJson(Map<String, dynamic> json) =>
      _$RemoteMessageFromJson(json);

  Map<String, dynamic> toJson() => _$RemoteMessageToJson(this);

  @override
  String toString() {
    final map = toJson();
    return jsonEncode(map);
  }

  /// Serialize this message to binary protobuf format.
  Uint8List toBinary() {
    final protoMsg = ProtoMessage(
      version: version,
      id: id,
      type: _toProtoMessageType(head.category),
      channel: _toProtoChannelType(head.type),
      ephemeral: head.ephemeral,
      source: head.from,
      destination: head.to,
      content: body != null
          ? Uint8List.fromList(
              utf8.encode(body is String ? body : jsonEncode(body)))
          : null,
      timestamp: Int64(meta.createdAt),
      meta: meta.raw.map((k, v) => MapEntry(k, v.toString())),
    );
    return protoMsg.writeToBuffer();
  }

  /// Deserialize a message from binary protobuf format.
  static RemoteMessage fromBinary(Uint8List data) {
    final protoMsg = ProtoMessage.fromBuffer(data);
    final msg = RemoteMessage();
    msg.version = protoMsg.version != 0.0 ? protoMsg.version : 2.1;
    msg.id = protoMsg.id;
    msg.head = Head(
      type: _fromProtoChannelType(protoMsg.channel),
      to: protoMsg.destination,
      from: protoMsg.source,
      ephemeral: protoMsg.ephemeral,
      category: _fromProtoMessageType(protoMsg.type),
    );

    // Decode content bytes as JSON body
    if (protoMsg.content != null && protoMsg.content!.isNotEmpty) {
      final contentStr = utf8.decode(protoMsg.content!);
      try {
        msg.body = jsonDecode(contentStr);
      } catch (_) {
        msg.body = {'text': contentStr};
      }
    } else {
      msg.body = {};
    }

    // Build meta from proto meta map
    msg.meta = Meta(
      createdAt: protoMsg.timestamp != Int64.ZERO
          ? protoMsg.timestamp.toInt()
          : DateTime.now().millisecondsSinceEpoch,
    );
    for (final entry in protoMsg.meta.entries) {
      msg.meta.raw[entry.key] = entry.value;
    }

    return msg;
  }

  // --- Proto enum mapping helpers ---

  static int _toProtoChannelType(ChannelType type) {
    switch (type) {
      case ChannelType.individual:
        return ProtoChannelType.INDIVIDUAL;
      case ChannelType.group:
        return ProtoChannelType.GROUP;
      case ChannelType.other:
        return ProtoChannelType.OTHER;
      case ChannelType.none:
        return ProtoChannelType.UNKNOWN;
    }
  }

  static ChannelType _fromProtoChannelType(int type) {
    switch (type) {
      case ProtoChannelType.INDIVIDUAL:
        return ChannelType.individual;
      case ProtoChannelType.GROUP:
        return ChannelType.group;
      case ProtoChannelType.OTHER:
        return ChannelType.other;
      default:
        return ChannelType.none;
    }
  }

  static int _toProtoMessageType(String category) {
    switch (category.toUpperCase()) {
      case 'SERVER_ACK':
        return ProtoMessageType.SERVER_ACK;
      case 'CLIENT_ACK':
        return ProtoMessageType.CLIENT_ACK;
      case 'NOTIFICATION':
        return ProtoMessageType.NOTIFICATION;
      case 'CUSTOM':
        return ProtoMessageType.CUSTOM;
      default:
        return ProtoMessageType.MESSAGE;
    }
  }

  static String _fromProtoMessageType(int type) {
    switch (type) {
      case ProtoMessageType.SERVER_ACK:
        return 'system';
      case ProtoMessageType.CLIENT_ACK:
        return 'system';
      case ProtoMessageType.NOTIFICATION:
        return 'system';
      default:
        return 'message';
    }
  }
}

