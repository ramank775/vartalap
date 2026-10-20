import 'dart:convert';

/// Public Signal material only (AUTH_CONTRACT §17). Signature verification and
/// identity trust belong to the client crypto layer, not this JSON boundary.
class E2eePreKey {
  final int id;
  final String publicKey;

  E2eePreKey({required this.id, required this.publicKey}) {
    _keyInt(id, 'id', 0, 0xffffff);
    _keyBytes(publicKey, 'publicKey', 33, signalPublic: true);
  }

  factory E2eePreKey.fromJson(Object? value) {
    final json = _keyObject(value, const ['id', 'publicKey']);
    return E2eePreKey(
      id: _keyInt(json['id'], 'id', 0, 0xffffff),
      publicKey:
          _keyBytes(json['publicKey'], 'publicKey', 33, signalPublic: true),
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'publicKey': publicKey};
}

class E2eeSignedPreKey extends E2eePreKey {
  final String signature;

  E2eeSignedPreKey({
    required super.id,
    required super.publicKey,
    required this.signature,
  }) {
    _keyBytes(signature, 'signature', 64);
  }

  factory E2eeSignedPreKey.fromJson(Object? value) {
    final json = _keyObject(value, const ['id', 'publicKey', 'signature']);
    return E2eeSignedPreKey(
      id: _keyInt(json['id'], 'id', 0, 0xffffff),
      publicKey:
          _keyBytes(json['publicKey'], 'publicKey', 33, signalPublic: true),
      signature: _keyBytes(json['signature'], 'signature', 64),
    );
  }

  @override
  Map<String, dynamic> toJson() => {...super.toJson(), 'signature': signature};
}

class E2eeKeyUpload {
  final String identityKey;
  final int registrationId;
  final E2eeSignedPreKey signedPreKey;
  final List<E2eePreKey> preKeys;

  E2eeKeyUpload({
    required this.identityKey,
    required this.registrationId,
    required this.signedPreKey,
    required List<E2eePreKey> preKeys,
  }) : preKeys = List.unmodifiable(preKeys) {
    _keyBytes(identityKey, 'identityKey', 33, signalPublic: true);
    _keyInt(registrationId, 'registrationId', 1, 16383);
    if (this.preKeys.length > 200 ||
        this.preKeys.map((key) => key.id).toSet().length !=
            this.preKeys.length) {
      throw const FormatException('Invalid or duplicate upload prekeys');
    }
    // A signed prekey must never serialize its signature into the preKeys list.
    if (this.preKeys.any((key) => key is E2eeSignedPreKey)) {
      throw const FormatException(
          'Upload prekeys must be one-time public keys');
    }
  }

  Map<String, dynamic> toJson() => {
        'identityKey': identityKey,
        'registrationId': registrationId,
        'signedPreKey': signedPreKey.toJson(),
        'preKeys': preKeys.map((key) => key.toJson()).toList(),
      };
}

const _bundleFields = [
  'deviceId',
  'generation',
  'identityKey',
  'registrationId',
  'signedPreKey',
];

class E2eeDeviceBundle {
  final String deviceId;
  final String generation;
  final String identityKey;
  final int registrationId;
  final E2eeSignedPreKey signedPreKey;

  E2eeDeviceBundle._fromJson(Map<String, dynamic> json)
      : deviceId = validateE2eeDeviceId(json['deviceId']),
        generation = validateE2eeGeneration(json['generation']),
        identityKey = _keyBytes(json['identityKey'], 'identityKey', 33,
            signalPublic: true),
        registrationId =
            _keyInt(json['registrationId'], 'registrationId', 1, 16383),
        signedPreKey = E2eeSignedPreKey.fromJson(json['signedPreKey']);

  factory E2eeDeviceBundle.fromJson(Object? value) =>
      E2eeDeviceBundle._fromJson(_keyObject(value, _bundleFields));
}

class E2eeKeyPublication {
  final E2eeDeviceBundle bundle;
  final int preKeyCount;

  E2eeKeyPublication._(this.bundle, this.preKeyCount);

  factory E2eeKeyPublication.fromJson(Object? value) {
    final json = _keyObject(value, [..._bundleFields, 'preKeyCount']);
    return E2eeKeyPublication._(E2eeDeviceBundle._fromJson(json),
        _keyInt(json['preKeyCount'], 'preKeyCount', 0, 200));
  }
}

class E2eeKeyClaim {
  final E2eeDeviceBundle bundle;
  final E2eePreKey? preKey;

  E2eeKeyClaim._(this.bundle, this.preKey);

  factory E2eeKeyClaim.fromJson(Object? value) {
    final json = _keyObject(value, [..._bundleFields, 'preKey']);
    return E2eeKeyClaim._(E2eeDeviceBundle._fromJson(json),
        json['preKey'] == null ? null : E2eePreKey.fromJson(json['preKey']));
  }
}

List<E2eeDeviceBundle> decodeE2eeDirectory(Object? value) {
  final json = _keyObject(value, const ['devices']);
  final devices = json['devices'];
  if (devices is! List) {
    throw const FormatException('Invalid device-key directory');
  }
  final bundles = devices.map(E2eeDeviceBundle.fromJson).toList();
  if (bundles.map((bundle) => bundle.deviceId).toSet().length !=
      bundles.length) {
    throw const FormatException('Duplicate device-key directory device');
  }
  return List.unmodifiable(bundles);
}

String validateE2eeDeviceId(Object? value) {
  if (value is! String || value.isEmpty || value.length > 256) {
    throw const FormatException('Invalid device-key deviceId');
  }
  return value;
}

String validateE2eeGeneration(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        caseSensitive: false,
      ).hasMatch(value)) {
    throw const FormatException('Invalid device-key generation');
  }
  return value;
}

Map<String, dynamic> _keyObject(Object? value, List<String> fields) {
  if (value is! Map<String, dynamic> ||
      value.length != fields.length ||
      !fields.every(value.containsKey)) {
    throw const FormatException('Invalid device-key object fields');
  }
  return value;
}

int _keyInt(Object? value, String field, int min, int max) {
  if (value is! int || value < min || value > max) {
    throw FormatException('Invalid device-key $field');
  }
  return value;
}

String _keyBytes(Object? value, String field, int length,
    {bool signalPublic = false}) {
  if (value is! String) throw FormatException('Invalid device-key $field');
  final decoded = base64.decode(value);
  if (decoded.length != length ||
      base64.encode(decoded) != value ||
      (signalPublic && decoded[0] != 5)) {
    throw FormatException('Invalid device-key $field');
  }
  return value;
}
