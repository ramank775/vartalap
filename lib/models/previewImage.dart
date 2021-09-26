class PreviewImage {
  final String id;
  final String uri;
  const PreviewImage({required this.id, required this.uri});

  int get hashCode => this.id.hashCode;

  @override
  bool operator ==(Object other) {
    return hashCode == other.hashCode;
  }
}
