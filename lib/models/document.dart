class HistoryEntry {
  final String action;
  final String person;
  final DateTime timestamp;
  final String? notes;

  HistoryEntry({
    required this.action,
    required this.person,
    required this.timestamp,
    this.notes,
  });
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

  void addHistoryEntry(String action, String person, {String? notes}) {
    history.add(HistoryEntry(
      action: action,
      person: person,
      timestamp: DateTime.now(),
      notes: notes,
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
}
