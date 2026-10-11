import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vartalap/utils/countries.dart';

/// Preference key for the remembered country (ISO 3166-1 alpha-2): the
/// login screen saves it on Next, the contact matcher reads its dial code.
const String kCountryIsoPrefKey = 'country_iso';
const String kDefaultCountryIso = 'IN';
const String kDefaultCountryCode = '+91';

/// The remembered country, else the SIM's (like WhatsApp), else India.
Future<Country> defaultCountry() async {
  final prefs = await SharedPreferences.getInstance();
  final saved = countryForIso(prefs.getString(kCountryIsoPrefKey));
  if (saved != null) return saved;
  // The channel lives in Android's MainActivity only.
  if (Platform.isAndroid) {
    try {
      final sim = await const MethodChannel('vartalap/sim')
          .invokeMethod<String>('countryIso');
      final fromSim = countryForIso(sim);
      if (fromSim != null) return fromSim;
    } catch (_) {}
  }
  return countryForIso(kDefaultCountryIso)!;
}

/// E.164 pattern: `+` followed by 7-15 digits, first digit non-zero.
final RegExp _e164Pattern = RegExp(r'^\+[1-9]\d{6,14}$');

/// Whether [phone] is a plausible E.164 number, used to gate "Send OTP".
bool isValidE164(String phone) => _e164Pattern.hasMatch(phone);

/// `countryCode` defaults to [kDefaultCountryCode] for callers (e.g. the
/// device address-book matcher in new_chat.dart) that normalize local
/// numbers without an explicit code. The login screen instead passes the
/// user's own remembered country-code field.
String? normalizePhoneNumber(String phoneNumber,
    {String countryCode = kDefaultCountryCode}) {
  // Drop the separators people type or paste: spaces, dashes, dots, brackets.
  phoneNumber = phoneNumber.replaceAll(RegExp(r'[\s\-.()]'), '');
  // Check if it's a valid phone number by parsing the string into integer
  if (int.tryParse(phoneNumber) == null) {
    return null;
  }

  // Check if number starts with 0, i.e. it's a local number replace 0 with country code
  // else if the number doesn't start's with + append the country code
  if (phoneNumber.startsWith('0')) {
    phoneNumber = countryCode + phoneNumber.substring(1);
  } else if (!phoneNumber.startsWith('+')) {
    phoneNumber = countryCode + phoneNumber;
  }
  return phoneNumber;
}
