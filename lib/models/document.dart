class HistoryEntry {
  final String action;
  final String person;
  final DateTime timestamp;
  final String? notes;
  final String? personnel;

  HistoryEntry({
    required this.action,
    required this.person,
    required this.timestamp,
    this.notes,
    this.personnel,
  });

  factory HistoryEntry.fromJson(Map<String, dynamic> json) {
    return HistoryEntry(
      action: json['action'],
      person: json['person'],
      timestamp: DateTime.parse(json['timestamp']),
      notes: json['notes'],
      personnel: json['personnel'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'action': action,
      'person': person,
      'timestamp': timestamp.toIso8601String(),
      'notes': notes,
      'personnel': personnel,
    };
  }
}

class Document {
  final String code;
  final String title;
  final String type;
  final String fromOrTo;
  final String mode;
  String assignedTo;
  final String? filePath;
  final String remarks;
  final String person;
  final bool incoming;
  final List<HistoryEntry> history;
  String status;

  Document({
    required this.code,
    required this.title,
    required this.type,
    required this.fromOrTo,
    required this.mode,
    required this.assignedTo,
    this.filePath,
    required this.remarks,
    required this.person,
    required this.incoming,
    List<HistoryEntry>? history,
    this.status = 'Received',
  }) : history = history ?? [];

  void addHistoryEntry(String action, String person, {String? notes, String? personnel}) {
    history.add(HistoryEntry(
      action: action,
      person: person,
      timestamp: DateTime.now(),
      notes: notes,
      personnel: personnel,
    ));
  }

  void transferTo(String newAssignee, String transferredBy, {String? notes}) {
    addHistoryEntry('Transferred to $newAssignee', transferredBy, notes: notes);
    assignedTo = newAssignee;
  }

  void updateStatus(String newStatus, String updatedBy, {String? notes}) {
    addHistoryEntry('Status changed to $newStatus', updatedBy, notes: notes);
    status = newStatus;
  }

  factory Document.fromJson(Map<String, dynamic> json) {
    return Document(
      code: json['code'],
      title: json['title'],
      type: json['type'],
      fromOrTo: json['from_or_to'],
      mode: json['mode'],
      assignedTo: json['addressed_to'],
      filePath: json['file_path'],
      remarks: json['remarks'],
      person: json['person'],
      incoming: json['incoming'],
      status: json['status'],
      history: (json['history'] as List<dynamic>?)
          ?.map((entry) => HistoryEntry.fromJson(entry))
          .toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'title': title,
      'type': type,
      'from_or_to': fromOrTo,
      'mode': mode,
      'addressed_to': assignedTo,
      'file_path': filePath,
      'remarks': remarks,
      'person': person,
      'incoming': incoming,
      'status': status,
    };
  }
}
