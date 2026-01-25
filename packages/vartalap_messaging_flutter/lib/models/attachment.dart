class Attachment {
  final int id;
  final String? remoteId;
  final String name;
  final String type; // mime type
  final String category; // image, video, document, etc.
  final String path;
  final DateTime createdAt;
  final DateTime updatedAt;

  Attachment({
    required this.id,
    this.remoteId,
    required this.name,
    required this.type,
    required this.category,
    required this.path,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();
}
