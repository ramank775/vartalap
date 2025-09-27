class PreviewImage {
  final String id;
  final String uri;
  const PreviewImage({required this.id, required this.uri});

  @override
  int get hashCode => id.hashCode;

  @override
  bool operator ==(Object other) {
    return hashCode == other.hashCode;
  }
}
