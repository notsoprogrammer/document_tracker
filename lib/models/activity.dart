class Activity {
  final int? id; // Primary key for SQLite
  final String? title;
  final DateTime startTime;
  final DateTime? endTime;
  final String peopleInvolved;
  final String remarks;
  final String person;
  final String? location;
  bool needsSync;
  final DateTime? createdAt;

  Activity({
    this.id,
    this.title,
    required this.startTime,
    this.endTime,
    required this.peopleInvolved,
    required this.remarks,
    required this.person,
    this.location,
    this.needsSync = false,
    this.createdAt,
  });

  factory Activity.fromJson(Map<String, dynamic> json) {
    return Activity(
      id: json['id'],
      title: json['title'],
      startTime: DateTime.parse(json['start_time']),
      endTime: json['end_time'] != null ? DateTime.parse(json['end_time']) : null,
      peopleInvolved: json['people_involved'],
      remarks: json['remarks'],
      person: json['person'],
      location: json['location'],
      needsSync: json['needs_sync'] == 1 || json['needs_sync'] == true,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime?.toIso8601String(),
      'people_involved': peopleInvolved,
      'remarks': remarks,
      'person': person,
      'location': location,
      'needs_sync': needsSync,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  Activity copyWith({
    int? id,
    String? title,
    DateTime? startTime,
    DateTime? endTime,
    String? peopleInvolved,
    String? remarks,
    String? person,
    String? location,
    bool? needsSync,
    DateTime? createdAt,
  }) {
    return Activity(
      id: id ?? this.id,
      title: title ?? this.title,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      peopleInvolved: peopleInvolved ?? this.peopleInvolved,
      remarks: remarks ?? this.remarks,
      person: person ?? this.person,
      location: location ?? this.location,
      needsSync: needsSync ?? this.needsSync,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
