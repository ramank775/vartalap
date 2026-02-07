// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_db.dart';

// ignore_for_file: type=lint
class $AssestsTable extends Assests
    with TableInfo<$AssestsTable, AssestEntity> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AssestsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
      'path', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
      'url', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _assetIdMeta =
      const VerificationMeta('assetId');
  @override
  late final GeneratedColumn<String> assetId = GeneratedColumn<String>(
      'asset_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _mimeTypeMeta =
      const VerificationMeta('mimeType');
  @override
  late final GeneratedColumn<String> mimeType = GeneratedColumn<String>(
      'mime_type', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _deletedAtMeta =
      const VerificationMeta('deletedAt');
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
      'deleted_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns =>
      [id, type, path, url, assetId, mimeType, createdAt, updatedAt, deletedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'assests';
  @override
  VerificationContext validateIntegrity(Insertable<AssestEntity> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    }
    if (data.containsKey('path')) {
      context.handle(
          _pathMeta, path.isAcceptableOrUnknown(data['path']!, _pathMeta));
    }
    if (data.containsKey('url')) {
      context.handle(
          _urlMeta, url.isAcceptableOrUnknown(data['url']!, _urlMeta));
    }
    if (data.containsKey('asset_id')) {
      context.handle(_assetIdMeta,
          assetId.isAcceptableOrUnknown(data['asset_id']!, _assetIdMeta));
    }
    if (data.containsKey('mime_type')) {
      context.handle(_mimeTypeMeta,
          mimeType.isAcceptableOrUnknown(data['mime_type']!, _mimeTypeMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    if (data.containsKey('deleted_at')) {
      context.handle(_deletedAtMeta,
          deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AssestEntity map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AssestEntity(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type']),
      path: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}path']),
      url: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}url']),
      assetId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}asset_id']),
      mimeType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}mime_type']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
      deletedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}deleted_at']),
    );
  }

  @override
  $AssestsTable createAlias(String alias) {
    return $AssestsTable(attachedDatabase, alias);
  }
}

class AssestEntity extends DataClass implements Insertable<AssestEntity> {
  final int id;
  final String? type;
  final String? path;
  final String? url;
  final String? assetId;
  final String? mimeType;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const AssestEntity(
      {required this.id,
      this.type,
      this.path,
      this.url,
      this.assetId,
      this.mimeType,
      required this.createdAt,
      required this.updatedAt,
      this.deletedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || type != null) {
      map['type'] = Variable<String>(type);
    }
    if (!nullToAbsent || path != null) {
      map['path'] = Variable<String>(path);
    }
    if (!nullToAbsent || url != null) {
      map['url'] = Variable<String>(url);
    }
    if (!nullToAbsent || assetId != null) {
      map['asset_id'] = Variable<String>(assetId);
    }
    if (!nullToAbsent || mimeType != null) {
      map['mime_type'] = Variable<String>(mimeType);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  AssestsCompanion toCompanion(bool nullToAbsent) {
    return AssestsCompanion(
      id: Value(id),
      type: type == null && nullToAbsent ? const Value.absent() : Value(type),
      path: path == null && nullToAbsent ? const Value.absent() : Value(path),
      url: url == null && nullToAbsent ? const Value.absent() : Value(url),
      assetId: assetId == null && nullToAbsent
          ? const Value.absent()
          : Value(assetId),
      mimeType: mimeType == null && nullToAbsent
          ? const Value.absent()
          : Value(mimeType),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory AssestEntity.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AssestEntity(
      id: serializer.fromJson<int>(json['id']),
      type: serializer.fromJson<String?>(json['type']),
      path: serializer.fromJson<String?>(json['path']),
      url: serializer.fromJson<String?>(json['url']),
      assetId: serializer.fromJson<String?>(json['assetId']),
      mimeType: serializer.fromJson<String?>(json['mimeType']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'type': serializer.toJson<String?>(type),
      'path': serializer.toJson<String?>(path),
      'url': serializer.toJson<String?>(url),
      'assetId': serializer.toJson<String?>(assetId),
      'mimeType': serializer.toJson<String?>(mimeType),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  AssestEntity copyWith(
          {int? id,
          Value<String?> type = const Value.absent(),
          Value<String?> path = const Value.absent(),
          Value<String?> url = const Value.absent(),
          Value<String?> assetId = const Value.absent(),
          Value<String?> mimeType = const Value.absent(),
          DateTime? createdAt,
          DateTime? updatedAt,
          Value<DateTime?> deletedAt = const Value.absent()}) =>
      AssestEntity(
        id: id ?? this.id,
        type: type.present ? type.value : this.type,
        path: path.present ? path.value : this.path,
        url: url.present ? url.value : this.url,
        assetId: assetId.present ? assetId.value : this.assetId,
        mimeType: mimeType.present ? mimeType.value : this.mimeType,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
      );
  AssestEntity copyWithCompanion(AssestsCompanion data) {
    return AssestEntity(
      id: data.id.present ? data.id.value : this.id,
      type: data.type.present ? data.type.value : this.type,
      path: data.path.present ? data.path.value : this.path,
      url: data.url.present ? data.url.value : this.url,
      assetId: data.assetId.present ? data.assetId.value : this.assetId,
      mimeType: data.mimeType.present ? data.mimeType.value : this.mimeType,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AssestEntity(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('path: $path, ')
          ..write('url: $url, ')
          ..write('assetId: $assetId, ')
          ..write('mimeType: $mimeType, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, type, path, url, assetId, mimeType, createdAt, updatedAt, deletedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AssestEntity &&
          other.id == this.id &&
          other.type == this.type &&
          other.path == this.path &&
          other.url == this.url &&
          other.assetId == this.assetId &&
          other.mimeType == this.mimeType &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class AssestsCompanion extends UpdateCompanion<AssestEntity> {
  final Value<int> id;
  final Value<String?> type;
  final Value<String?> path;
  final Value<String?> url;
  final Value<String?> assetId;
  final Value<String?> mimeType;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  const AssestsCompanion({
    this.id = const Value.absent(),
    this.type = const Value.absent(),
    this.path = const Value.absent(),
    this.url = const Value.absent(),
    this.assetId = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
  });
  AssestsCompanion.insert({
    this.id = const Value.absent(),
    this.type = const Value.absent(),
    this.path = const Value.absent(),
    this.url = const Value.absent(),
    this.assetId = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
  });
  static Insertable<AssestEntity> custom({
    Expression<int>? id,
    Expression<String>? type,
    Expression<String>? path,
    Expression<String>? url,
    Expression<String>? assetId,
    Expression<String>? mimeType,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (type != null) 'type': type,
      if (path != null) 'path': path,
      if (url != null) 'url': url,
      if (assetId != null) 'asset_id': assetId,
      if (mimeType != null) 'mime_type': mimeType,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
    });
  }

  AssestsCompanion copyWith(
      {Value<int>? id,
      Value<String?>? type,
      Value<String?>? path,
      Value<String?>? url,
      Value<String?>? assetId,
      Value<String?>? mimeType,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<DateTime?>? deletedAt}) {
    return AssestsCompanion(
      id: id ?? this.id,
      type: type ?? this.type,
      path: path ?? this.path,
      url: url ?? this.url,
      assetId: assetId ?? this.assetId,
      mimeType: mimeType ?? this.mimeType,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (assetId.present) {
      map['asset_id'] = Variable<String>(assetId.value);
    }
    if (mimeType.present) {
      map['mime_type'] = Variable<String>(mimeType.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AssestsCompanion(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('path: $path, ')
          ..write('url: $url, ')
          ..write('assetId: $assetId, ')
          ..write('mimeType: $mimeType, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }
}

class $ChannelsTable extends Channels
    with TableInfo<$ChannelsTable, ChannelModel> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChannelsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  @override
  late final GeneratedColumnWithTypeConverter<ChannelType, String> type =
      GeneratedColumn<String>('type', aliasedName, false,
              type: DriftSqlType.string, requiredDuringInsert: true)
          .withConverter<ChannelType>($ChannelsTable.$convertertype);
  static const VerificationMeta _cidMeta = const VerificationMeta('cid');
  @override
  late final GeneratedColumn<String> cid = GeneratedColumn<String>(
      'cid', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _taskIdMeta = const VerificationMeta('taskId');
  @override
  late final GeneratedColumn<int> taskId = GeneratedColumn<int>(
      'task_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  @override
  late final GeneratedColumnWithTypeConverter<Map<String, dynamic>?, String>
      extraData = GeneratedColumn<String>('extra_data', aliasedName, true,
              type: DriftSqlType.string, requiredDuringInsert: false)
          .withConverter<Map<String, dynamic>?>(
              $ChannelsTable.$converterextraData);
  @override
  late final GeneratedColumnWithTypeConverter<Map<String, dynamic>, String>
      config = GeneratedColumn<String>('config', aliasedName, false,
              type: DriftSqlType.string,
              requiredDuringInsert: false,
              defaultValue: const Constant('{}'))
          .withConverter<Map<String, dynamic>>($ChannelsTable.$converterconfig);
  static const VerificationMeta _mutedMeta = const VerificationMeta('muted');
  @override
  late final GeneratedColumn<bool> muted = GeneratedColumn<bool>(
      'muted', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("muted" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _deletedAtMeta =
      const VerificationMeta('deletedAt');
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
      'deleted_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        type,
        cid,
        taskId,
        extraData,
        config,
        muted,
        createdAt,
        updatedAt,
        deletedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'channels';
  @override
  VerificationContext validateIntegrity(Insertable<ChannelModel> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('cid')) {
      context.handle(
          _cidMeta, cid.isAcceptableOrUnknown(data['cid']!, _cidMeta));
    }
    if (data.containsKey('task_id')) {
      context.handle(_taskIdMeta,
          taskId.isAcceptableOrUnknown(data['task_id']!, _taskIdMeta));
    }
    if (data.containsKey('muted')) {
      context.handle(
          _mutedMeta, muted.isAcceptableOrUnknown(data['muted']!, _mutedMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    if (data.containsKey('deleted_at')) {
      context.handle(_deletedAtMeta,
          deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ChannelModel map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChannelModel(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      type: $ChannelsTable.$convertertype.fromSql(attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!),
      cid: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}cid']),
      taskId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}task_id']),
      extraData: $ChannelsTable.$converterextraData.fromSql(attachedDatabase
          .typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}extra_data'])),
      config: $ChannelsTable.$converterconfig.fromSql(attachedDatabase
          .typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}config'])!),
      muted: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}muted'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
      deletedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}deleted_at']),
    );
  }

  @override
  $ChannelsTable createAlias(String alias) {
    return $ChannelsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<ChannelType, String, String> $convertertype =
      const EnumNameConverter<ChannelType>(ChannelType.values);
  static TypeConverter<Map<String, dynamic>?, String?> $converterextraData =
      NullableMapConverter();
  static TypeConverter<Map<String, dynamic>, String> $converterconfig =
      MapConverter();
}

class ChannelsCompanion extends UpdateCompanion<ChannelModel> {
  final Value<int> id;
  final Value<ChannelType> type;
  final Value<String?> cid;
  final Value<int?> taskId;
  final Value<Map<String, dynamic>?> extraData;
  final Value<Map<String, dynamic>> config;
  final Value<bool> muted;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  const ChannelsCompanion({
    this.id = const Value.absent(),
    this.type = const Value.absent(),
    this.cid = const Value.absent(),
    this.taskId = const Value.absent(),
    this.extraData = const Value.absent(),
    this.config = const Value.absent(),
    this.muted = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
  });
  ChannelsCompanion.insert({
    this.id = const Value.absent(),
    required ChannelType type,
    this.cid = const Value.absent(),
    this.taskId = const Value.absent(),
    this.extraData = const Value.absent(),
    this.config = const Value.absent(),
    this.muted = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
  }) : type = Value(type);
  static Insertable<ChannelModel> custom({
    Expression<int>? id,
    Expression<String>? type,
    Expression<String>? cid,
    Expression<int>? taskId,
    Expression<String>? extraData,
    Expression<String>? config,
    Expression<bool>? muted,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (type != null) 'type': type,
      if (cid != null) 'cid': cid,
      if (taskId != null) 'task_id': taskId,
      if (extraData != null) 'extra_data': extraData,
      if (config != null) 'config': config,
      if (muted != null) 'muted': muted,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
    });
  }

  ChannelsCompanion copyWith(
      {Value<int>? id,
      Value<ChannelType>? type,
      Value<String?>? cid,
      Value<int?>? taskId,
      Value<Map<String, dynamic>?>? extraData,
      Value<Map<String, dynamic>>? config,
      Value<bool>? muted,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<DateTime?>? deletedAt}) {
    return ChannelsCompanion(
      id: id ?? this.id,
      type: type ?? this.type,
      cid: cid ?? this.cid,
      taskId: taskId ?? this.taskId,
      extraData: extraData ?? this.extraData,
      config: config ?? this.config,
      muted: muted ?? this.muted,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (type.present) {
      map['type'] =
          Variable<String>($ChannelsTable.$convertertype.toSql(type.value));
    }
    if (cid.present) {
      map['cid'] = Variable<String>(cid.value);
    }
    if (taskId.present) {
      map['task_id'] = Variable<int>(taskId.value);
    }
    if (extraData.present) {
      map['extra_data'] = Variable<String>(
          $ChannelsTable.$converterextraData.toSql(extraData.value));
    }
    if (config.present) {
      map['config'] =
          Variable<String>($ChannelsTable.$converterconfig.toSql(config.value));
    }
    if (muted.present) {
      map['muted'] = Variable<bool>(muted.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChannelsCompanion(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('cid: $cid, ')
          ..write('taskId: $taskId, ')
          ..write('extraData: $extraData, ')
          ..write('config: $config, ')
          ..write('muted: $muted, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }
}

class $ContactsTable extends Contacts with TableInfo<$ContactsTable, Contact> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ContactsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _usernameMeta =
      const VerificationMeta('username');
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
      'username', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _uidMeta = const VerificationMeta('uid');
  @override
  late final GeneratedColumn<String> uid = GeneratedColumn<String>(
      'uid', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _phoneMeta = const VerificationMeta('phone');
  @override
  late final GeneratedColumn<String> phone = GeneratedColumn<String>(
      'phone', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _thumbnailMeta =
      const VerificationMeta('thumbnail');
  @override
  late final GeneratedColumn<Uint8List> thumbnail = GeneratedColumn<Uint8List>(
      'thumbnail', aliasedName, true,
      type: DriftSqlType.blob, requiredDuringInsert: false);
  static const VerificationMeta _photoMeta = const VerificationMeta('photo');
  @override
  late final GeneratedColumn<String> photo = GeneratedColumn<String>(
      'photo', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  late final GeneratedColumnWithTypeConverter<Map<String, dynamic>?, String>
      extraData = GeneratedColumn<String>('extra_data', aliasedName, true,
              type: DriftSqlType.string, requiredDuringInsert: false)
          .withConverter<Map<String, dynamic>?>(
              $ContactsTable.$converterextraData);
  @override
  late final GeneratedColumnWithTypeConverter<ContactStatus, String> status =
      GeneratedColumn<String>('status', aliasedName, false,
              type: DriftSqlType.string, requiredDuringInsert: true)
          .withConverter<ContactStatus>($ContactsTable.$converterstatus);
  @override
  List<GeneratedColumn> get $columns =>
      [id, username, uid, phone, name, thumbnail, photo, extraData, status];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'contacts';
  @override
  VerificationContext validateIntegrity(Insertable<Contact> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('username')) {
      context.handle(_usernameMeta,
          username.isAcceptableOrUnknown(data['username']!, _usernameMeta));
    }
    if (data.containsKey('uid')) {
      context.handle(
          _uidMeta, uid.isAcceptableOrUnknown(data['uid']!, _uidMeta));
    }
    if (data.containsKey('phone')) {
      context.handle(
          _phoneMeta, phone.isAcceptableOrUnknown(data['phone']!, _phoneMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    }
    if (data.containsKey('thumbnail')) {
      context.handle(_thumbnailMeta,
          thumbnail.isAcceptableOrUnknown(data['thumbnail']!, _thumbnailMeta));
    }
    if (data.containsKey('photo')) {
      context.handle(
          _photoMeta, photo.isAcceptableOrUnknown(data['photo']!, _photoMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Contact map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Contact.fromDb(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      username: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}username']),
      uid: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}uid']),
      phone: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}phone']),
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name']),
      thumbnail: attachedDatabase.typeMapping
          .read(DriftSqlType.blob, data['${effectivePrefix}thumbnail']),
      photo: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}photo']),
      extraData: $ContactsTable.$converterextraData.fromSql(attachedDatabase
          .typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}extra_data'])),
      status: $ContactsTable.$converterstatus.fromSql(attachedDatabase
          .typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!),
    );
  }

  @override
  $ContactsTable createAlias(String alias) {
    return $ContactsTable(attachedDatabase, alias);
  }

  static TypeConverter<Map<String, dynamic>?, String?> $converterextraData =
      NullableMapConverter();
  static JsonTypeConverter2<ContactStatus, String, String> $converterstatus =
      const EnumNameConverter<ContactStatus>(ContactStatus.values);
}

class ContactsCompanion extends UpdateCompanion<Contact> {
  final Value<int> id;
  final Value<String?> username;
  final Value<String?> uid;
  final Value<String?> phone;
  final Value<String?> name;
  final Value<Uint8List?> thumbnail;
  final Value<String?> photo;
  final Value<Map<String, dynamic>?> extraData;
  final Value<ContactStatus> status;
  const ContactsCompanion({
    this.id = const Value.absent(),
    this.username = const Value.absent(),
    this.uid = const Value.absent(),
    this.phone = const Value.absent(),
    this.name = const Value.absent(),
    this.thumbnail = const Value.absent(),
    this.photo = const Value.absent(),
    this.extraData = const Value.absent(),
    this.status = const Value.absent(),
  });
  ContactsCompanion.insert({
    this.id = const Value.absent(),
    this.username = const Value.absent(),
    this.uid = const Value.absent(),
    this.phone = const Value.absent(),
    this.name = const Value.absent(),
    this.thumbnail = const Value.absent(),
    this.photo = const Value.absent(),
    this.extraData = const Value.absent(),
    required ContactStatus status,
  }) : status = Value(status);
  static Insertable<Contact> custom({
    Expression<int>? id,
    Expression<String>? username,
    Expression<String>? uid,
    Expression<String>? phone,
    Expression<String>? name,
    Expression<Uint8List>? thumbnail,
    Expression<String>? photo,
    Expression<String>? extraData,
    Expression<String>? status,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (username != null) 'username': username,
      if (uid != null) 'uid': uid,
      if (phone != null) 'phone': phone,
      if (name != null) 'name': name,
      if (thumbnail != null) 'thumbnail': thumbnail,
      if (photo != null) 'photo': photo,
      if (extraData != null) 'extra_data': extraData,
      if (status != null) 'status': status,
    });
  }

  ContactsCompanion copyWith(
      {Value<int>? id,
      Value<String?>? username,
      Value<String?>? uid,
      Value<String?>? phone,
      Value<String?>? name,
      Value<Uint8List?>? thumbnail,
      Value<String?>? photo,
      Value<Map<String, dynamic>?>? extraData,
      Value<ContactStatus>? status}) {
    return ContactsCompanion(
      id: id ?? this.id,
      username: username ?? this.username,
      uid: uid ?? this.uid,
      phone: phone ?? this.phone,
      name: name ?? this.name,
      thumbnail: thumbnail ?? this.thumbnail,
      photo: photo ?? this.photo,
      extraData: extraData ?? this.extraData,
      status: status ?? this.status,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (uid.present) {
      map['uid'] = Variable<String>(uid.value);
    }
    if (phone.present) {
      map['phone'] = Variable<String>(phone.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (thumbnail.present) {
      map['thumbnail'] = Variable<Uint8List>(thumbnail.value);
    }
    if (photo.present) {
      map['photo'] = Variable<String>(photo.value);
    }
    if (extraData.present) {
      map['extra_data'] = Variable<String>(
          $ContactsTable.$converterextraData.toSql(extraData.value));
    }
    if (status.present) {
      map['status'] =
          Variable<String>($ContactsTable.$converterstatus.toSql(status.value));
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ContactsCompanion(')
          ..write('id: $id, ')
          ..write('username: $username, ')
          ..write('uid: $uid, ')
          ..write('phone: $phone, ')
          ..write('name: $name, ')
          ..write('thumbnail: $thumbnail, ')
          ..write('photo: $photo, ')
          ..write('extraData: $extraData, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }
}

class $MembersTable extends Members
    with TableInfo<$MembersTable, MemberEntity> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MembersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _memberIdMeta =
      const VerificationMeta('memberId');
  @override
  late final GeneratedColumn<int> memberId = GeneratedColumn<int>(
      'member_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES contacts (id) ON UPDATE CASCADE'));
  static const VerificationMeta _channelIdMeta =
      const VerificationMeta('channelId');
  @override
  late final GeneratedColumn<int> channelId = GeneratedColumn<int>(
      'channel_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES channels (id) ON DELETE CASCADE'));
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
      'role', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _sinceMeta = const VerificationMeta('since');
  @override
  late final GeneratedColumn<DateTime> since = GeneratedColumn<DateTime>(
      'since', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _deletedAtMeta =
      const VerificationMeta('deletedAt');
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
      'deleted_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns =>
      [memberId, channelId, role, since, updatedAt, deletedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'members';
  @override
  VerificationContext validateIntegrity(Insertable<MemberEntity> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('member_id')) {
      context.handle(_memberIdMeta,
          memberId.isAcceptableOrUnknown(data['member_id']!, _memberIdMeta));
    } else if (isInserting) {
      context.missing(_memberIdMeta);
    }
    if (data.containsKey('channel_id')) {
      context.handle(_channelIdMeta,
          channelId.isAcceptableOrUnknown(data['channel_id']!, _channelIdMeta));
    } else if (isInserting) {
      context.missing(_channelIdMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
          _roleMeta, role.isAcceptableOrUnknown(data['role']!, _roleMeta));
    }
    if (data.containsKey('since')) {
      context.handle(
          _sinceMeta, since.isAcceptableOrUnknown(data['since']!, _sinceMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    if (data.containsKey('deleted_at')) {
      context.handle(_deletedAtMeta,
          deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {channelId, memberId};
  @override
  MemberEntity map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MemberEntity(
      memberId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}member_id'])!,
      channelId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}channel_id'])!,
      role: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}role']),
      since: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}since'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
      deletedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}deleted_at']),
    );
  }

  @override
  $MembersTable createAlias(String alias) {
    return $MembersTable(attachedDatabase, alias);
  }
}

class MemberEntity extends DataClass implements Insertable<MemberEntity> {
  final int memberId;
  final int channelId;
  final String? role;
  final DateTime since;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const MemberEntity(
      {required this.memberId,
      required this.channelId,
      this.role,
      required this.since,
      required this.updatedAt,
      this.deletedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['member_id'] = Variable<int>(memberId);
    map['channel_id'] = Variable<int>(channelId);
    if (!nullToAbsent || role != null) {
      map['role'] = Variable<String>(role);
    }
    map['since'] = Variable<DateTime>(since);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  MembersCompanion toCompanion(bool nullToAbsent) {
    return MembersCompanion(
      memberId: Value(memberId),
      channelId: Value(channelId),
      role: role == null && nullToAbsent ? const Value.absent() : Value(role),
      since: Value(since),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory MemberEntity.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MemberEntity(
      memberId: serializer.fromJson<int>(json['memberId']),
      channelId: serializer.fromJson<int>(json['channelId']),
      role: serializer.fromJson<String?>(json['role']),
      since: serializer.fromJson<DateTime>(json['since']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'memberId': serializer.toJson<int>(memberId),
      'channelId': serializer.toJson<int>(channelId),
      'role': serializer.toJson<String?>(role),
      'since': serializer.toJson<DateTime>(since),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  MemberEntity copyWith(
          {int? memberId,
          int? channelId,
          Value<String?> role = const Value.absent(),
          DateTime? since,
          DateTime? updatedAt,
          Value<DateTime?> deletedAt = const Value.absent()}) =>
      MemberEntity(
        memberId: memberId ?? this.memberId,
        channelId: channelId ?? this.channelId,
        role: role.present ? role.value : this.role,
        since: since ?? this.since,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
      );
  MemberEntity copyWithCompanion(MembersCompanion data) {
    return MemberEntity(
      memberId: data.memberId.present ? data.memberId.value : this.memberId,
      channelId: data.channelId.present ? data.channelId.value : this.channelId,
      role: data.role.present ? data.role.value : this.role,
      since: data.since.present ? data.since.value : this.since,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MemberEntity(')
          ..write('memberId: $memberId, ')
          ..write('channelId: $channelId, ')
          ..write('role: $role, ')
          ..write('since: $since, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(memberId, channelId, role, since, updatedAt, deletedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MemberEntity &&
          other.memberId == this.memberId &&
          other.channelId == this.channelId &&
          other.role == this.role &&
          other.since == this.since &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class MembersCompanion extends UpdateCompanion<MemberEntity> {
  final Value<int> memberId;
  final Value<int> channelId;
  final Value<String?> role;
  final Value<DateTime> since;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const MembersCompanion({
    this.memberId = const Value.absent(),
    this.channelId = const Value.absent(),
    this.role = const Value.absent(),
    this.since = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MembersCompanion.insert({
    required int memberId,
    required int channelId,
    this.role = const Value.absent(),
    this.since = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : memberId = Value(memberId),
        channelId = Value(channelId);
  static Insertable<MemberEntity> custom({
    Expression<int>? memberId,
    Expression<int>? channelId,
    Expression<String>? role,
    Expression<DateTime>? since,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (memberId != null) 'member_id': memberId,
      if (channelId != null) 'channel_id': channelId,
      if (role != null) 'role': role,
      if (since != null) 'since': since,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MembersCompanion copyWith(
      {Value<int>? memberId,
      Value<int>? channelId,
      Value<String?>? role,
      Value<DateTime>? since,
      Value<DateTime>? updatedAt,
      Value<DateTime?>? deletedAt,
      Value<int>? rowid}) {
    return MembersCompanion(
      memberId: memberId ?? this.memberId,
      channelId: channelId ?? this.channelId,
      role: role ?? this.role,
      since: since ?? this.since,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (memberId.present) {
      map['member_id'] = Variable<int>(memberId.value);
    }
    if (channelId.present) {
      map['channel_id'] = Variable<int>(channelId.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (since.present) {
      map['since'] = Variable<DateTime>(since.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MembersCompanion(')
          ..write('memberId: $memberId, ')
          ..write('channelId: $channelId, ')
          ..write('role: $role, ')
          ..write('since: $since, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MessagesTable extends Messages
    with TableInfo<$MessagesTable, ChatMessage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _ridMeta = const VerificationMeta('rid');
  @override
  late final GeneratedColumn<String> rid = GeneratedColumn<String>(
      'rid', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  late final GeneratedColumnWithTypeConverter<MessageType, String> type =
      GeneratedColumn<String>('type', aliasedName, false,
              type: DriftSqlType.string, requiredDuringInsert: true)
          .withConverter<MessageType>($MessagesTable.$convertertype);
  @override
  late final GeneratedColumnWithTypeConverter<MessageState, String> state =
      GeneratedColumn<String>('state', aliasedName, false,
              type: DriftSqlType.string, requiredDuringInsert: true)
          .withConverter<MessageState>($MessagesTable.$converterstate);
  @override
  late final GeneratedColumnWithTypeConverter<Map<String, dynamic>, String>
      payload = GeneratedColumn<String>('payload', aliasedName, false,
              type: DriftSqlType.string, requiredDuringInsert: true)
          .withConverter<Map<String, dynamic>>(
              $MessagesTable.$converterpayload);
  static const VerificationMeta _channelIdMeta =
      const VerificationMeta('channelId');
  @override
  late final GeneratedColumn<int> channelId = GeneratedColumn<int>(
      'channel_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES channels (id) ON DELETE CASCADE'));
  static const VerificationMeta _senderIdMeta =
      const VerificationMeta('senderId');
  @override
  late final GeneratedColumn<int> senderId = GeneratedColumn<int>(
      'sender_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES contacts (id) ON DELETE CASCADE'));
  static const VerificationMeta _localCreatedAtMeta =
      const VerificationMeta('localCreatedAt');
  @override
  late final GeneratedColumn<DateTime> localCreatedAt =
      GeneratedColumn<DateTime>('local_created_at', aliasedName, false,
          type: DriftSqlType.dateTime,
          requiredDuringInsert: false,
          defaultValue: currentDateAndTime);
  static const VerificationMeta _remoteCreatedAtMeta =
      const VerificationMeta('remoteCreatedAt');
  @override
  late final GeneratedColumn<DateTime> remoteCreatedAt =
      GeneratedColumn<DateTime>('remote_created_at', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        rid,
        type,
        state,
        payload,
        channelId,
        senderId,
        localCreatedAt,
        remoteCreatedAt,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'messages';
  @override
  VerificationContext validateIntegrity(Insertable<ChatMessage> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('rid')) {
      context.handle(
          _ridMeta, rid.isAcceptableOrUnknown(data['rid']!, _ridMeta));
    }
    if (data.containsKey('channel_id')) {
      context.handle(_channelIdMeta,
          channelId.isAcceptableOrUnknown(data['channel_id']!, _channelIdMeta));
    } else if (isInserting) {
      context.missing(_channelIdMeta);
    }
    if (data.containsKey('sender_id')) {
      context.handle(_senderIdMeta,
          senderId.isAcceptableOrUnknown(data['sender_id']!, _senderIdMeta));
    } else if (isInserting) {
      context.missing(_senderIdMeta);
    }
    if (data.containsKey('local_created_at')) {
      context.handle(
          _localCreatedAtMeta,
          localCreatedAt.isAcceptableOrUnknown(
              data['local_created_at']!, _localCreatedAtMeta));
    }
    if (data.containsKey('remote_created_at')) {
      context.handle(
          _remoteCreatedAtMeta,
          remoteCreatedAt.isAcceptableOrUnknown(
              data['remote_created_at']!, _remoteCreatedAtMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ChatMessage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChatMessage(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      rid: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}rid']),
      type: $MessagesTable.$convertertype.fromSql(attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!),
      state: $MessagesTable.$converterstate.fromSql(attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}state'])!),
      payload: $MessagesTable.$converterpayload.fromSql(attachedDatabase
          .typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payload'])!),
      channelId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}channel_id'])!,
      senderId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sender_id'])!,
      localCreatedAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}local_created_at'])!,
      remoteCreatedAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}remote_created_at']),
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $MessagesTable createAlias(String alias) {
    return $MessagesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<MessageType, String, String> $convertertype =
      const EnumNameConverter<MessageType>(MessageType.values);
  static JsonTypeConverter2<MessageState, String, String> $converterstate =
      const EnumNameConverter<MessageState>(MessageState.values);
  static TypeConverter<Map<String, dynamic>, String> $converterpayload =
      MapConverter();
}

class MessagesCompanion extends UpdateCompanion<ChatMessage> {
  final Value<int> id;
  final Value<String?> rid;
  final Value<MessageType> type;
  final Value<MessageState> state;
  final Value<Map<String, dynamic>> payload;
  final Value<int> channelId;
  final Value<int> senderId;
  final Value<DateTime> localCreatedAt;
  final Value<DateTime?> remoteCreatedAt;
  final Value<DateTime> updatedAt;
  const MessagesCompanion({
    this.id = const Value.absent(),
    this.rid = const Value.absent(),
    this.type = const Value.absent(),
    this.state = const Value.absent(),
    this.payload = const Value.absent(),
    this.channelId = const Value.absent(),
    this.senderId = const Value.absent(),
    this.localCreatedAt = const Value.absent(),
    this.remoteCreatedAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  MessagesCompanion.insert({
    this.id = const Value.absent(),
    this.rid = const Value.absent(),
    required MessageType type,
    required MessageState state,
    required Map<String, dynamic> payload,
    required int channelId,
    required int senderId,
    this.localCreatedAt = const Value.absent(),
    this.remoteCreatedAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  })  : type = Value(type),
        state = Value(state),
        payload = Value(payload),
        channelId = Value(channelId),
        senderId = Value(senderId);
  static Insertable<ChatMessage> custom({
    Expression<int>? id,
    Expression<String>? rid,
    Expression<String>? type,
    Expression<String>? state,
    Expression<String>? payload,
    Expression<int>? channelId,
    Expression<int>? senderId,
    Expression<DateTime>? localCreatedAt,
    Expression<DateTime>? remoteCreatedAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (rid != null) 'rid': rid,
      if (type != null) 'type': type,
      if (state != null) 'state': state,
      if (payload != null) 'payload': payload,
      if (channelId != null) 'channel_id': channelId,
      if (senderId != null) 'sender_id': senderId,
      if (localCreatedAt != null) 'local_created_at': localCreatedAt,
      if (remoteCreatedAt != null) 'remote_created_at': remoteCreatedAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  MessagesCompanion copyWith(
      {Value<int>? id,
      Value<String?>? rid,
      Value<MessageType>? type,
      Value<MessageState>? state,
      Value<Map<String, dynamic>>? payload,
      Value<int>? channelId,
      Value<int>? senderId,
      Value<DateTime>? localCreatedAt,
      Value<DateTime?>? remoteCreatedAt,
      Value<DateTime>? updatedAt}) {
    return MessagesCompanion(
      id: id ?? this.id,
      rid: rid ?? this.rid,
      type: type ?? this.type,
      state: state ?? this.state,
      payload: payload ?? this.payload,
      channelId: channelId ?? this.channelId,
      senderId: senderId ?? this.senderId,
      localCreatedAt: localCreatedAt ?? this.localCreatedAt,
      remoteCreatedAt: remoteCreatedAt ?? this.remoteCreatedAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (rid.present) {
      map['rid'] = Variable<String>(rid.value);
    }
    if (type.present) {
      map['type'] =
          Variable<String>($MessagesTable.$convertertype.toSql(type.value));
    }
    if (state.present) {
      map['state'] =
          Variable<String>($MessagesTable.$converterstate.toSql(state.value));
    }
    if (payload.present) {
      map['payload'] = Variable<String>(
          $MessagesTable.$converterpayload.toSql(payload.value));
    }
    if (channelId.present) {
      map['channel_id'] = Variable<int>(channelId.value);
    }
    if (senderId.present) {
      map['sender_id'] = Variable<int>(senderId.value);
    }
    if (localCreatedAt.present) {
      map['local_created_at'] = Variable<DateTime>(localCreatedAt.value);
    }
    if (remoteCreatedAt.present) {
      map['remote_created_at'] = Variable<DateTime>(remoteCreatedAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessagesCompanion(')
          ..write('id: $id, ')
          ..write('rid: $rid, ')
          ..write('type: $type, ')
          ..write('state: $state, ')
          ..write('payload: $payload, ')
          ..write('channelId: $channelId, ')
          ..write('senderId: $senderId, ')
          ..write('localCreatedAt: $localCreatedAt, ')
          ..write('remoteCreatedAt: $remoteCreatedAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $MessageAssetsTable extends MessageAssets
    with TableInfo<$MessageAssetsTable, MessageAsset> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessageAssetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _messageIdMeta =
      const VerificationMeta('messageId');
  @override
  late final GeneratedColumn<int> messageId = GeneratedColumn<int>(
      'message_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES messages (id) ON DELETE CASCADE'));
  static const VerificationMeta _assetIdMeta =
      const VerificationMeta('assetId');
  @override
  late final GeneratedColumn<int> assetId = GeneratedColumn<int>(
      'asset_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES assests (id) ON DELETE CASCADE'));
  @override
  List<GeneratedColumn> get $columns => [messageId, assetId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'message_assets';
  @override
  VerificationContext validateIntegrity(Insertable<MessageAsset> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('message_id')) {
      context.handle(_messageIdMeta,
          messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta));
    } else if (isInserting) {
      context.missing(_messageIdMeta);
    }
    if (data.containsKey('asset_id')) {
      context.handle(_assetIdMeta,
          assetId.isAcceptableOrUnknown(data['asset_id']!, _assetIdMeta));
    } else if (isInserting) {
      context.missing(_assetIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {messageId, assetId};
  @override
  MessageAsset map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MessageAsset(
      messageId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}message_id'])!,
      assetId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}asset_id'])!,
    );
  }

  @override
  $MessageAssetsTable createAlias(String alias) {
    return $MessageAssetsTable(attachedDatabase, alias);
  }
}

class MessageAsset extends DataClass implements Insertable<MessageAsset> {
  final int messageId;
  final int assetId;
  const MessageAsset({required this.messageId, required this.assetId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['message_id'] = Variable<int>(messageId);
    map['asset_id'] = Variable<int>(assetId);
    return map;
  }

  MessageAssetsCompanion toCompanion(bool nullToAbsent) {
    return MessageAssetsCompanion(
      messageId: Value(messageId),
      assetId: Value(assetId),
    );
  }

  factory MessageAsset.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MessageAsset(
      messageId: serializer.fromJson<int>(json['messageId']),
      assetId: serializer.fromJson<int>(json['assetId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'messageId': serializer.toJson<int>(messageId),
      'assetId': serializer.toJson<int>(assetId),
    };
  }

  MessageAsset copyWith({int? messageId, int? assetId}) => MessageAsset(
        messageId: messageId ?? this.messageId,
        assetId: assetId ?? this.assetId,
      );
  MessageAsset copyWithCompanion(MessageAssetsCompanion data) {
    return MessageAsset(
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      assetId: data.assetId.present ? data.assetId.value : this.assetId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MessageAsset(')
          ..write('messageId: $messageId, ')
          ..write('assetId: $assetId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(messageId, assetId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MessageAsset &&
          other.messageId == this.messageId &&
          other.assetId == this.assetId);
}

class MessageAssetsCompanion extends UpdateCompanion<MessageAsset> {
  final Value<int> messageId;
  final Value<int> assetId;
  final Value<int> rowid;
  const MessageAssetsCompanion({
    this.messageId = const Value.absent(),
    this.assetId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MessageAssetsCompanion.insert({
    required int messageId,
    required int assetId,
    this.rowid = const Value.absent(),
  })  : messageId = Value(messageId),
        assetId = Value(assetId);
  static Insertable<MessageAsset> custom({
    Expression<int>? messageId,
    Expression<int>? assetId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (messageId != null) 'message_id': messageId,
      if (assetId != null) 'asset_id': assetId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MessageAssetsCompanion copyWith(
      {Value<int>? messageId, Value<int>? assetId, Value<int>? rowid}) {
    return MessageAssetsCompanion(
      messageId: messageId ?? this.messageId,
      assetId: assetId ?? this.assetId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (messageId.present) {
      map['message_id'] = Variable<int>(messageId.value);
    }
    if (assetId.present) {
      map['asset_id'] = Variable<int>(assetId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessageAssetsCompanion(')
          ..write('messageId: $messageId, ')
          ..write('assetId: $assetId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $UserProfilesTable extends UserProfiles
    with TableInfo<$UserProfilesTable, Profile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UserProfilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
      'user_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _emailMeta = const VerificationMeta('email');
  @override
  late final GeneratedColumn<String> email = GeneratedColumn<String>(
      'email', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _imageMeta = const VerificationMeta('image');
  @override
  late final GeneratedColumn<String> image = GeneratedColumn<String>(
      'image', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [userId, name, email, image, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'user_profiles';
  @override
  VerificationContext validateIntegrity(Insertable<Profile> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('user_id')) {
      context.handle(_userIdMeta,
          userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta));
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('email')) {
      context.handle(
          _emailMeta, email.isAcceptableOrUnknown(data['email']!, _emailMeta));
    } else if (isInserting) {
      context.missing(_emailMeta);
    }
    if (data.containsKey('image')) {
      context.handle(
          _imageMeta, image.isAcceptableOrUnknown(data['image']!, _imageMeta));
    } else if (isInserting) {
      context.missing(_imageMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {userId};
  @override
  Profile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Profile.fromDb(
      userId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}user_id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      email: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}email'])!,
      image: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}image'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $UserProfilesTable createAlias(String alias) {
    return $UserProfilesTable(attachedDatabase, alias);
  }
}

class UserProfilesCompanion extends UpdateCompanion<Profile> {
  final Value<String> userId;
  final Value<String> name;
  final Value<String> email;
  final Value<String> image;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const UserProfilesCompanion({
    this.userId = const Value.absent(),
    this.name = const Value.absent(),
    this.email = const Value.absent(),
    this.image = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UserProfilesCompanion.insert({
    required String userId,
    required String name,
    required String email,
    required String image,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : userId = Value(userId),
        name = Value(name),
        email = Value(email),
        image = Value(image),
        updatedAt = Value(updatedAt);
  static Insertable<Profile> custom({
    Expression<String>? userId,
    Expression<String>? name,
    Expression<String>? email,
    Expression<String>? image,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (name != null) 'name': name,
      if (email != null) 'email': email,
      if (image != null) 'image': image,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UserProfilesCompanion copyWith(
      {Value<String>? userId,
      Value<String>? name,
      Value<String>? email,
      Value<String>? image,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return UserProfilesCompanion(
      userId: userId ?? this.userId,
      name: name ?? this.name,
      email: email ?? this.email,
      image: image ?? this.image,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (email.present) {
      map['email'] = Variable<String>(email.value);
    }
    if (image.present) {
      map['image'] = Variable<String>(image.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UserProfilesCompanion(')
          ..write('userId: $userId, ')
          ..write('name: $name, ')
          ..write('email: $email, ')
          ..write('image: $image, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TasksTable extends Tasks with TableInfo<$TasksTable, Task> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TasksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      additionalChecks: GeneratedColumn.checkTextLength(maxTextLength: 50),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  static const VerificationMeta _payloadMeta =
      const VerificationMeta('payload');
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
      'payload', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  late final GeneratedColumnWithTypeConverter<Map<String, dynamic>, String>
      state = GeneratedColumn<String>('state', aliasedName, false,
              type: DriftSqlType.string, requiredDuringInsert: true)
          .withConverter<Map<String, dynamic>>($TasksTable.$converterstate);
  @override
  late final GeneratedColumnWithTypeConverter<TaskStatus, int> status =
      GeneratedColumn<int>('status', aliasedName, false,
              type: DriftSqlType.int, requiredDuringInsert: true)
          .withConverter<TaskStatus>($TasksTable.$converterstatus);
  @override
  List<GeneratedColumn> get $columns => [id, type, payload, state, status];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tasks';
  @override
  VerificationContext validateIntegrity(Insertable<Task> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(_payloadMeta,
          payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta));
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Task map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Task(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      payload: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payload'])!,
      state: $TasksTable.$converterstate.fromSql(attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}state'])!),
      status: $TasksTable.$converterstatus.fromSql(attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}status'])!),
    );
  }

  @override
  $TasksTable createAlias(String alias) {
    return $TasksTable(attachedDatabase, alias);
  }

  static TypeConverter<Map<String, dynamic>, String> $converterstate =
      MapConverter();
  static JsonTypeConverter2<TaskStatus, int, int> $converterstatus =
      const EnumIndexConverter<TaskStatus>(TaskStatus.values);
}

class Task extends DataClass implements Insertable<Task> {
  final int id;
  final String type;
  final String payload;
  final Map<String, dynamic> state;
  final TaskStatus status;
  const Task(
      {required this.id,
      required this.type,
      required this.payload,
      required this.state,
      required this.status});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['type'] = Variable<String>(type);
    map['payload'] = Variable<String>(payload);
    {
      map['state'] = Variable<String>($TasksTable.$converterstate.toSql(state));
    }
    {
      map['status'] = Variable<int>($TasksTable.$converterstatus.toSql(status));
    }
    return map;
  }

  TasksCompanion toCompanion(bool nullToAbsent) {
    return TasksCompanion(
      id: Value(id),
      type: Value(type),
      payload: Value(payload),
      state: Value(state),
      status: Value(status),
    );
  }

  factory Task.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Task(
      id: serializer.fromJson<int>(json['id']),
      type: serializer.fromJson<String>(json['type']),
      payload: serializer.fromJson<String>(json['payload']),
      state: serializer.fromJson<Map<String, dynamic>>(json['state']),
      status: $TasksTable.$converterstatus
          .fromJson(serializer.fromJson<int>(json['status'])),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'type': serializer.toJson<String>(type),
      'payload': serializer.toJson<String>(payload),
      'state': serializer.toJson<Map<String, dynamic>>(state),
      'status':
          serializer.toJson<int>($TasksTable.$converterstatus.toJson(status)),
    };
  }

  Task copyWith(
          {int? id,
          String? type,
          String? payload,
          Map<String, dynamic>? state,
          TaskStatus? status}) =>
      Task(
        id: id ?? this.id,
        type: type ?? this.type,
        payload: payload ?? this.payload,
        state: state ?? this.state,
        status: status ?? this.status,
      );
  Task copyWithCompanion(TasksCompanion data) {
    return Task(
      id: data.id.present ? data.id.value : this.id,
      type: data.type.present ? data.type.value : this.type,
      payload: data.payload.present ? data.payload.value : this.payload,
      state: data.state.present ? data.state.value : this.state,
      status: data.status.present ? data.status.value : this.status,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Task(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('payload: $payload, ')
          ..write('state: $state, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, type, payload, state, status);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Task &&
          other.id == this.id &&
          other.type == this.type &&
          other.payload == this.payload &&
          other.state == this.state &&
          other.status == this.status);
}

class TasksCompanion extends UpdateCompanion<Task> {
  final Value<int> id;
  final Value<String> type;
  final Value<String> payload;
  final Value<Map<String, dynamic>> state;
  final Value<TaskStatus> status;
  const TasksCompanion({
    this.id = const Value.absent(),
    this.type = const Value.absent(),
    this.payload = const Value.absent(),
    this.state = const Value.absent(),
    this.status = const Value.absent(),
  });
  TasksCompanion.insert({
    this.id = const Value.absent(),
    required String type,
    required String payload,
    required Map<String, dynamic> state,
    required TaskStatus status,
  })  : type = Value(type),
        payload = Value(payload),
        state = Value(state),
        status = Value(status);
  static Insertable<Task> custom({
    Expression<int>? id,
    Expression<String>? type,
    Expression<String>? payload,
    Expression<String>? state,
    Expression<int>? status,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (type != null) 'type': type,
      if (payload != null) 'payload': payload,
      if (state != null) 'state': state,
      if (status != null) 'status': status,
    });
  }

  TasksCompanion copyWith(
      {Value<int>? id,
      Value<String>? type,
      Value<String>? payload,
      Value<Map<String, dynamic>>? state,
      Value<TaskStatus>? status}) {
    return TasksCompanion(
      id: id ?? this.id,
      type: type ?? this.type,
      payload: payload ?? this.payload,
      state: state ?? this.state,
      status: status ?? this.status,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (state.present) {
      map['state'] =
          Variable<String>($TasksTable.$converterstate.toSql(state.value));
    }
    if (status.present) {
      map['status'] =
          Variable<int>($TasksTable.$converterstatus.toSql(status.value));
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TasksCompanion(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('payload: $payload, ')
          ..write('state: $state, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }
}

class $TaskDependenciesTable extends TaskDependencies
    with TableInfo<$TaskDependenciesTable, TaskDependency> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TaskDependenciesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _taskIdMeta = const VerificationMeta('taskId');
  @override
  late final GeneratedColumn<int> taskId = GeneratedColumn<int>(
      'task_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES tasks (id)'));
  static const VerificationMeta _dependentTaskIdMeta =
      const VerificationMeta('dependentTaskId');
  @override
  late final GeneratedColumn<int> dependentTaskId = GeneratedColumn<int>(
      'dependent_task_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES tasks (id)'));
  @override
  List<GeneratedColumn> get $columns => [taskId, dependentTaskId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'task_dependencies';
  @override
  VerificationContext validateIntegrity(Insertable<TaskDependency> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('task_id')) {
      context.handle(_taskIdMeta,
          taskId.isAcceptableOrUnknown(data['task_id']!, _taskIdMeta));
    } else if (isInserting) {
      context.missing(_taskIdMeta);
    }
    if (data.containsKey('dependent_task_id')) {
      context.handle(
          _dependentTaskIdMeta,
          dependentTaskId.isAcceptableOrUnknown(
              data['dependent_task_id']!, _dependentTaskIdMeta));
    } else if (isInserting) {
      context.missing(_dependentTaskIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => const {};
  @override
  TaskDependency map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TaskDependency(
      taskId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}task_id'])!,
      dependentTaskId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}dependent_task_id'])!,
    );
  }

  @override
  $TaskDependenciesTable createAlias(String alias) {
    return $TaskDependenciesTable(attachedDatabase, alias);
  }
}

class TaskDependency extends DataClass implements Insertable<TaskDependency> {
  final int taskId;
  final int dependentTaskId;
  const TaskDependency({required this.taskId, required this.dependentTaskId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['task_id'] = Variable<int>(taskId);
    map['dependent_task_id'] = Variable<int>(dependentTaskId);
    return map;
  }

  TaskDependenciesCompanion toCompanion(bool nullToAbsent) {
    return TaskDependenciesCompanion(
      taskId: Value(taskId),
      dependentTaskId: Value(dependentTaskId),
    );
  }

  factory TaskDependency.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TaskDependency(
      taskId: serializer.fromJson<int>(json['taskId']),
      dependentTaskId: serializer.fromJson<int>(json['dependentTaskId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'taskId': serializer.toJson<int>(taskId),
      'dependentTaskId': serializer.toJson<int>(dependentTaskId),
    };
  }

  TaskDependency copyWith({int? taskId, int? dependentTaskId}) =>
      TaskDependency(
        taskId: taskId ?? this.taskId,
        dependentTaskId: dependentTaskId ?? this.dependentTaskId,
      );
  TaskDependency copyWithCompanion(TaskDependenciesCompanion data) {
    return TaskDependency(
      taskId: data.taskId.present ? data.taskId.value : this.taskId,
      dependentTaskId: data.dependentTaskId.present
          ? data.dependentTaskId.value
          : this.dependentTaskId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TaskDependency(')
          ..write('taskId: $taskId, ')
          ..write('dependentTaskId: $dependentTaskId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(taskId, dependentTaskId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TaskDependency &&
          other.taskId == this.taskId &&
          other.dependentTaskId == this.dependentTaskId);
}

class TaskDependenciesCompanion extends UpdateCompanion<TaskDependency> {
  final Value<int> taskId;
  final Value<int> dependentTaskId;
  final Value<int> rowid;
  const TaskDependenciesCompanion({
    this.taskId = const Value.absent(),
    this.dependentTaskId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TaskDependenciesCompanion.insert({
    required int taskId,
    required int dependentTaskId,
    this.rowid = const Value.absent(),
  })  : taskId = Value(taskId),
        dependentTaskId = Value(dependentTaskId);
  static Insertable<TaskDependency> custom({
    Expression<int>? taskId,
    Expression<int>? dependentTaskId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (taskId != null) 'task_id': taskId,
      if (dependentTaskId != null) 'dependent_task_id': dependentTaskId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TaskDependenciesCompanion copyWith(
      {Value<int>? taskId, Value<int>? dependentTaskId, Value<int>? rowid}) {
    return TaskDependenciesCompanion(
      taskId: taskId ?? this.taskId,
      dependentTaskId: dependentTaskId ?? this.dependentTaskId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (taskId.present) {
      map['task_id'] = Variable<int>(taskId.value);
    }
    if (dependentTaskId.present) {
      map['dependent_task_id'] = Variable<int>(dependentTaskId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TaskDependenciesCompanion(')
          ..write('taskId: $taskId, ')
          ..write('dependentTaskId: $dependentTaskId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$ChatDatabase extends GeneratedDatabase {
  _$ChatDatabase(QueryExecutor e) : super(e);
  $ChatDatabaseManager get managers => $ChatDatabaseManager(this);
  late final $AssestsTable assests = $AssestsTable(this);
  late final $ChannelsTable channels = $ChannelsTable(this);
  late final $ContactsTable contacts = $ContactsTable(this);
  late final $MembersTable members = $MembersTable(this);
  late final $MessagesTable messages = $MessagesTable(this);
  late final $MessageAssetsTable messageAssets = $MessageAssetsTable(this);
  late final $UserProfilesTable userProfiles = $UserProfilesTable(this);
  late final $TasksTable tasks = $TasksTable(this);
  late final $TaskDependenciesTable taskDependencies =
      $TaskDependenciesTable(this);
  late final ChatDao chatDao = ChatDao(this as ChatDatabase);
  late final ChannelDao channelDao = ChannelDao(this as ChatDatabase);
  late final UserProfileDao userProfileDao =
      UserProfileDao(this as ChatDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        assests,
        channels,
        contacts,
        members,
        messages,
        messageAssets,
        userProfiles,
        tasks,
        taskDependencies
      ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules(
        [
          WritePropagation(
            on: TableUpdateQuery.onTableName('contacts',
                limitUpdateKind: UpdateKind.update),
            result: [
              TableUpdate('members', kind: UpdateKind.update),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('channels',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('members', kind: UpdateKind.delete),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('channels',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('messages', kind: UpdateKind.delete),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('contacts',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('messages', kind: UpdateKind.delete),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('messages',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('message_assets', kind: UpdateKind.delete),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('assests',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('message_assets', kind: UpdateKind.delete),
            ],
          ),
        ],
      );
}

typedef $$AssestsTableCreateCompanionBuilder = AssestsCompanion Function({
  Value<int> id,
  Value<String?> type,
  Value<String?> path,
  Value<String?> url,
  Value<String?> assetId,
  Value<String?> mimeType,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<DateTime?> deletedAt,
});
typedef $$AssestsTableUpdateCompanionBuilder = AssestsCompanion Function({
  Value<int> id,
  Value<String?> type,
  Value<String?> path,
  Value<String?> url,
  Value<String?> assetId,
  Value<String?> mimeType,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<DateTime?> deletedAt,
});

final class $$AssestsTableReferences
    extends BaseReferences<_$ChatDatabase, $AssestsTable, AssestEntity> {
  $$AssestsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$MessageAssetsTable, List<MessageAsset>>
      _messageAssetsRefsTable(_$ChatDatabase db) =>
          MultiTypedResultKey.fromTable(db.messageAssets,
              aliasName: $_aliasNameGenerator(
                  db.assests.id, db.messageAssets.assetId));

  $$MessageAssetsTableProcessedTableManager get messageAssetsRefs {
    final manager = $$MessageAssetsTableTableManager($_db, $_db.messageAssets)
        .filter((f) => f.assetId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_messageAssetsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$AssestsTableFilterComposer
    extends Composer<_$ChatDatabase, $AssestsTable> {
  $$AssestsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get path => $composableBuilder(
      column: $table.path, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get url => $composableBuilder(
      column: $table.url, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get assetId => $composableBuilder(
      column: $table.assetId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get mimeType => $composableBuilder(
      column: $table.mimeType, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnFilters(column));

  Expression<bool> messageAssetsRefs(
      Expression<bool> Function($$MessageAssetsTableFilterComposer f) f) {
    final $$MessageAssetsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.messageAssets,
        getReferencedColumn: (t) => t.assetId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$MessageAssetsTableFilterComposer(
              $db: $db,
              $table: $db.messageAssets,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$AssestsTableOrderingComposer
    extends Composer<_$ChatDatabase, $AssestsTable> {
  $$AssestsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get path => $composableBuilder(
      column: $table.path, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get url => $composableBuilder(
      column: $table.url, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get assetId => $composableBuilder(
      column: $table.assetId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get mimeType => $composableBuilder(
      column: $table.mimeType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnOrderings(column));
}

class $$AssestsTableAnnotationComposer
    extends Composer<_$ChatDatabase, $AssestsTable> {
  $$AssestsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<String> get assetId =>
      $composableBuilder(column: $table.assetId, builder: (column) => column);

  GeneratedColumn<String> get mimeType =>
      $composableBuilder(column: $table.mimeType, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  Expression<T> messageAssetsRefs<T extends Object>(
      Expression<T> Function($$MessageAssetsTableAnnotationComposer a) f) {
    final $$MessageAssetsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.messageAssets,
        getReferencedColumn: (t) => t.assetId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$MessageAssetsTableAnnotationComposer(
              $db: $db,
              $table: $db.messageAssets,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$AssestsTableTableManager extends RootTableManager<
    _$ChatDatabase,
    $AssestsTable,
    AssestEntity,
    $$AssestsTableFilterComposer,
    $$AssestsTableOrderingComposer,
    $$AssestsTableAnnotationComposer,
    $$AssestsTableCreateCompanionBuilder,
    $$AssestsTableUpdateCompanionBuilder,
    (AssestEntity, $$AssestsTableReferences),
    AssestEntity,
    PrefetchHooks Function({bool messageAssetsRefs})> {
  $$AssestsTableTableManager(_$ChatDatabase db, $AssestsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AssestsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AssestsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AssestsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String?> type = const Value.absent(),
            Value<String?> path = const Value.absent(),
            Value<String?> url = const Value.absent(),
            Value<String?> assetId = const Value.absent(),
            Value<String?> mimeType = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<DateTime?> deletedAt = const Value.absent(),
          }) =>
              AssestsCompanion(
            id: id,
            type: type,
            path: path,
            url: url,
            assetId: assetId,
            mimeType: mimeType,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String?> type = const Value.absent(),
            Value<String?> path = const Value.absent(),
            Value<String?> url = const Value.absent(),
            Value<String?> assetId = const Value.absent(),
            Value<String?> mimeType = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<DateTime?> deletedAt = const Value.absent(),
          }) =>
              AssestsCompanion.insert(
            id: id,
            type: type,
            path: path,
            url: url,
            assetId: assetId,
            mimeType: mimeType,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) =>
                  (e.readTable(table), $$AssestsTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: ({messageAssetsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (messageAssetsRefs) db.messageAssets
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (messageAssetsRefs)
                    await $_getPrefetchedData<AssestEntity, $AssestsTable,
                            MessageAsset>(
                        currentTable: table,
                        referencedTable: $$AssestsTableReferences
                            ._messageAssetsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$AssestsTableReferences(db, table, p0)
                                .messageAssetsRefs,
                        referencedItemsForCurrentItem: (item,
                                referencedItems) =>
                            referencedItems.where((e) => e.assetId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$AssestsTableProcessedTableManager = ProcessedTableManager<
    _$ChatDatabase,
    $AssestsTable,
    AssestEntity,
    $$AssestsTableFilterComposer,
    $$AssestsTableOrderingComposer,
    $$AssestsTableAnnotationComposer,
    $$AssestsTableCreateCompanionBuilder,
    $$AssestsTableUpdateCompanionBuilder,
    (AssestEntity, $$AssestsTableReferences),
    AssestEntity,
    PrefetchHooks Function({bool messageAssetsRefs})>;
typedef $$ChannelsTableCreateCompanionBuilder = ChannelsCompanion Function({
  Value<int> id,
  required ChannelType type,
  Value<String?> cid,
  Value<int?> taskId,
  Value<Map<String, dynamic>?> extraData,
  Value<Map<String, dynamic>> config,
  Value<bool> muted,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<DateTime?> deletedAt,
});
typedef $$ChannelsTableUpdateCompanionBuilder = ChannelsCompanion Function({
  Value<int> id,
  Value<ChannelType> type,
  Value<String?> cid,
  Value<int?> taskId,
  Value<Map<String, dynamic>?> extraData,
  Value<Map<String, dynamic>> config,
  Value<bool> muted,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<DateTime?> deletedAt,
});

final class $$ChannelsTableReferences
    extends BaseReferences<_$ChatDatabase, $ChannelsTable, ChannelModel> {
  $$ChannelsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$MembersTable, List<MemberEntity>>
      _membersRefsTable(_$ChatDatabase db) =>
          MultiTypedResultKey.fromTable(db.members,
              aliasName:
                  $_aliasNameGenerator(db.channels.id, db.members.channelId));

  $$MembersTableProcessedTableManager get membersRefs {
    final manager = $$MembersTableTableManager($_db, $_db.members)
        .filter((f) => f.channelId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_membersRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$MessagesTable, List<ChatMessage>>
      _messagesRefsTable(_$ChatDatabase db) =>
          MultiTypedResultKey.fromTable(db.messages,
              aliasName:
                  $_aliasNameGenerator(db.channels.id, db.messages.channelId));

  $$MessagesTableProcessedTableManager get messagesRefs {
    final manager = $$MessagesTableTableManager($_db, $_db.messages)
        .filter((f) => f.channelId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_messagesRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$ChannelsTableFilterComposer
    extends Composer<_$ChatDatabase, $ChannelsTable> {
  $$ChannelsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnWithTypeConverterFilters<ChannelType, ChannelType, String> get type =>
      $composableBuilder(
          column: $table.type,
          builder: (column) => ColumnWithTypeConverterFilters(column));

  ColumnFilters<String> get cid => $composableBuilder(
      column: $table.cid, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get taskId => $composableBuilder(
      column: $table.taskId, builder: (column) => ColumnFilters(column));

  ColumnWithTypeConverterFilters<Map<String, dynamic>?, Map<String, dynamic>,
          String>
      get extraData => $composableBuilder(
          column: $table.extraData,
          builder: (column) => ColumnWithTypeConverterFilters(column));

  ColumnWithTypeConverterFilters<Map<String, dynamic>, Map<String, dynamic>,
          String>
      get config => $composableBuilder(
          column: $table.config,
          builder: (column) => ColumnWithTypeConverterFilters(column));

  ColumnFilters<bool> get muted => $composableBuilder(
      column: $table.muted, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnFilters(column));

  Expression<bool> membersRefs(
      Expression<bool> Function($$MembersTableFilterComposer f) f) {
    final $$MembersTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.members,
        getReferencedColumn: (t) => t.channelId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$MembersTableFilterComposer(
              $db: $db,
              $table: $db.members,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<bool> messagesRefs(
      Expression<bool> Function($$MessagesTableFilterComposer f) f) {
    final $$MessagesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.messages,
        getReferencedColumn: (t) => t.channelId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$MessagesTableFilterComposer(
              $db: $db,
              $table: $db.messages,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$ChannelsTableOrderingComposer
    extends Composer<_$ChatDatabase, $ChannelsTable> {
  $$ChannelsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get cid => $composableBuilder(
      column: $table.cid, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get taskId => $composableBuilder(
      column: $table.taskId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get extraData => $composableBuilder(
      column: $table.extraData, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get config => $composableBuilder(
      column: $table.config, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get muted => $composableBuilder(
      column: $table.muted, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnOrderings(column));
}

class $$ChannelsTableAnnotationComposer
    extends Composer<_$ChatDatabase, $ChannelsTable> {
  $$ChannelsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<ChannelType, String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get cid =>
      $composableBuilder(column: $table.cid, builder: (column) => column);

  GeneratedColumn<int> get taskId =>
      $composableBuilder(column: $table.taskId, builder: (column) => column);

  GeneratedColumnWithTypeConverter<Map<String, dynamic>?, String>
      get extraData => $composableBuilder(
          column: $table.extraData, builder: (column) => column);

  GeneratedColumnWithTypeConverter<Map<String, dynamic>, String> get config =>
      $composableBuilder(column: $table.config, builder: (column) => column);

  GeneratedColumn<bool> get muted =>
      $composableBuilder(column: $table.muted, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  Expression<T> membersRefs<T extends Object>(
      Expression<T> Function($$MembersTableAnnotationComposer a) f) {
    final $$MembersTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.members,
        getReferencedColumn: (t) => t.channelId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$MembersTableAnnotationComposer(
              $db: $db,
              $table: $db.members,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<T> messagesRefs<T extends Object>(
      Expression<T> Function($$MessagesTableAnnotationComposer a) f) {
    final $$MessagesTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.messages,
        getReferencedColumn: (t) => t.channelId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$MessagesTableAnnotationComposer(
              $db: $db,
              $table: $db.messages,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$ChannelsTableTableManager extends RootTableManager<
    _$ChatDatabase,
    $ChannelsTable,
    ChannelModel,
    $$ChannelsTableFilterComposer,
    $$ChannelsTableOrderingComposer,
    $$ChannelsTableAnnotationComposer,
    $$ChannelsTableCreateCompanionBuilder,
    $$ChannelsTableUpdateCompanionBuilder,
    (ChannelModel, $$ChannelsTableReferences),
    ChannelModel,
    PrefetchHooks Function({bool membersRefs, bool messagesRefs})> {
  $$ChannelsTableTableManager(_$ChatDatabase db, $ChannelsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChannelsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChannelsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChannelsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<ChannelType> type = const Value.absent(),
            Value<String?> cid = const Value.absent(),
            Value<int?> taskId = const Value.absent(),
            Value<Map<String, dynamic>?> extraData = const Value.absent(),
            Value<Map<String, dynamic>> config = const Value.absent(),
            Value<bool> muted = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<DateTime?> deletedAt = const Value.absent(),
          }) =>
              ChannelsCompanion(
            id: id,
            type: type,
            cid: cid,
            taskId: taskId,
            extraData: extraData,
            config: config,
            muted: muted,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required ChannelType type,
            Value<String?> cid = const Value.absent(),
            Value<int?> taskId = const Value.absent(),
            Value<Map<String, dynamic>?> extraData = const Value.absent(),
            Value<Map<String, dynamic>> config = const Value.absent(),
            Value<bool> muted = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<DateTime?> deletedAt = const Value.absent(),
          }) =>
              ChannelsCompanion.insert(
            id: id,
            type: type,
            cid: cid,
            taskId: taskId,
            extraData: extraData,
            config: config,
            muted: muted,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) =>
                  (e.readTable(table), $$ChannelsTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: ({membersRefs = false, messagesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (membersRefs) db.members,
                if (messagesRefs) db.messages
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (membersRefs)
                    await $_getPrefetchedData<ChannelModel, $ChannelsTable,
                            MemberEntity>(
                        currentTable: table,
                        referencedTable:
                            $$ChannelsTableReferences._membersRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$ChannelsTableReferences(db, table, p0)
                                .membersRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.channelId == item.id),
                        typedResults: items),
                  if (messagesRefs)
                    await $_getPrefetchedData<ChannelModel, $ChannelsTable,
                            ChatMessage>(
                        currentTable: table,
                        referencedTable:
                            $$ChannelsTableReferences._messagesRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$ChannelsTableReferences(db, table, p0)
                                .messagesRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.channelId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$ChannelsTableProcessedTableManager = ProcessedTableManager<
    _$ChatDatabase,
    $ChannelsTable,
    ChannelModel,
    $$ChannelsTableFilterComposer,
    $$ChannelsTableOrderingComposer,
    $$ChannelsTableAnnotationComposer,
    $$ChannelsTableCreateCompanionBuilder,
    $$ChannelsTableUpdateCompanionBuilder,
    (ChannelModel, $$ChannelsTableReferences),
    ChannelModel,
    PrefetchHooks Function({bool membersRefs, bool messagesRefs})>;
typedef $$ContactsTableCreateCompanionBuilder = ContactsCompanion Function({
  Value<int> id,
  Value<String?> username,
  Value<String?> uid,
  Value<String?> phone,
  Value<String?> name,
  Value<Uint8List?> thumbnail,
  Value<String?> photo,
  Value<Map<String, dynamic>?> extraData,
  required ContactStatus status,
});
typedef $$ContactsTableUpdateCompanionBuilder = ContactsCompanion Function({
  Value<int> id,
  Value<String?> username,
  Value<String?> uid,
  Value<String?> phone,
  Value<String?> name,
  Value<Uint8List?> thumbnail,
  Value<String?> photo,
  Value<Map<String, dynamic>?> extraData,
  Value<ContactStatus> status,
});

final class $$ContactsTableReferences
    extends BaseReferences<_$ChatDatabase, $ContactsTable, Contact> {
  $$ContactsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$MembersTable, List<MemberEntity>>
      _membersRefsTable(_$ChatDatabase db) => MultiTypedResultKey.fromTable(
          db.members,
          aliasName: $_aliasNameGenerator(db.contacts.id, db.members.memberId));

  $$MembersTableProcessedTableManager get membersRefs {
    final manager = $$MembersTableTableManager($_db, $_db.members)
        .filter((f) => f.memberId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_membersRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$MessagesTable, List<ChatMessage>>
      _messagesRefsTable(_$ChatDatabase db) =>
          MultiTypedResultKey.fromTable(db.messages,
              aliasName:
                  $_aliasNameGenerator(db.contacts.id, db.messages.senderId));

  $$MessagesTableProcessedTableManager get messagesRefs {
    final manager = $$MessagesTableTableManager($_db, $_db.messages)
        .filter((f) => f.senderId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_messagesRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$ContactsTableFilterComposer
    extends Composer<_$ChatDatabase, $ContactsTable> {
  $$ContactsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get username => $composableBuilder(
      column: $table.username, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get uid => $composableBuilder(
      column: $table.uid, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get phone => $composableBuilder(
      column: $table.phone, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<Uint8List> get thumbnail => $composableBuilder(
      column: $table.thumbnail, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get photo => $composableBuilder(
      column: $table.photo, builder: (column) => ColumnFilters(column));

  ColumnWithTypeConverterFilters<Map<String, dynamic>?, Map<String, dynamic>,
          String>
      get extraData => $composableBuilder(
          column: $table.extraData,
          builder: (column) => ColumnWithTypeConverterFilters(column));

  ColumnWithTypeConverterFilters<ContactStatus, ContactStatus, String>
      get status => $composableBuilder(
          column: $table.status,
          builder: (column) => ColumnWithTypeConverterFilters(column));

  Expression<bool> membersRefs(
      Expression<bool> Function($$MembersTableFilterComposer f) f) {
    final $$MembersTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.members,
        getReferencedColumn: (t) => t.memberId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$MembersTableFilterComposer(
              $db: $db,
              $table: $db.members,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<bool> messagesRefs(
      Expression<bool> Function($$MessagesTableFilterComposer f) f) {
    final $$MessagesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.messages,
        getReferencedColumn: (t) => t.senderId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$MessagesTableFilterComposer(
              $db: $db,
              $table: $db.messages,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$ContactsTableOrderingComposer
    extends Composer<_$ChatDatabase, $ContactsTable> {
  $$ContactsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get username => $composableBuilder(
      column: $table.username, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get uid => $composableBuilder(
      column: $table.uid, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get phone => $composableBuilder(
      column: $table.phone, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<Uint8List> get thumbnail => $composableBuilder(
      column: $table.thumbnail, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get photo => $composableBuilder(
      column: $table.photo, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get extraData => $composableBuilder(
      column: $table.extraData, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));
}

class $$ContactsTableAnnotationComposer
    extends Composer<_$ChatDatabase, $ContactsTable> {
  $$ContactsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<String> get uid =>
      $composableBuilder(column: $table.uid, builder: (column) => column);

  GeneratedColumn<String> get phone =>
      $composableBuilder(column: $table.phone, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<Uint8List> get thumbnail =>
      $composableBuilder(column: $table.thumbnail, builder: (column) => column);

  GeneratedColumn<String> get photo =>
      $composableBuilder(column: $table.photo, builder: (column) => column);

  GeneratedColumnWithTypeConverter<Map<String, dynamic>?, String>
      get extraData => $composableBuilder(
          column: $table.extraData, builder: (column) => column);

  GeneratedColumnWithTypeConverter<ContactStatus, String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  Expression<T> membersRefs<T extends Object>(
      Expression<T> Function($$MembersTableAnnotationComposer a) f) {
    final $$MembersTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.members,
        getReferencedColumn: (t) => t.memberId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$MembersTableAnnotationComposer(
              $db: $db,
              $table: $db.members,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<T> messagesRefs<T extends Object>(
      Expression<T> Function($$MessagesTableAnnotationComposer a) f) {
    final $$MessagesTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.messages,
        getReferencedColumn: (t) => t.senderId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$MessagesTableAnnotationComposer(
              $db: $db,
              $table: $db.messages,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$ContactsTableTableManager extends RootTableManager<
    _$ChatDatabase,
    $ContactsTable,
    Contact,
    $$ContactsTableFilterComposer,
    $$ContactsTableOrderingComposer,
    $$ContactsTableAnnotationComposer,
    $$ContactsTableCreateCompanionBuilder,
    $$ContactsTableUpdateCompanionBuilder,
    (Contact, $$ContactsTableReferences),
    Contact,
    PrefetchHooks Function({bool membersRefs, bool messagesRefs})> {
  $$ContactsTableTableManager(_$ChatDatabase db, $ContactsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ContactsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ContactsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ContactsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String?> username = const Value.absent(),
            Value<String?> uid = const Value.absent(),
            Value<String?> phone = const Value.absent(),
            Value<String?> name = const Value.absent(),
            Value<Uint8List?> thumbnail = const Value.absent(),
            Value<String?> photo = const Value.absent(),
            Value<Map<String, dynamic>?> extraData = const Value.absent(),
            Value<ContactStatus> status = const Value.absent(),
          }) =>
              ContactsCompanion(
            id: id,
            username: username,
            uid: uid,
            phone: phone,
            name: name,
            thumbnail: thumbnail,
            photo: photo,
            extraData: extraData,
            status: status,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String?> username = const Value.absent(),
            Value<String?> uid = const Value.absent(),
            Value<String?> phone = const Value.absent(),
            Value<String?> name = const Value.absent(),
            Value<Uint8List?> thumbnail = const Value.absent(),
            Value<String?> photo = const Value.absent(),
            Value<Map<String, dynamic>?> extraData = const Value.absent(),
            required ContactStatus status,
          }) =>
              ContactsCompanion.insert(
            id: id,
            username: username,
            uid: uid,
            phone: phone,
            name: name,
            thumbnail: thumbnail,
            photo: photo,
            extraData: extraData,
            status: status,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) =>
                  (e.readTable(table), $$ContactsTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: ({membersRefs = false, messagesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (membersRefs) db.members,
                if (messagesRefs) db.messages
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (membersRefs)
                    await $_getPrefetchedData<Contact, $ContactsTable,
                            MemberEntity>(
                        currentTable: table,
                        referencedTable:
                            $$ContactsTableReferences._membersRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$ContactsTableReferences(db, table, p0)
                                .membersRefs,
                        referencedItemsForCurrentItem: (item,
                                referencedItems) =>
                            referencedItems.where((e) => e.memberId == item.id),
                        typedResults: items),
                  if (messagesRefs)
                    await $_getPrefetchedData<Contact, $ContactsTable,
                            ChatMessage>(
                        currentTable: table,
                        referencedTable:
                            $$ContactsTableReferences._messagesRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$ContactsTableReferences(db, table, p0)
                                .messagesRefs,
                        referencedItemsForCurrentItem: (item,
                                referencedItems) =>
                            referencedItems.where((e) => e.senderId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$ContactsTableProcessedTableManager = ProcessedTableManager<
    _$ChatDatabase,
    $ContactsTable,
    Contact,
    $$ContactsTableFilterComposer,
    $$ContactsTableOrderingComposer,
    $$ContactsTableAnnotationComposer,
    $$ContactsTableCreateCompanionBuilder,
    $$ContactsTableUpdateCompanionBuilder,
    (Contact, $$ContactsTableReferences),
    Contact,
    PrefetchHooks Function({bool membersRefs, bool messagesRefs})>;
typedef $$MembersTableCreateCompanionBuilder = MembersCompanion Function({
  required int memberId,
  required int channelId,
  Value<String?> role,
  Value<DateTime> since,
  Value<DateTime> updatedAt,
  Value<DateTime?> deletedAt,
  Value<int> rowid,
});
typedef $$MembersTableUpdateCompanionBuilder = MembersCompanion Function({
  Value<int> memberId,
  Value<int> channelId,
  Value<String?> role,
  Value<DateTime> since,
  Value<DateTime> updatedAt,
  Value<DateTime?> deletedAt,
  Value<int> rowid,
});

final class $$MembersTableReferences
    extends BaseReferences<_$ChatDatabase, $MembersTable, MemberEntity> {
  $$MembersTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ContactsTable _memberIdTable(_$ChatDatabase db) => db.contacts
      .createAlias($_aliasNameGenerator(db.members.memberId, db.contacts.id));

  $$ContactsTableProcessedTableManager get memberId {
    final $_column = $_itemColumn<int>('member_id')!;

    final manager = $$ContactsTableTableManager($_db, $_db.contacts)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_memberIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static $ChannelsTable _channelIdTable(_$ChatDatabase db) => db.channels
      .createAlias($_aliasNameGenerator(db.members.channelId, db.channels.id));

  $$ChannelsTableProcessedTableManager get channelId {
    final $_column = $_itemColumn<int>('channel_id')!;

    final manager = $$ChannelsTableTableManager($_db, $_db.channels)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_channelIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$MembersTableFilterComposer
    extends Composer<_$ChatDatabase, $MembersTable> {
  $$MembersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get role => $composableBuilder(
      column: $table.role, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get since => $composableBuilder(
      column: $table.since, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnFilters(column));

  $$ContactsTableFilterComposer get memberId {
    final $$ContactsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.memberId,
        referencedTable: $db.contacts,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ContactsTableFilterComposer(
              $db: $db,
              $table: $db.contacts,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$ChannelsTableFilterComposer get channelId {
    final $$ChannelsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.channelId,
        referencedTable: $db.channels,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ChannelsTableFilterComposer(
              $db: $db,
              $table: $db.channels,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$MembersTableOrderingComposer
    extends Composer<_$ChatDatabase, $MembersTable> {
  $$MembersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get role => $composableBuilder(
      column: $table.role, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get since => $composableBuilder(
      column: $table.since, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnOrderings(column));

  $$ContactsTableOrderingComposer get memberId {
    final $$ContactsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.memberId,
        referencedTable: $db.contacts,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ContactsTableOrderingComposer(
              $db: $db,
              $table: $db.contacts,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$ChannelsTableOrderingComposer get channelId {
    final $$ChannelsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.channelId,
        referencedTable: $db.channels,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ChannelsTableOrderingComposer(
              $db: $db,
              $table: $db.channels,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$MembersTableAnnotationComposer
    extends Composer<_$ChatDatabase, $MembersTable> {
  $$MembersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<DateTime> get since =>
      $composableBuilder(column: $table.since, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  $$ContactsTableAnnotationComposer get memberId {
    final $$ContactsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.memberId,
        referencedTable: $db.contacts,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ContactsTableAnnotationComposer(
              $db: $db,
              $table: $db.contacts,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$ChannelsTableAnnotationComposer get channelId {
    final $$ChannelsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.channelId,
        referencedTable: $db.channels,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ChannelsTableAnnotationComposer(
              $db: $db,
              $table: $db.channels,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$MembersTableTableManager extends RootTableManager<
    _$ChatDatabase,
    $MembersTable,
    MemberEntity,
    $$MembersTableFilterComposer,
    $$MembersTableOrderingComposer,
    $$MembersTableAnnotationComposer,
    $$MembersTableCreateCompanionBuilder,
    $$MembersTableUpdateCompanionBuilder,
    (MemberEntity, $$MembersTableReferences),
    MemberEntity,
    PrefetchHooks Function({bool memberId, bool channelId})> {
  $$MembersTableTableManager(_$ChatDatabase db, $MembersTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MembersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MembersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MembersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> memberId = const Value.absent(),
            Value<int> channelId = const Value.absent(),
            Value<String?> role = const Value.absent(),
            Value<DateTime> since = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<DateTime?> deletedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MembersCompanion(
            memberId: memberId,
            channelId: channelId,
            role: role,
            since: since,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required int memberId,
            required int channelId,
            Value<String?> role = const Value.absent(),
            Value<DateTime> since = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<DateTime?> deletedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MembersCompanion.insert(
            memberId: memberId,
            channelId: channelId,
            role: role,
            since: since,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) =>
                  (e.readTable(table), $$MembersTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: ({memberId = false, channelId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (memberId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.memberId,
                    referencedTable:
                        $$MembersTableReferences._memberIdTable(db),
                    referencedColumn:
                        $$MembersTableReferences._memberIdTable(db).id,
                  ) as T;
                }
                if (channelId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.channelId,
                    referencedTable:
                        $$MembersTableReferences._channelIdTable(db),
                    referencedColumn:
                        $$MembersTableReferences._channelIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$MembersTableProcessedTableManager = ProcessedTableManager<
    _$ChatDatabase,
    $MembersTable,
    MemberEntity,
    $$MembersTableFilterComposer,
    $$MembersTableOrderingComposer,
    $$MembersTableAnnotationComposer,
    $$MembersTableCreateCompanionBuilder,
    $$MembersTableUpdateCompanionBuilder,
    (MemberEntity, $$MembersTableReferences),
    MemberEntity,
    PrefetchHooks Function({bool memberId, bool channelId})>;
typedef $$MessagesTableCreateCompanionBuilder = MessagesCompanion Function({
  Value<int> id,
  Value<String?> rid,
  required MessageType type,
  required MessageState state,
  required Map<String, dynamic> payload,
  required int channelId,
  required int senderId,
  Value<DateTime> localCreatedAt,
  Value<DateTime?> remoteCreatedAt,
  Value<DateTime> updatedAt,
});
typedef $$MessagesTableUpdateCompanionBuilder = MessagesCompanion Function({
  Value<int> id,
  Value<String?> rid,
  Value<MessageType> type,
  Value<MessageState> state,
  Value<Map<String, dynamic>> payload,
  Value<int> channelId,
  Value<int> senderId,
  Value<DateTime> localCreatedAt,
  Value<DateTime?> remoteCreatedAt,
  Value<DateTime> updatedAt,
});

final class $$MessagesTableReferences
    extends BaseReferences<_$ChatDatabase, $MessagesTable, ChatMessage> {
  $$MessagesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ChannelsTable _channelIdTable(_$ChatDatabase db) => db.channels
      .createAlias($_aliasNameGenerator(db.messages.channelId, db.channels.id));

  $$ChannelsTableProcessedTableManager get channelId {
    final $_column = $_itemColumn<int>('channel_id')!;

    final manager = $$ChannelsTableTableManager($_db, $_db.channels)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_channelIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static $ContactsTable _senderIdTable(_$ChatDatabase db) => db.contacts
      .createAlias($_aliasNameGenerator(db.messages.senderId, db.contacts.id));

  $$ContactsTableProcessedTableManager get senderId {
    final $_column = $_itemColumn<int>('sender_id')!;

    final manager = $$ContactsTableTableManager($_db, $_db.contacts)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_senderIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static MultiTypedResultKey<$MessageAssetsTable, List<MessageAsset>>
      _messageAssetsRefsTable(_$ChatDatabase db) =>
          MultiTypedResultKey.fromTable(db.messageAssets,
              aliasName: $_aliasNameGenerator(
                  db.messages.id, db.messageAssets.messageId));

  $$MessageAssetsTableProcessedTableManager get messageAssetsRefs {
    final manager = $$MessageAssetsTableTableManager($_db, $_db.messageAssets)
        .filter((f) => f.messageId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_messageAssetsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$MessagesTableFilterComposer
    extends Composer<_$ChatDatabase, $MessagesTable> {
  $$MessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get rid => $composableBuilder(
      column: $table.rid, builder: (column) => ColumnFilters(column));

  ColumnWithTypeConverterFilters<MessageType, MessageType, String> get type =>
      $composableBuilder(
          column: $table.type,
          builder: (column) => ColumnWithTypeConverterFilters(column));

  ColumnWithTypeConverterFilters<MessageState, MessageState, String>
      get state => $composableBuilder(
          column: $table.state,
          builder: (column) => ColumnWithTypeConverterFilters(column));

  ColumnWithTypeConverterFilters<Map<String, dynamic>, Map<String, dynamic>,
          String>
      get payload => $composableBuilder(
          column: $table.payload,
          builder: (column) => ColumnWithTypeConverterFilters(column));

  ColumnFilters<DateTime> get localCreatedAt => $composableBuilder(
      column: $table.localCreatedAt,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get remoteCreatedAt => $composableBuilder(
      column: $table.remoteCreatedAt,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  $$ChannelsTableFilterComposer get channelId {
    final $$ChannelsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.channelId,
        referencedTable: $db.channels,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ChannelsTableFilterComposer(
              $db: $db,
              $table: $db.channels,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$ContactsTableFilterComposer get senderId {
    final $$ContactsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.senderId,
        referencedTable: $db.contacts,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ContactsTableFilterComposer(
              $db: $db,
              $table: $db.contacts,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<bool> messageAssetsRefs(
      Expression<bool> Function($$MessageAssetsTableFilterComposer f) f) {
    final $$MessageAssetsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.messageAssets,
        getReferencedColumn: (t) => t.messageId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$MessageAssetsTableFilterComposer(
              $db: $db,
              $table: $db.messageAssets,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$MessagesTableOrderingComposer
    extends Composer<_$ChatDatabase, $MessagesTable> {
  $$MessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get rid => $composableBuilder(
      column: $table.rid, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get state => $composableBuilder(
      column: $table.state, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get localCreatedAt => $composableBuilder(
      column: $table.localCreatedAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get remoteCreatedAt => $composableBuilder(
      column: $table.remoteCreatedAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  $$ChannelsTableOrderingComposer get channelId {
    final $$ChannelsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.channelId,
        referencedTable: $db.channels,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ChannelsTableOrderingComposer(
              $db: $db,
              $table: $db.channels,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$ContactsTableOrderingComposer get senderId {
    final $$ContactsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.senderId,
        referencedTable: $db.contacts,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ContactsTableOrderingComposer(
              $db: $db,
              $table: $db.contacts,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$MessagesTableAnnotationComposer
    extends Composer<_$ChatDatabase, $MessagesTable> {
  $$MessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get rid =>
      $composableBuilder(column: $table.rid, builder: (column) => column);

  GeneratedColumnWithTypeConverter<MessageType, String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumnWithTypeConverter<MessageState, String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumnWithTypeConverter<Map<String, dynamic>, String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<DateTime> get localCreatedAt => $composableBuilder(
      column: $table.localCreatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get remoteCreatedAt => $composableBuilder(
      column: $table.remoteCreatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$ChannelsTableAnnotationComposer get channelId {
    final $$ChannelsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.channelId,
        referencedTable: $db.channels,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ChannelsTableAnnotationComposer(
              $db: $db,
              $table: $db.channels,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$ContactsTableAnnotationComposer get senderId {
    final $$ContactsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.senderId,
        referencedTable: $db.contacts,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ContactsTableAnnotationComposer(
              $db: $db,
              $table: $db.contacts,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<T> messageAssetsRefs<T extends Object>(
      Expression<T> Function($$MessageAssetsTableAnnotationComposer a) f) {
    final $$MessageAssetsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.messageAssets,
        getReferencedColumn: (t) => t.messageId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$MessageAssetsTableAnnotationComposer(
              $db: $db,
              $table: $db.messageAssets,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$MessagesTableTableManager extends RootTableManager<
    _$ChatDatabase,
    $MessagesTable,
    ChatMessage,
    $$MessagesTableFilterComposer,
    $$MessagesTableOrderingComposer,
    $$MessagesTableAnnotationComposer,
    $$MessagesTableCreateCompanionBuilder,
    $$MessagesTableUpdateCompanionBuilder,
    (ChatMessage, $$MessagesTableReferences),
    ChatMessage,
    PrefetchHooks Function(
        {bool channelId, bool senderId, bool messageAssetsRefs})> {
  $$MessagesTableTableManager(_$ChatDatabase db, $MessagesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String?> rid = const Value.absent(),
            Value<MessageType> type = const Value.absent(),
            Value<MessageState> state = const Value.absent(),
            Value<Map<String, dynamic>> payload = const Value.absent(),
            Value<int> channelId = const Value.absent(),
            Value<int> senderId = const Value.absent(),
            Value<DateTime> localCreatedAt = const Value.absent(),
            Value<DateTime?> remoteCreatedAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
          }) =>
              MessagesCompanion(
            id: id,
            rid: rid,
            type: type,
            state: state,
            payload: payload,
            channelId: channelId,
            senderId: senderId,
            localCreatedAt: localCreatedAt,
            remoteCreatedAt: remoteCreatedAt,
            updatedAt: updatedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String?> rid = const Value.absent(),
            required MessageType type,
            required MessageState state,
            required Map<String, dynamic> payload,
            required int channelId,
            required int senderId,
            Value<DateTime> localCreatedAt = const Value.absent(),
            Value<DateTime?> remoteCreatedAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
          }) =>
              MessagesCompanion.insert(
            id: id,
            rid: rid,
            type: type,
            state: state,
            payload: payload,
            channelId: channelId,
            senderId: senderId,
            localCreatedAt: localCreatedAt,
            remoteCreatedAt: remoteCreatedAt,
            updatedAt: updatedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) =>
                  (e.readTable(table), $$MessagesTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: (
              {channelId = false,
              senderId = false,
              messageAssetsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (messageAssetsRefs) db.messageAssets
              ],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (channelId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.channelId,
                    referencedTable:
                        $$MessagesTableReferences._channelIdTable(db),
                    referencedColumn:
                        $$MessagesTableReferences._channelIdTable(db).id,
                  ) as T;
                }
                if (senderId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.senderId,
                    referencedTable:
                        $$MessagesTableReferences._senderIdTable(db),
                    referencedColumn:
                        $$MessagesTableReferences._senderIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (messageAssetsRefs)
                    await $_getPrefetchedData<ChatMessage, $MessagesTable,
                            MessageAsset>(
                        currentTable: table,
                        referencedTable: $$MessagesTableReferences
                            ._messageAssetsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$MessagesTableReferences(db, table, p0)
                                .messageAssetsRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.messageId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$MessagesTableProcessedTableManager = ProcessedTableManager<
    _$ChatDatabase,
    $MessagesTable,
    ChatMessage,
    $$MessagesTableFilterComposer,
    $$MessagesTableOrderingComposer,
    $$MessagesTableAnnotationComposer,
    $$MessagesTableCreateCompanionBuilder,
    $$MessagesTableUpdateCompanionBuilder,
    (ChatMessage, $$MessagesTableReferences),
    ChatMessage,
    PrefetchHooks Function(
        {bool channelId, bool senderId, bool messageAssetsRefs})>;
typedef $$MessageAssetsTableCreateCompanionBuilder = MessageAssetsCompanion
    Function({
  required int messageId,
  required int assetId,
  Value<int> rowid,
});
typedef $$MessageAssetsTableUpdateCompanionBuilder = MessageAssetsCompanion
    Function({
  Value<int> messageId,
  Value<int> assetId,
  Value<int> rowid,
});

final class $$MessageAssetsTableReferences
    extends BaseReferences<_$ChatDatabase, $MessageAssetsTable, MessageAsset> {
  $$MessageAssetsTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $MessagesTable _messageIdTable(_$ChatDatabase db) =>
      db.messages.createAlias(
          $_aliasNameGenerator(db.messageAssets.messageId, db.messages.id));

  $$MessagesTableProcessedTableManager get messageId {
    final $_column = $_itemColumn<int>('message_id')!;

    final manager = $$MessagesTableTableManager($_db, $_db.messages)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_messageIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static $AssestsTable _assetIdTable(_$ChatDatabase db) =>
      db.assests.createAlias(
          $_aliasNameGenerator(db.messageAssets.assetId, db.assests.id));

  $$AssestsTableProcessedTableManager get assetId {
    final $_column = $_itemColumn<int>('asset_id')!;

    final manager = $$AssestsTableTableManager($_db, $_db.assests)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_assetIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$MessageAssetsTableFilterComposer
    extends Composer<_$ChatDatabase, $MessageAssetsTable> {
  $$MessageAssetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$MessagesTableFilterComposer get messageId {
    final $$MessagesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.messageId,
        referencedTable: $db.messages,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$MessagesTableFilterComposer(
              $db: $db,
              $table: $db.messages,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$AssestsTableFilterComposer get assetId {
    final $$AssestsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.assetId,
        referencedTable: $db.assests,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$AssestsTableFilterComposer(
              $db: $db,
              $table: $db.assests,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$MessageAssetsTableOrderingComposer
    extends Composer<_$ChatDatabase, $MessageAssetsTable> {
  $$MessageAssetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$MessagesTableOrderingComposer get messageId {
    final $$MessagesTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.messageId,
        referencedTable: $db.messages,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$MessagesTableOrderingComposer(
              $db: $db,
              $table: $db.messages,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$AssestsTableOrderingComposer get assetId {
    final $$AssestsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.assetId,
        referencedTable: $db.assests,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$AssestsTableOrderingComposer(
              $db: $db,
              $table: $db.assests,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$MessageAssetsTableAnnotationComposer
    extends Composer<_$ChatDatabase, $MessageAssetsTable> {
  $$MessageAssetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$MessagesTableAnnotationComposer get messageId {
    final $$MessagesTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.messageId,
        referencedTable: $db.messages,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$MessagesTableAnnotationComposer(
              $db: $db,
              $table: $db.messages,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$AssestsTableAnnotationComposer get assetId {
    final $$AssestsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.assetId,
        referencedTable: $db.assests,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$AssestsTableAnnotationComposer(
              $db: $db,
              $table: $db.assests,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$MessageAssetsTableTableManager extends RootTableManager<
    _$ChatDatabase,
    $MessageAssetsTable,
    MessageAsset,
    $$MessageAssetsTableFilterComposer,
    $$MessageAssetsTableOrderingComposer,
    $$MessageAssetsTableAnnotationComposer,
    $$MessageAssetsTableCreateCompanionBuilder,
    $$MessageAssetsTableUpdateCompanionBuilder,
    (MessageAsset, $$MessageAssetsTableReferences),
    MessageAsset,
    PrefetchHooks Function({bool messageId, bool assetId})> {
  $$MessageAssetsTableTableManager(_$ChatDatabase db, $MessageAssetsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessageAssetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessageAssetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessageAssetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> messageId = const Value.absent(),
            Value<int> assetId = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MessageAssetsCompanion(
            messageId: messageId,
            assetId: assetId,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required int messageId,
            required int assetId,
            Value<int> rowid = const Value.absent(),
          }) =>
              MessageAssetsCompanion.insert(
            messageId: messageId,
            assetId: assetId,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$MessageAssetsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({messageId = false, assetId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (messageId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.messageId,
                    referencedTable:
                        $$MessageAssetsTableReferences._messageIdTable(db),
                    referencedColumn:
                        $$MessageAssetsTableReferences._messageIdTable(db).id,
                  ) as T;
                }
                if (assetId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.assetId,
                    referencedTable:
                        $$MessageAssetsTableReferences._assetIdTable(db),
                    referencedColumn:
                        $$MessageAssetsTableReferences._assetIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$MessageAssetsTableProcessedTableManager = ProcessedTableManager<
    _$ChatDatabase,
    $MessageAssetsTable,
    MessageAsset,
    $$MessageAssetsTableFilterComposer,
    $$MessageAssetsTableOrderingComposer,
    $$MessageAssetsTableAnnotationComposer,
    $$MessageAssetsTableCreateCompanionBuilder,
    $$MessageAssetsTableUpdateCompanionBuilder,
    (MessageAsset, $$MessageAssetsTableReferences),
    MessageAsset,
    PrefetchHooks Function({bool messageId, bool assetId})>;
typedef $$UserProfilesTableCreateCompanionBuilder = UserProfilesCompanion
    Function({
  required String userId,
  required String name,
  required String email,
  required String image,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$UserProfilesTableUpdateCompanionBuilder = UserProfilesCompanion
    Function({
  Value<String> userId,
  Value<String> name,
  Value<String> email,
  Value<String> image,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$UserProfilesTableFilterComposer
    extends Composer<_$ChatDatabase, $UserProfilesTable> {
  $$UserProfilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get userId => $composableBuilder(
      column: $table.userId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get email => $composableBuilder(
      column: $table.email, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get image => $composableBuilder(
      column: $table.image, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$UserProfilesTableOrderingComposer
    extends Composer<_$ChatDatabase, $UserProfilesTable> {
  $$UserProfilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get userId => $composableBuilder(
      column: $table.userId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get email => $composableBuilder(
      column: $table.email, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get image => $composableBuilder(
      column: $table.image, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$UserProfilesTableAnnotationComposer
    extends Composer<_$ChatDatabase, $UserProfilesTable> {
  $$UserProfilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get email =>
      $composableBuilder(column: $table.email, builder: (column) => column);

  GeneratedColumn<String> get image =>
      $composableBuilder(column: $table.image, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$UserProfilesTableTableManager extends RootTableManager<
    _$ChatDatabase,
    $UserProfilesTable,
    Profile,
    $$UserProfilesTableFilterComposer,
    $$UserProfilesTableOrderingComposer,
    $$UserProfilesTableAnnotationComposer,
    $$UserProfilesTableCreateCompanionBuilder,
    $$UserProfilesTableUpdateCompanionBuilder,
    (Profile, BaseReferences<_$ChatDatabase, $UserProfilesTable, Profile>),
    Profile,
    PrefetchHooks Function()> {
  $$UserProfilesTableTableManager(_$ChatDatabase db, $UserProfilesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UserProfilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UserProfilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UserProfilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> userId = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> email = const Value.absent(),
            Value<String> image = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              UserProfilesCompanion(
            userId: userId,
            name: name,
            email: email,
            image: image,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String userId,
            required String name,
            required String email,
            required String image,
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              UserProfilesCompanion.insert(
            userId: userId,
            name: name,
            email: email,
            image: image,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$UserProfilesTableProcessedTableManager = ProcessedTableManager<
    _$ChatDatabase,
    $UserProfilesTable,
    Profile,
    $$UserProfilesTableFilterComposer,
    $$UserProfilesTableOrderingComposer,
    $$UserProfilesTableAnnotationComposer,
    $$UserProfilesTableCreateCompanionBuilder,
    $$UserProfilesTableUpdateCompanionBuilder,
    (Profile, BaseReferences<_$ChatDatabase, $UserProfilesTable, Profile>),
    Profile,
    PrefetchHooks Function()>;
typedef $$TasksTableCreateCompanionBuilder = TasksCompanion Function({
  Value<int> id,
  required String type,
  required String payload,
  required Map<String, dynamic> state,
  required TaskStatus status,
});
typedef $$TasksTableUpdateCompanionBuilder = TasksCompanion Function({
  Value<int> id,
  Value<String> type,
  Value<String> payload,
  Value<Map<String, dynamic>> state,
  Value<TaskStatus> status,
});

final class $$TasksTableReferences
    extends BaseReferences<_$ChatDatabase, $TasksTable, Task> {
  $$TasksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$TaskDependenciesTable, List<TaskDependency>>
      _taskDependenciesRefsTable(_$ChatDatabase db) =>
          MultiTypedResultKey.fromTable(db.taskDependencies,
              aliasName: $_aliasNameGenerator(
                  db.tasks.id, db.taskDependencies.taskId));

  $$TaskDependenciesTableProcessedTableManager get taskDependenciesRefs {
    final manager =
        $$TaskDependenciesTableTableManager($_db, $_db.taskDependencies)
            .filter((f) => f.taskId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache =
        $_typedResult.readTableOrNull(_taskDependenciesRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$TaskDependenciesTable, List<TaskDependency>>
      _ref_dependenct_task_idTable(_$ChatDatabase db) =>
          MultiTypedResultKey.fromTable(db.taskDependencies,
              aliasName: $_aliasNameGenerator(
                  db.tasks.id, db.taskDependencies.dependentTaskId));

  $$TaskDependenciesTableProcessedTableManager get ref_dependenct_task_id {
    final manager =
        $$TaskDependenciesTableTableManager($_db, $_db.taskDependencies).filter(
            (f) => f.dependentTaskId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache =
        $_typedResult.readTableOrNull(_ref_dependenct_task_idTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$TasksTableFilterComposer extends Composer<_$ChatDatabase, $TasksTable> {
  $$TasksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnFilters(column));

  ColumnWithTypeConverterFilters<Map<String, dynamic>, Map<String, dynamic>,
          String>
      get state => $composableBuilder(
          column: $table.state,
          builder: (column) => ColumnWithTypeConverterFilters(column));

  ColumnWithTypeConverterFilters<TaskStatus, TaskStatus, int> get status =>
      $composableBuilder(
          column: $table.status,
          builder: (column) => ColumnWithTypeConverterFilters(column));

  Expression<bool> taskDependenciesRefs(
      Expression<bool> Function($$TaskDependenciesTableFilterComposer f) f) {
    final $$TaskDependenciesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.taskDependencies,
        getReferencedColumn: (t) => t.taskId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TaskDependenciesTableFilterComposer(
              $db: $db,
              $table: $db.taskDependencies,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<bool> ref_dependenct_task_id(
      Expression<bool> Function($$TaskDependenciesTableFilterComposer f) f) {
    final $$TaskDependenciesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.taskDependencies,
        getReferencedColumn: (t) => t.dependentTaskId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TaskDependenciesTableFilterComposer(
              $db: $db,
              $table: $db.taskDependencies,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$TasksTableOrderingComposer
    extends Composer<_$ChatDatabase, $TasksTable> {
  $$TasksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get state => $composableBuilder(
      column: $table.state, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));
}

class $$TasksTableAnnotationComposer
    extends Composer<_$ChatDatabase, $TasksTable> {
  $$TasksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumnWithTypeConverter<Map<String, dynamic>, String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumnWithTypeConverter<TaskStatus, int> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  Expression<T> taskDependenciesRefs<T extends Object>(
      Expression<T> Function($$TaskDependenciesTableAnnotationComposer a) f) {
    final $$TaskDependenciesTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.taskDependencies,
        getReferencedColumn: (t) => t.taskId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TaskDependenciesTableAnnotationComposer(
              $db: $db,
              $table: $db.taskDependencies,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<T> ref_dependenct_task_id<T extends Object>(
      Expression<T> Function($$TaskDependenciesTableAnnotationComposer a) f) {
    final $$TaskDependenciesTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.taskDependencies,
        getReferencedColumn: (t) => t.dependentTaskId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TaskDependenciesTableAnnotationComposer(
              $db: $db,
              $table: $db.taskDependencies,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$TasksTableTableManager extends RootTableManager<
    _$ChatDatabase,
    $TasksTable,
    Task,
    $$TasksTableFilterComposer,
    $$TasksTableOrderingComposer,
    $$TasksTableAnnotationComposer,
    $$TasksTableCreateCompanionBuilder,
    $$TasksTableUpdateCompanionBuilder,
    (Task, $$TasksTableReferences),
    Task,
    PrefetchHooks Function(
        {bool taskDependenciesRefs, bool ref_dependenct_task_id})> {
  $$TasksTableTableManager(_$ChatDatabase db, $TasksTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TasksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TasksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TasksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<String> payload = const Value.absent(),
            Value<Map<String, dynamic>> state = const Value.absent(),
            Value<TaskStatus> status = const Value.absent(),
          }) =>
              TasksCompanion(
            id: id,
            type: type,
            payload: payload,
            state: state,
            status: status,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String type,
            required String payload,
            required Map<String, dynamic> state,
            required TaskStatus status,
          }) =>
              TasksCompanion.insert(
            id: id,
            type: type,
            payload: payload,
            state: state,
            status: status,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) =>
                  (e.readTable(table), $$TasksTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: (
              {taskDependenciesRefs = false, ref_dependenct_task_id = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (taskDependenciesRefs) db.taskDependencies,
                if (ref_dependenct_task_id) db.taskDependencies
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (taskDependenciesRefs)
                    await $_getPrefetchedData<Task, $TasksTable,
                            TaskDependency>(
                        currentTable: table,
                        referencedTable: $$TasksTableReferences
                            ._taskDependenciesRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$TasksTableReferences(db, table, p0)
                                .taskDependenciesRefs,
                        referencedItemsForCurrentItem: (item,
                                referencedItems) =>
                            referencedItems.where((e) => e.taskId == item.id),
                        typedResults: items),
                  if (ref_dependenct_task_id)
                    await $_getPrefetchedData<Task, $TasksTable,
                            TaskDependency>(
                        currentTable: table,
                        referencedTable: $$TasksTableReferences
                            ._ref_dependenct_task_idTable(db),
                        managerFromTypedResult: (p0) =>
                            $$TasksTableReferences(db, table, p0)
                                .ref_dependenct_task_id,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.dependentTaskId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$TasksTableProcessedTableManager = ProcessedTableManager<
    _$ChatDatabase,
    $TasksTable,
    Task,
    $$TasksTableFilterComposer,
    $$TasksTableOrderingComposer,
    $$TasksTableAnnotationComposer,
    $$TasksTableCreateCompanionBuilder,
    $$TasksTableUpdateCompanionBuilder,
    (Task, $$TasksTableReferences),
    Task,
    PrefetchHooks Function(
        {bool taskDependenciesRefs, bool ref_dependenct_task_id})>;
typedef $$TaskDependenciesTableCreateCompanionBuilder
    = TaskDependenciesCompanion Function({
  required int taskId,
  required int dependentTaskId,
  Value<int> rowid,
});
typedef $$TaskDependenciesTableUpdateCompanionBuilder
    = TaskDependenciesCompanion Function({
  Value<int> taskId,
  Value<int> dependentTaskId,
  Value<int> rowid,
});

final class $$TaskDependenciesTableReferences extends BaseReferences<
    _$ChatDatabase, $TaskDependenciesTable, TaskDependency> {
  $$TaskDependenciesTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $TasksTable _taskIdTable(_$ChatDatabase db) => db.tasks.createAlias(
      $_aliasNameGenerator(db.taskDependencies.taskId, db.tasks.id));

  $$TasksTableProcessedTableManager get taskId {
    final $_column = $_itemColumn<int>('task_id')!;

    final manager = $$TasksTableTableManager($_db, $_db.tasks)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_taskIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static $TasksTable _dependentTaskIdTable(_$ChatDatabase db) =>
      db.tasks.createAlias($_aliasNameGenerator(
          db.taskDependencies.dependentTaskId, db.tasks.id));

  $$TasksTableProcessedTableManager get dependentTaskId {
    final $_column = $_itemColumn<int>('dependent_task_id')!;

    final manager = $$TasksTableTableManager($_db, $_db.tasks)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_dependentTaskIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$TaskDependenciesTableFilterComposer
    extends Composer<_$ChatDatabase, $TaskDependenciesTable> {
  $$TaskDependenciesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$TasksTableFilterComposer get taskId {
    final $$TasksTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.taskId,
        referencedTable: $db.tasks,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TasksTableFilterComposer(
              $db: $db,
              $table: $db.tasks,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$TasksTableFilterComposer get dependentTaskId {
    final $$TasksTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.dependentTaskId,
        referencedTable: $db.tasks,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TasksTableFilterComposer(
              $db: $db,
              $table: $db.tasks,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$TaskDependenciesTableOrderingComposer
    extends Composer<_$ChatDatabase, $TaskDependenciesTable> {
  $$TaskDependenciesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$TasksTableOrderingComposer get taskId {
    final $$TasksTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.taskId,
        referencedTable: $db.tasks,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TasksTableOrderingComposer(
              $db: $db,
              $table: $db.tasks,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$TasksTableOrderingComposer get dependentTaskId {
    final $$TasksTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.dependentTaskId,
        referencedTable: $db.tasks,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TasksTableOrderingComposer(
              $db: $db,
              $table: $db.tasks,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$TaskDependenciesTableAnnotationComposer
    extends Composer<_$ChatDatabase, $TaskDependenciesTable> {
  $$TaskDependenciesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$TasksTableAnnotationComposer get taskId {
    final $$TasksTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.taskId,
        referencedTable: $db.tasks,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TasksTableAnnotationComposer(
              $db: $db,
              $table: $db.tasks,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$TasksTableAnnotationComposer get dependentTaskId {
    final $$TasksTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.dependentTaskId,
        referencedTable: $db.tasks,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TasksTableAnnotationComposer(
              $db: $db,
              $table: $db.tasks,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$TaskDependenciesTableTableManager extends RootTableManager<
    _$ChatDatabase,
    $TaskDependenciesTable,
    TaskDependency,
    $$TaskDependenciesTableFilterComposer,
    $$TaskDependenciesTableOrderingComposer,
    $$TaskDependenciesTableAnnotationComposer,
    $$TaskDependenciesTableCreateCompanionBuilder,
    $$TaskDependenciesTableUpdateCompanionBuilder,
    (TaskDependency, $$TaskDependenciesTableReferences),
    TaskDependency,
    PrefetchHooks Function({bool taskId, bool dependentTaskId})> {
  $$TaskDependenciesTableTableManager(
      _$ChatDatabase db, $TaskDependenciesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TaskDependenciesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TaskDependenciesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TaskDependenciesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> taskId = const Value.absent(),
            Value<int> dependentTaskId = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              TaskDependenciesCompanion(
            taskId: taskId,
            dependentTaskId: dependentTaskId,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required int taskId,
            required int dependentTaskId,
            Value<int> rowid = const Value.absent(),
          }) =>
              TaskDependenciesCompanion.insert(
            taskId: taskId,
            dependentTaskId: dependentTaskId,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$TaskDependenciesTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({taskId = false, dependentTaskId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (taskId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.taskId,
                    referencedTable:
                        $$TaskDependenciesTableReferences._taskIdTable(db),
                    referencedColumn:
                        $$TaskDependenciesTableReferences._taskIdTable(db).id,
                  ) as T;
                }
                if (dependentTaskId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.dependentTaskId,
                    referencedTable: $$TaskDependenciesTableReferences
                        ._dependentTaskIdTable(db),
                    referencedColumn: $$TaskDependenciesTableReferences
                        ._dependentTaskIdTable(db)
                        .id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$TaskDependenciesTableProcessedTableManager = ProcessedTableManager<
    _$ChatDatabase,
    $TaskDependenciesTable,
    TaskDependency,
    $$TaskDependenciesTableFilterComposer,
    $$TaskDependenciesTableOrderingComposer,
    $$TaskDependenciesTableAnnotationComposer,
    $$TaskDependenciesTableCreateCompanionBuilder,
    $$TaskDependenciesTableUpdateCompanionBuilder,
    (TaskDependency, $$TaskDependenciesTableReferences),
    TaskDependency,
    PrefetchHooks Function({bool taskId, bool dependentTaskId})>;

class $ChatDatabaseManager {
  final _$ChatDatabase _db;
  $ChatDatabaseManager(this._db);
  $$AssestsTableTableManager get assests =>
      $$AssestsTableTableManager(_db, _db.assests);
  $$ChannelsTableTableManager get channels =>
      $$ChannelsTableTableManager(_db, _db.channels);
  $$ContactsTableTableManager get contacts =>
      $$ContactsTableTableManager(_db, _db.contacts);
  $$MembersTableTableManager get members =>
      $$MembersTableTableManager(_db, _db.members);
  $$MessagesTableTableManager get messages =>
      $$MessagesTableTableManager(_db, _db.messages);
  $$MessageAssetsTableTableManager get messageAssets =>
      $$MessageAssetsTableTableManager(_db, _db.messageAssets);
  $$UserProfilesTableTableManager get userProfiles =>
      $$UserProfilesTableTableManager(_db, _db.userProfiles);
  $$TasksTableTableManager get tasks =>
      $$TasksTableTableManager(_db, _db.tasks);
  $$TaskDependenciesTableTableManager get taskDependencies =>
      $$TaskDependenciesTableTableManager(_db, _db.taskDependencies);
}
