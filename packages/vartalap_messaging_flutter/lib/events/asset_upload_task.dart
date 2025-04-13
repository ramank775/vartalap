import 'package:drift/drift.dart';
import 'package:vartalap_messaging/client/client.dart';
import 'package:vartalap_messaging_flutter/db/chat_db.dart';
import 'package:vartalap_messaging_flutter/events/vartalap_task.dart';

class AssetUploadTask extends VartalapTask<String> {
  static const name = 'asset-upload';
  AssetUploadTask(
    VartalapChatClient client,
    ChatDatabase db, {
    String? payload,
  }) : super(client, db, name, payload: payload);

  @override
  Future<void> process() async {
    final asset = await (db.select(db.assets)
          ..whereSamePrimaryKey(AssetsCompanion(id: Value(payload))))
        .getSingle();
    final resp = await client.uploadAsset(asset);
    await (db.update(db.assets)..where((asset) => asset.id.equals(payload)))
        .write(AssetsCompanion(cid: Value(resp.assetId)));
  }

  @override
  void deserializePayload(String rawPayload) {
    payload = rawPayload;
  }

  @override
  String serializePayload() {
    return payload;
  }
}
