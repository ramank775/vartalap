import 'package:drift/drift.dart';
import 'package:vartalap_messaging_flutter/db/chat_db.dart';
import 'package:vartalap_messaging_flutter/entity/entity.dart';
import 'package:vartalap_messaging_flutter/models/models.dart';

part 'user_profile_dao.g.dart';

/// UserProfileDao - User Profile Operations
///
/// RESPONSIBILITIES:
/// - Store and retrieve the logged-in user's profile
/// - Enable offline authentication state persistence
/// - Support profile updates
///
/// USAGE:
/// ```dart
/// // Store user profile after login
/// await userProfileDao.saveProfile(profile);
///
/// // Retrieve profile offline
/// final profile = await userProfileDao.getProfile(userId);
/// ```
@DriftAccessor(tables: [UserProfiles])
class UserProfileDao extends DatabaseAccessor<ChatDatabase>
    with _$UserProfileDaoMixin {
  UserProfileDao(super.db);

  /// Get the user profile by userId
  Future<Profile?> getProfile(String userId) async {
    return await (select(userProfiles)
          ..where((tbl) => tbl.userId.equals(userId)))
        .getSingleOrNull();
  }

  /// Save or update the user profile
  Future<void> saveProfile(Profile profile) async {
    await into(userProfiles).insertOnConflictUpdate(
      UserProfilesCompanion.insert(
        userId: profile.userId,
        name: profile.name,
        email: profile.email,
        image: profile.image,
        updatedAt: DateTime.now(),
      ),
    );
  }

  /// Delete the user profile
  Future<void> deleteProfile(String userId) async {
    await (delete(userProfiles)..where((tbl) => tbl.userId.equals(userId)))
        .go();
  }
}
