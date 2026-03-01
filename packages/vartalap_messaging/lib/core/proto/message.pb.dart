// Protobuf serialization for the chat-server Message format.
// Based on proto/event-args.proto from chat-server.
//
// This uses direct wire-format encoding rather than GeneratedMessage
// to avoid requiring protoc code generation.
//
// ignore_for_file: constant_identifier_names

import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:protobuf/protobuf.dart';

/// Message.Type enum values from proto
class ProtoMessageType {
  static const int SERVER_ACK = 0;
  static const int CLIENT_ACK = 1;
  static const int MESSAGE = 2;
  static const int NOTIFICATION = 3;
  static const int CUSTOM = 10;
}

/// Message.Channel enum values from proto
class ProtoChannelType {
  static const int UNKNOWN = 0;
  static const int INDIVIDUAL = 1;
  static const int GROUP = 2;
  static const int OTHER = 10;
}

/// Dart representation of the proto Message, with manual encode/decode.
///
/// Proto field numbers:
///   1: version (float)
///   2: id (string)
///   3: type (enum)
///   4: channel (enum)
///   5: ephemeral (bool)
///   6: source (string)
///   7: destination (string)
///   8: content (bytes)
///   9: timestamp (uint64)
///  10: meta (map of string to string) — encoded as repeated embedded message
///  11: recipients (repeated string)
///  20: serverId (string)
///  21: serverTimestamp (uint64)
class ProtoMessage {
  double version;
  String id;
  int type;
  int channel;
  bool ephemeral;
  String source;
  String destination;
  Uint8List? content;
  Int64 timestamp;
  Map<String, String> meta;
  List<String> recipients;
  String? serverId;
  Int64? serverTimestamp;

  ProtoMessage({
    this.version = 2.1,
    this.id = '',
    this.type = ProtoMessageType.MESSAGE,
    this.channel = ProtoChannelType.UNKNOWN,
    this.ephemeral = false,
    this.source = '',
    this.destination = '',
    this.content,
    Int64? timestamp,
    Map<String, String>? meta,
    List<String>? recipients,
    this.serverId,
    this.serverTimestamp,
  })  : timestamp = timestamp ?? Int64.ZERO,
        meta = meta ?? {},
        recipients = recipients ?? [];

  /// Encode to protobuf binary wire format.
  Uint8List writeToBuffer() {
    final writer = CodedBufferWriter();

    // 1: version (float) — wire type 5 (32-bit)
    if (version != 0.0) {
      writer.writeField(1, PbFieldType.OF, version);
    }

    // 2: id (string) — wire type 2 (length-delimited)
    if (id.isNotEmpty) {
      writer.writeField(2, PbFieldType.OS, id);
    }

    // 3: type (enum) — wire type 0 (varint)
    if (type != 0) {
      writer.writeField(3, PbFieldType.OE, type);
    }

    // 4: channel (enum) — wire type 0 (varint)
    if (channel != 0) {
      writer.writeField(4, PbFieldType.OE, channel);
    }

    // 5: ephemeral (bool) — wire type 0 (varint)
    if (ephemeral) {
      writer.writeField(5, PbFieldType.OB, ephemeral);
    }

    // 6: source (string)
    if (source.isNotEmpty) {
      writer.writeField(6, PbFieldType.OS, source);
    }

    // 7: destination (string)
    if (destination.isNotEmpty) {
      writer.writeField(7, PbFieldType.OS, destination);
    }

    // 8: content (bytes)
    if (content != null && content!.isNotEmpty) {
      writer.writeField(8, PbFieldType.OY, content);
    }

    // 9: timestamp (uint64)
    if (timestamp != Int64.ZERO) {
      writer.writeField(9, PbFieldType.OU6, timestamp);
    }

    // 10: meta (map<string, string>) — each entry is a sub-message with fields 1,2
    for (final entry in meta.entries) {
      final subWriter = CodedBufferWriter();
      subWriter.writeField(1, PbFieldType.OS, entry.key);
      subWriter.writeField(2, PbFieldType.OS, entry.value);
      final subBytes = subWriter.toBuffer();
      // Tag for field 10, wire type 2 (length-delimited)
      writer.writeField(10, PbFieldType.OY, subBytes);
    }

    // 11: recipients (repeated string)
    for (final r in recipients) {
      writer.writeField(11, PbFieldType.OS, r);
    }

    // 20: serverId (string)
    if (serverId != null && serverId!.isNotEmpty) {
      writer.writeField(20, PbFieldType.OS, serverId);
    }

    // 21: serverTimestamp (uint64)
    if (serverTimestamp != null && serverTimestamp != Int64.ZERO) {
      writer.writeField(21, PbFieldType.OU6, serverTimestamp);
    }

    return writer.toBuffer();
  }

  /// Decode from protobuf binary wire format.
  static ProtoMessage fromBuffer(Uint8List data) {
    final msg = ProtoMessage();
    final reader = CodedBufferReader(data);

    while (!reader.isAtEnd()) {
      final tag = reader.readTag();
      final fieldNumber = getTagFieldNumber(tag);
      // wireType is implicit in the reader — we switch on field number
      getTagWireType(tag); // consume but rely on reader to handle wire type

      switch (fieldNumber) {
        case 1: // version (float)
          msg.version = reader.readFloat();
          break;
        case 2: // id (string)
          msg.id = reader.readString();
          break;
        case 3: // type (enum as varint)
          msg.type = reader.readEnum();
          break;
        case 4: // channel (enum as varint)
          msg.channel = reader.readEnum();
          break;
        case 5: // ephemeral (bool)
          msg.ephemeral = reader.readBool();
          break;
        case 6: // source (string)
          msg.source = reader.readString();
          break;
        case 7: // destination (string)
          msg.destination = reader.readString();
          break;
        case 8: // content (bytes)
          msg.content = Uint8List.fromList(reader.readBytes());
          break;
        case 9: // timestamp (uint64)
          msg.timestamp = reader.readInt64();
          break;
        case 10: // meta map entry (sub-message)
          _readMetaEntry(reader, msg.meta);
          break;
        case 11: // recipients (string)
          msg.recipients.add(reader.readString());
          break;
        case 20: // serverId (string)
          msg.serverId = reader.readString();
          break;
        case 21: // serverTimestamp (uint64)
          msg.serverTimestamp = reader.readInt64();
          break;
        default:
          // Skip unknown fields
          reader.readUnknownFieldSetGroup(fieldNumber);
          break;
      }
    }

    return msg;
  }

  /// Read a map-of-string-to-string entry sub-message.
  static void _readMetaEntry(
      CodedBufferReader reader, Map<String, String> meta) {
    final bytes = reader.readBytes();
    final subReader = CodedBufferReader(bytes);
    String key = '';
    String value = '';
    while (!subReader.isAtEnd()) {
      final subTag = subReader.readTag();
      final subField = getTagFieldNumber(subTag);
      switch (subField) {
        case 1:
          key = subReader.readString();
          break;
        case 2:
          value = subReader.readString();
          break;
        default:
          subReader.readUnknownFieldSetGroup(subField);
          break;
      }
    }
    if (key.isNotEmpty) {
      meta[key] = value;
    }
  }
}
