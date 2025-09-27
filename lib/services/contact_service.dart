import 'package:flutter_contacts/flutter_contacts.dart' as fc;
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';

class ContactService {
  /// Fetches contacts from the device and converts them to app's Contact model
  static Future<List<Contact>> fetchDeviceContacts() async {
    try {
      // Check if permission is granted
      if (!await fc.FlutterContacts.requestPermission(readonly: true)) {
        return [];
      }

      // Fetch contacts from device
      final deviceContacts = await fc.FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: true,
      );

      // Convert to app's Contact model
      final List<Contact> appContacts = [];
      for (int i = 0; i < deviceContacts.length; i++) {
        final deviceContact = deviceContacts[i];
        
        // Only add contacts that have at least one phone number
        if (deviceContact.phones.isNotEmpty) {
          final contact = Contact(
            id: i, // Using index as id since device contacts don't have persistent IDs
            username: null, // Device contacts don't have usernames
            uid: null,
            phone: deviceContact.phones.first.number,
            name: deviceContact.displayName.isNotEmpty ? deviceContact.displayName : null,
            thumbnail: deviceContact.photo,
            photo: null,
            extraData: null,
            status: ContactStatus.unknown, // Default status for device contacts
          );
          appContacts.add(contact);
        }
      }

      return appContacts;
    } catch (e) {
      // Return empty list if there's any error
      return [];
    }
  }
}