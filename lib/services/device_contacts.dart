/// The phone's address book, read for contact discovery.
library vartalap.services.device_contacts;

import 'package:flutter_contacts/flutter_contacts.dart' hide PermissionStatus;
import 'package:permission_handler/permission_handler.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/utils/phone_number.dart';

/// Walks the device address book once and returns:
///   * `phones` — every readable normalized E.164 phone (input to the
///     hashed lookup).
///   * `names` — phone → contact-book label, only when the address
///     book actually has a non-empty name. The name wins display
///     priority over username/userId per AUTH_CONTRACT §2.4 — without
///     this map, the UI falls back to whatever the server returned
///     (username) and unfortunately to user_id when even that is
///     missing.
Future<(List<String>, Map<String, String>)> readDeviceContacts() async {
  final contacts = await FlutterContacts.getAll(
    properties: {ContactProperty.phone, ContactProperty.name},
  );
  final phones = <String>{};
  final names = <String, String>{};
  // Local numbers (no +) take the user's own country, not a fixed +91.
  final countryCode = '+${(await defaultCountry()).dialCode}';
  for (final c in contacts) {
    final dn = c.displayName?.trim() ?? '';
    final fn = c.name?.first?.trim() ?? '';
    final label = dn.isNotEmpty ? dn : (fn.isNotEmpty ? fn : null);
    for (final p in c.phones) {
      final raw = (p.normalizedNumber?.isNotEmpty ?? false)
          ? p.normalizedNumber!
          : p.number;
      final normalized = normalizePhoneNumber(raw, countryCode: countryCode);
      if (normalized == null) continue;
      phones.add(normalized);
      if (label != null) names.putIfAbsent(normalized, () => label);
    }
  }
  return (phones.toList(), names);
}

/// Looks the address book up at app start, so someone who just joined
/// shows without opening Contacts. Never asks for the permission.
Future<void> syncDeviceContacts(ChatService chat) async {
  if (!await Permission.contacts.isGranted) return;
  final (phones, names) = await readDeviceContacts();
  await chat.discoverContacts(
    normalizedPhones: phones,
    contactBookNamesByPhone: names,
  );
}
