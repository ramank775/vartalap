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

  @override
  String toString() {
    return 'Profile(userId: $userId, name: $name, email: $email, image: $image)';
  }
}
