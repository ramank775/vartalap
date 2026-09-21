/// Preference key for the remembered country code (§4.7 plumbing — the
/// login screen's country-code field persists here; new users default to
/// [kDefaultCountryCode]).
const String kCountryCodePrefKey = 'country_code';
const String kDefaultCountryCode = '+91';

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
  // Remove space
  phoneNumber = phoneNumber.replaceAll(' ', '');
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
