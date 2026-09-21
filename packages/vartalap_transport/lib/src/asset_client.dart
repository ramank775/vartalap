import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'auth_client.dart' show AuthClientException;
import 'auth_token_provider.dart';

/// media-ms presigned upload / download — V3_RELEASE_PLAN §4.2,
/// decisions 8, 22, 36. Three authenticated routes plus the plain
/// (already-signed) object-store PUT/GET:
///
///   GET  /v3.0/assets/upload/presigned_url?ext&category&size
///   PUT  <signed url>                     (content-type + length signed)
///   PUT  /v3.0/assets/{fileId}/status     {"status": true}
///   GET  /v3.0/assets/download/{fileId}/presigned_url
///
/// Separate from [AuthClient] because none of this is AUTH_CONTRACT and
/// none of it needs the session-management state that class carries —
/// only a bearer token, which [AuthTokenProvider] supplies.
class AssetClient {
  final Uri baseUrl;
  final AuthTokenProvider auth;
  final http.Client _client;
  final bool _ownsClient;

  /// media-ms rejects anything larger (decision 36).
  static const int maxUploadBytes = 25 * 1024 * 1024;

  AssetClient({
    required this.baseUrl,
    required this.auth,
    http.Client? httpClient,
  })  : _client = httpClient ?? http.Client(),
        _ownsClient = httpClient == null;

  void dispose() {
    if (_ownsClient) _client.close();
  }

  Map<String, String> _headers() {
    final key = auth.currentAccesskey;
    if (key == null) {
      throw StateError('AssetClient: no accesskey — not signed in');
    }
    return {'Authorization': 'Bearer $key', 'Accept': 'application/json'};
  }

  /// Reserve a fileId and get the signed PUT url. [ext] is the bare
  /// extension (`png`, not `.png`) — the server maps it to the
  /// content-type it signs, so [putBytes] must send that same type.
  Future<PresignedUpload> presignUpload({
    required String ext,
    required String category,
    required int size,
  }) async {
    final uri = baseUrl.resolve('/v3.0/assets/upload/presigned_url').replace(
      queryParameters: {
        'ext': ext,
        'category': category,
        'size': '$size',
      },
    );
    final resp = await _client.get(uri, headers: _headers());
    _assertOk(resp, 'presignUpload');
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return PresignedUpload(
      url: json['url'] as String,
      fileId: json['fileId'] as String,
    );
  }

  /// The signed PUT. No Authorization header — the signature is the
  /// authorization, and an extra bearer token can invalidate it on real
  /// object stores.
  Future<void> putBytes({
    required String url,
    required List<int> bytes,
    required String contentType,
  }) async {
    final resp = await _client.put(
      Uri.parse(url),
      headers: {
        'Content-Type': contentType,
        'Content-Length': '${bytes.length}',
      },
      body: bytes,
    );
    _assertOk(resp, 'putBytes');
  }

  /// Flip the record to "upload complete". Owner-scoped: 404 for
  /// anyone else, 400 if it was already marked.
  Future<void> markUploaded(String fileId) async {
    final resp = await _client.put(
      baseUrl.resolve('/v3.0/assets/$fileId/status'),
      headers: {..._headers(), 'Content-Type': 'application/json'},
      body: jsonEncode({'status': true}),
    );
    _assertOk(resp, 'markUploaded');
  }

  /// Any authenticated user holding the (unguessable) fileId may
  /// download — the id is the capability.
  Future<String> downloadUrl(String fileId) async {
    final resp = await _client.get(
      baseUrl.resolve('/v3.0/assets/download/$fileId/presigned_url'),
      headers: _headers(),
    );
    _assertOk(resp, 'downloadUrl');
    return (jsonDecode(resp.body) as Map<String, dynamic>)['url'] as String;
  }

  /// GET a signed download url. Unsigned on purpose, same reason as
  /// [putBytes].
  Future<Uint8List> download(String url) async {
    final resp = await _client.get(Uri.parse(url));
    _assertOk(resp, 'download');
    return resp.bodyBytes;
  }

  void _assertOk(http.Response resp, String method) {
    if (resp.statusCode >= 200 && resp.statusCode < 300) return;
    String? code;
    try {
      final err = (jsonDecode(resp.body) as Map<String, dynamic>)['error'];
      if (err is Map<String, dynamic>) code = err['code'] as String?;
    } catch (_) {
      // Non-JSON body (object store XML, proxy HTML) — status stands.
    }
    throw AuthClientException(method, resp.statusCode, code, null);
  }
}

class PresignedUpload {
  final String url;
  final String fileId;
  const PresignedUpload({required this.url, required this.fileId});
}
