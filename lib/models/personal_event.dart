class PersonalEvent {
  final int? id;
  final String username;
  final DateTime date;
  final DateTime? endDate;
  final String title;
  final String? remarks;
  final DateTime? createdAt;

  PersonalEvent({
    this.id,
    required this.username,
    required this.date,
    this.endDate,
    required this.title,
    this.remarks,
    this.createdAt,
  });

  factory PersonalEvent.fromJson(Map<String, dynamic> json) {
    return PersonalEvent(
      id: json['id'],
      username: json['username'],
      date: DateTime.parse(json['date']),
      endDate: json['end_date'] != null ? DateTime.parse(json['end_date']) : null,
      title: json['title'],
      remarks: json['remarks'],
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'username': username,
      'date': '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      'end_date': endDate != null
          ? '${endDate!.year}-${endDate!.month.toString().padLeft(2, '0')}-${endDate!.day.toString().padLeft(2, '0')}'
          : null,
      'title': title,
      'remarks': remarks,
    };
  }
}
