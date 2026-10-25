import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'e2ee.dart';

/// Decision 188: an attachment is encrypted on the sending phone with a key
/// of its own. The object store holds version, nonce, ChaCha20-Poly1305
/// ciphertext and tag; the key travels in the `#fragment` of
/// `Attachment.url`, which only exists inside the encrypted message, so
/// neither the server nor the bucket ever sees it.
const int sealedAttachmentOverhead = 1 + 12 + 16;

Uint8List _random(int length) {
  final random = Random.secure();
  return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
}

Uint8List newAttachmentKey() => _random(32);

/// ponytail: one AEAD pass over the whole file, held in memory; fine at the
/// 25 MB upload cap. Chunk it if the cap ever grows.
Uint8List sealAttachment(Uint8List key, Uint8List plain) {
  final nonce = _random(12);
  return Uint8List.fromList(
      [1, ...nonce, ...chaCha20Poly1305(true, key, nonce, Uint8List(0), plain)]);
}

/// Throws when [sealed] was not made with [key] or was changed.
Uint8List openSealedAttachment(Uint8List key, Uint8List sealed) {
  if (sealed.length < sealedAttachmentOverhead || sealed[0] != 1) {
    throw const FormatException('Not an encrypted attachment');
  }
  return chaCha20Poly1305(
      false, key, sealed.sublist(1, 13), Uint8List(0), sealed.sublist(13));
}

String attachmentUrl(String fileId, Uint8List key) =>
    '$fileId#${base64Url.encode(key)}';

/// The object to fetch and, for an encrypted attachment, its key.
({String object, Uint8List? key}) parseAttachmentUrl(String url) {
  final hash = url.indexOf('#');
  if (hash < 0) return (object: url, key: null);
  return (
    object: url.substring(0, hash),
    key: base64Url.decode(url.substring(hash + 1)),
  );
}
