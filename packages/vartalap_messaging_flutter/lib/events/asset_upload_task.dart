import 'dart:io';
import 'package:drift/drift.dart';
import 'package:taskq/taskq.dart';
import 'package:vartalap_messaging/vartalap_messaging.dart' as messaging;
import 'package:vartalap_messaging_flutter/db/chat_db.dart' hide Task;
import 'package:vartalap_messaging_flutter/events/vartalap_task.dart';

class AssetUploadTask extends VartalapTask<int> {
  static const name = 'asset-upload';
  AssetUploadTask(
    messaging.VartalapChatClient client,
    ChatDatabase db, {
    int? payload,
    int? id,
    TaskStatus state = TaskStatus.pending,
  }) : super(
          client,
          db,
          name,
          payload: payload,
          id: id,
          state: state,
        );

  @override
  Future<void> process() async {
    final currentPayload = payload;

    final asset = await (db.select(db.assests)
          ..where((tbl) => tbl.id.equals(currentPayload)))
        .getSingle();

    final remoteAssetId = await uploadAsset(asset);

    await (db.update(db.assests)..where((tbl) => tbl.id.equals(currentPayload)))
        .write(AssestsCompanion(assetId: Value(remoteAssetId)));
  }

  Future<String> uploadAsset(AssestEntity asset) async {
    final path = asset.path;
    if (path == null) {
      throw Exception('Asset path is null, cannot upload');
    }

    final file = File(path);
    if (!await file.exists()) {
      throw Exception('Asset file does not exist at path: $path');
    }

    // 1. Generate a upload url from the server
    final extension = path.split('.').last;
    final category = asset.type ?? 'default';
    final data = await client.getUploadUrl(extension, category);

    if (data.assetId == null) {
      throw Exception('Server failed to provide an assetId');
    }

    // 2. Upload the physical file to the server
    await client.uploadAsset(data.url, file);

    // 3. Mark the upload as done
    await client.markAssetAsUploaded(data.assetId!);

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
