// HACK: Currently as this app is intended to work for indian user's only
// use +91 as default country code
String? normalizePhoneNumber(String phoneNumber, {String countryCode = '+91'}) {
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
