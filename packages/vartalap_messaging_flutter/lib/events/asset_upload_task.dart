import 'package:drift/drift.dart';
import 'package:vartalap_messaging/client/client.dart';
import 'package:vartalap_messaging_flutter/db/chat_db.dart';
import 'package:vartalap_messaging_flutter/events/vartalap_task.dart';

class AssetUploadTask extends VartalapTask<int> {
  static const name = 'asset-upload';
  AssetUploadTask(
    VartalapChatClient client,
    ChatDatabase db, {
    int? payload,
  }) : super(client, db, name, payload: payload);

  @override
  Future<void> process() async {
    final asset = await (db.select(db.assests)
          ..whereSamePrimaryKey(AssestsCompanion(id: Value(payload))))
        .getSingle();
    final resp = await uploadAsset(asset);
    await (db.update(db.assests)..where((asset) => asset.id.equals(payload)))
        .write(AssestsCompanion(assetId: Value(resp)));
  }

  Future<String> uploadAsset(AssestEntity asset) async {
    // Generate a upload url to the server
    final data = await client.getUploadUrl(asset.mimeType!, 'default');
    // Upload the asset to the server. via put request to the upload url

    // Mark the upload as done
    client.markAssetAsUploaded(data.assetId!);
    // Return the asset id
    return data.assetId!;
  }

  @override
  void deserializePayload(String rawPayload) {
    payload = int.parse(rawPayload);
  }

  @override
  String serializePayload() {
    return payload.toString();
  }
}
