class MessageSpacer {
  final double height;
  final int id;
  const MessageSpacer({
    required this.height,
    required this.id,
  });

  @override
  int get hashCode => id.hashCode;

  @override
  bool operator ==(Object other) {
    return hashCode == other.hashCode;
  }
}
