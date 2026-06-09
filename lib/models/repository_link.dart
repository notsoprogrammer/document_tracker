class RepositoryLink {
  final int? id;
  final String title;
  final String driveLink;
  final String description;
  final String addedBy;
  final DateTime addedAt;
  bool needsSync;

  RepositoryLink({
    this.id,
    required this.title,
    required this.driveLink,
    required this.description,
    required this.addedBy,
    required this.addedAt,
    this.needsSync = false,
  });

  factory RepositoryLink.fromJson(Map<String, dynamic> json) {
    return RepositoryLink(
      id: json['id'],
      title: json['title'],
      driveLink: json['drive_link'],
      description: json['description'] ?? '',
      addedBy: json['added_by'],
      addedAt: DateTime.parse(json['added_at']),
      needsSync: json['needs_sync'] == 1 || json['needs_sync'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'drive_link': driveLink,
      'description': description,
      'added_by': addedBy,
      'added_at': addedAt.toIso8601String(),
      'needs_sync': needsSync,
    };
  }

  RepositoryLink copyWith({
    int? id,
    String? title,
    String? driveLink,
    String? description,
    String? addedBy,
    DateTime? addedAt,
    bool? needsSync,
  }) {
    return RepositoryLink(
      id: id ?? this.id,
      title: title ?? this.title,
      driveLink: driveLink ?? this.driveLink,
      description: description ?? this.description,
      addedBy: addedBy ?? this.addedBy,
      addedAt: addedAt ?? this.addedAt,
      needsSync: needsSync ?? this.needsSync,
    );
  }
}
