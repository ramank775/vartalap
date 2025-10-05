class Profile {
  final String userId;
  final String name;
  final String email;
  final String image;

  Profile({
    required this.userId,
    required this.name,
    required this.email,
    required this.image,
  });

  // Constructor for Drift database
  Profile.fromDb({
    required this.userId,
    required this.name,
    required this.email,
    required this.image,
    DateTime? updatedAt, // ignored but needed for Drift
  });

  @override
  String toString() {
    return 'Profile(userId: $userId, name: $name, email: $email, image: $image)';
  }
}
