import 'dart:convert';

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
  final List<String> imageUrls; // Google Drive image URLs
  final List<String> fileUrls; // Google Drive file URLs (non-images)

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
    List<String>? imageUrls,
    List<String>? fileUrls,
  }) : history = history ?? [], imageUrls = imageUrls ?? [], fileUrls = fileUrls ?? [];

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
    List<HistoryEntry> history = [];
    List<String> imageUrls = [];
    List<String> fileUrls = [];

    // Parse image_urls if present
    if (json['image_urls'] != null) {
      if (json['image_urls'] is List) {
        imageUrls = List<String>.from(json['image_urls']);
      } else if (json['image_urls'] is String) {
        // Handle case where image_urls is stored as JSON string
        try {
          final decoded = jsonDecode(json['image_urls']);
          if (decoded is List) {
            imageUrls = List<String>.from(decoded);
          }
        } catch (e) {
          // If parsing fails, treat as single URL
          imageUrls = [json['image_urls']];
        }
      }
    }

    // Parse file_urls if present
    if (json['file_urls'] != null) {
      if (json['file_urls'] is List) {
        fileUrls = List<String>.from(json['file_urls']);
      } else if (json['file_urls'] is String) {
        // Handle case where file_urls is stored as JSON string
        try {
          final decoded = jsonDecode(json['file_urls']);
          if (decoded is List) {
            fileUrls = List<String>.from(decoded);
          }
        } catch (e) {
          // If parsing fails, treat as single URL
          fileUrls = [json['file_urls']];
        }
      }
    }

    if (json['incoming'] == true) {
      // For incoming documents, create a simple history entry
      history.add(HistoryEntry(
        action: 'Document Received',
        person: json['person'],
        timestamp: DateTime.parse(json['created_at']),
      ));
    } else {
      // For outgoing documents, parse the history from the TEXT field
      final historyRaw = json['history'];
      String? historyText;
      if (historyRaw is String) {
        historyText = historyRaw;
      } else if (historyRaw is List) {
        // Handle case where history might be stored as list (legacy data)
        historyText = (historyRaw as List).join('\n');
      } else {
        historyText = null;
      }
      if (historyText != null && historyText.isNotEmpty) {
        // Parse the formatted history text back into HistoryEntry
        // Format: "Created and forwarded to OFFICE c/o PERSONNEL|by: PERSON | Time: TIMESTAMP"
        final lines = historyText.split('\n');
        for (final line in lines) {
          if (line.trim().isEmpty) continue;

          final parts = line.split('|');
          if (parts.length >= 2) {
            final action = parts[0].trim();
            final byLine = parts[1].trim();
            final timePart = parts.length > 2 ? parts[2].trim() : '';

            // Extract person from "by: PERSON"
            final personMatch = RegExp(r'by:\s*(.+)').firstMatch(byLine);
            final person = personMatch?.group(1) ?? json['person'];

            // Extract timestamp from "Time: TIMESTAMP"
            DateTime timestamp = DateTime.parse(json['created_at']);
            if (timePart.startsWith('Time:')) {
              final timeStr = timePart.replaceFirst('Time:', '').trim();
              // Try to parse the formatted time, fallback to created_at
              try {
                // Assuming format like "Today 14:30" or "Yesterday 14:30" or "1 days ago" or "12/25/2023"
                if (timeStr.startsWith('Today') || timeStr.startsWith('Yesterday')) {
                  final time = timeStr.split(' ')[1];
                  final now = DateTime.now();
                  final today = DateTime(now.year, now.month, now.day);
                  if (timeStr.startsWith('Yesterday')) {
                    timestamp = today.subtract(const Duration(days: 1));
                  } else {
                    timestamp = today;
                  }
                  final timeParts = time.split(':');
                  timestamp = timestamp.add(Duration(
                    hours: int.parse(timeParts[0]),
                    minutes: int.parse(timeParts[1]),
                  ));
                } else if (timeStr.contains('days ago')) {
                  final days = int.parse(timeStr.split(' ')[0]);
                  timestamp = DateTime.now().subtract(Duration(days: days));
                } else if (timeStr.contains('/')) {
                  // Assume MM/DD/YYYY format
                  final dateParts = timeStr.split('/');
                  timestamp = DateTime(
                    int.parse(dateParts[2]),
                    int.parse(dateParts[0]),
                    int.parse(dateParts[1]),
                  );
                }
              } catch (e) {
                // Keep created_at timestamp
              }
            }

            history.add(HistoryEntry(
              action: action,
              person: person,
              timestamp: timestamp,
            ));
          }
        }
      }
    }

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
      history: history,
      imageUrls: imageUrls,
      fileUrls: fileUrls,
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
      'image_urls': imageUrls,
      'file_urls': fileUrls,
    };
  }
}
