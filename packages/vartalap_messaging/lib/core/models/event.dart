import 'dart:convert';

import 'package:json_annotation/json_annotation.dart';
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
  @JsonKey(ignore: true)
  Map<String, dynamic> raw = {};
  @JsonKey(ignore: true)
  String get hash => raw['hash'];
  @JsonKey(ignore: true)
  String get contentHash => raw['contentHash'];
  @JsonKey(ignore: true)
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
}
