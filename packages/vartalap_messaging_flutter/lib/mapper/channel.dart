import 'package:vartalap_messaging_flutter/db/chat_db.dart';
import 'package:vartalap_messaging_flutter/models/models.dart';

extension ChannelEntityX on ChannelEntity {
  /// Converts a [ChannelEntity] to a [ChannelModel].
  ChannelModel toModel() {
    return ChannelModel(
      type: type,
      id: id,
      cid: cid,
      isMuted: muted,
      config: ChannelConfig.fromJson(config),
      extraData: extraData ?? {},
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

extension ChannelModelX on ChannelModel {
  /// Converts a [ChannelModel] to a [ChannelEntity].
  ChannelEntity toEntity() {
    return ChannelEntity(
      id: id,
      type: type,
      extraData: extraData,
      config: config?.toJson() ?? {},
      muted: isMuted,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
