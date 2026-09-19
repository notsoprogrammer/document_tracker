import 'dart:convert';
import 'note.dart';

class Activity {
  final int? id;
  final String? title;
  final DateTime startTime;
  final DateTime? endTime;
  final String peopleInvolved;
  final String remarks;
  /// Append-only notes thread. Anyone may add a note; only its author may edit
  /// or delete it. The legacy single [remarks] text is folded in as the first
  /// note when this list is empty.
  final List<Note> remarksList;
  final String person;
  final String? location;
  bool needsSync;
  final DateTime? createdAt;
  final List<DateTime> extraDates;
  final String? linkedDocumentCode;

  Activity({
    this.id,
    this.title,
    required this.startTime,
    this.endTime,
    required this.peopleInvolved,
    required this.remarks,
    List<Note>? remarksList,
    required this.person,
    this.location,
    this.needsSync = false,
    this.createdAt,
    this.extraDates = const [],
    this.linkedDocumentCode,
  }) : remarksList = remarksList ?? const [];

  factory Activity.fromJson(Map<String, dynamic> json) {
    List<DateTime> extraDates = [];
    if (json['extra_dates'] != null) {
      dynamic raw = json['extra_dates'];
      if (raw is String) {
        try { raw = jsonDecode(raw) as List<dynamic>; } catch (_) { raw = <dynamic>[]; }
      }
      if (raw is List) {
        extraDates = raw.map((e) => DateTime.parse(e.toString())).toList();
      }
    }
    return Activity(
      id: json['id'],
      title: json['title'],
      startTime: DateTime.parse(json['start_time']),
      endTime: json['end_time'] != null ? DateTime.parse(json['end_time']) : null,
      peopleInvolved: json['people_involved'],
      remarks: json['remarks'],
      remarksList: Note.parseList(
        json['remarks_list'],
        legacyRemarks: json['remarks']?.toString(),
        legacyDate: json['created_at'] != null
            ? DateTime.tryParse(json['created_at'].toString())
            : null,
      ),
      person: json['person'],
      location: json['location'],
      needsSync: json['needs_sync'] == 1 || json['needs_sync'] == true,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
      extraDates: extraDates,
      linkedDocumentCode: json['linked_document_code'],
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
      'remarks_list': Note.listToJson(remarksList),
      'person': person,
      'location': location,
      'needs_sync': needsSync,
      'created_at': createdAt?.toIso8601String(),
      'extra_dates': extraDates.map((d) => d.toIso8601String()).toList(),
      'linked_document_code': linkedDocumentCode,
    };
  }

  Activity copyWith({
    int? id,
    String? title,
    DateTime? startTime,
    DateTime? endTime,
    String? peopleInvolved,
    String? remarks,
    List<Note>? remarksList,
    String? person,
    String? location,
    bool? needsSync,
    DateTime? createdAt,
    List<DateTime>? extraDates,
    String? linkedDocumentCode,
  }) {
    return Activity(
      id: id ?? this.id,
      title: title ?? this.title,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      peopleInvolved: peopleInvolved ?? this.peopleInvolved,
      remarks: remarks ?? this.remarks,
      remarksList: remarksList ?? this.remarksList,
      person: person ?? this.person,
      location: location ?? this.location,
      needsSync: needsSync ?? this.needsSync,
      createdAt: createdAt ?? this.createdAt,
      extraDates: extraDates ?? this.extraDates,
      linkedDocumentCode: linkedDocumentCode ?? this.linkedDocumentCode,
    );
  }
}
