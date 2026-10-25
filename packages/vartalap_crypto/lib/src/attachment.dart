import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'e2ee.dart';

/// Decisions 188 and 190: an attachment is encrypted on the sending phone,
/// convergently: its key is a hash of the file and its nonce a hash of the
/// key, so the same file always seals to the same bytes and the server
/// stores it once. The object holds version, nonce, ChaCha20-Poly1305
/// ciphertext and tag; the key travels in the `#fragment` of
/// `Attachment.url`, which only exists inside the encrypted message.
/// The owner accepted the cost: someone holding a file can tell whether
/// the server has it, and see who fetches it (decision 190).
const int sealedAttachmentOverhead = 1 + 12 + 16;

Uint8List _sha256(String tag, Uint8List data) {
  final digest = SHA256Digest()..update(utf8.encode(tag), 0, tag.length);
  digest.update(data, 0, data.length);
  final out = Uint8List(32);
  digest.doFinal(out, 0);
  return out;
}

/// The key, and the sealed bytes, for [plain].
/// ponytail: one AEAD pass over the whole file, held in memory; fine at the
/// 25 MB upload cap. Chunk it if the cap ever grows.
({Uint8List key, Uint8List sealed}) sealAttachment(Uint8List plain) {
  final key = _sha256('vartalap media key v2', plain);
  final nonce = _sha256('vartalap media nonce v2', key).sublist(0, 12);
  return (
    key: key,
    sealed: Uint8List.fromList(
        [2, ...nonce, ...chaCha20Poly1305(true, key, nonce, Uint8List(0), plain)]),
  );
}

/// Throws when [sealed] was not made with [key] or was changed. Version 1
/// (a random key, before decision 190) opens the same way.
Uint8List openSealedAttachment(Uint8List key, Uint8List sealed) {
  if (sealed.length < sealedAttachmentOverhead ||
      (sealed[0] != 1 && sealed[0] != 2)) {
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
