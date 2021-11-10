class MessageSpacer {
  final double height;
  final String id;
  const MessageSpacer({
    required this.height,
    required this.id,
  });

  int get hashCode => this.id.hashCode;

  @override
  bool operator ==(Object other) {
    return hashCode == other.hashCode;
  }
}
