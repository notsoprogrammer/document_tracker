import 'dart:convert';
import '../utils/date_time_utils.dart';

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
  final String? title;
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
  final List<String> localImagePaths; // Local image file paths (for offline uploads)
  final List<String> localFilePaths; // Local file paths (for offline uploads)
  bool needsSync; // Indicates if document was added offline and needs syncing
  final DateTime? createdAt;

  Document({
    required this.code,
    this.title,
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
    List<String>? localImagePaths,
    List<String>? localFilePaths,
    this.needsSync = false,
    this.createdAt,
  }) : history = history ?? [], imageUrls = imageUrls ?? [], fileUrls = fileUrls ?? [], localImagePaths = localImagePaths ?? [], localFilePaths = localFilePaths ?? [] {
    if (this.history.isEmpty) {
      if (incoming) {
        this.history.add(HistoryEntry(
          action: 'Document Received',
          person: person,
          timestamp: getPhilippineTime(),
        ));
      } else {
        this.history.add(HistoryEntry(
          action: 'Created and forwarded to $fromOrTo c/o $assignedTo',
          person: person,
          timestamp: getPhilippineTime(),
        ));
      }
    }
  }

  void addHistoryEntry(String action, String person, {String? notes, String? personnel}) {
    // Skip adding history entries for flag ceremony documents
    if (mode == 'Flag Ceremony') return;

    history.add(HistoryEntry(
      action: action,
      person: person,
      timestamp: getPhilippineTime(),
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

    // Parse local_image_paths if present
    List<String> localImagePaths = [];
    if (json['local_image_paths'] != null) {
      if (json['local_image_paths'] is List) {
        localImagePaths = List<String>.from(json['local_image_paths']);
      } else if (json['local_image_paths'] is String) {
        // Handle case where local_image_paths is stored as JSON string
        try {
          final decoded = jsonDecode(json['local_image_paths']);
          if (decoded is List) {
            localImagePaths = List<String>.from(decoded);
          }
        } catch (e) {
          // If parsing fails, treat as single path
          localImagePaths = [json['local_image_paths']];
        }
      }
    }

    // Parse local_file_paths if present
    List<String> localFilePaths = [];
    if (json['local_file_paths'] != null) {
      if (json['local_file_paths'] is List) {
        localFilePaths = List<String>.from(json['local_file_paths']);
      } else if (json['local_file_paths'] is String) {
        // Handle case where local_file_paths is stored as JSON string
        try {
          final decoded = jsonDecode(json['local_file_paths']);
          if (decoded is List) {
            localFilePaths = List<String>.from(decoded);
          }
        } catch (e) {
          // If parsing fails, treat as single path
          localFilePaths = [json['local_file_paths']];
        }
      }
    }

    // For outgoing documents, parse the history from the TEXT field
    if (json['incoming'] != true) {
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
                  final now = getPhilippineTime();
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
                  timestamp = getPhilippineTime().subtract(Duration(days: days));
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
      incoming: json['incoming'] == 1 || json['incoming'] == true,
      status: json['status'],
      history: history,
      imageUrls: imageUrls,
      fileUrls: fileUrls,
      localImagePaths: localImagePaths,
      localFilePaths: localFilePaths,
      needsSync: json['needs_sync'] == 1 || json['needs_sync'] == true,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    // Generate default title for flag ceremony documents if title is null
    String effectiveTitle = title ?? '';
    if (title == null && mode == 'Flag Ceremony') {
      if (type == 'Flag Raising') {
        effectiveTitle = 'Flag Raising Ceremony - $code';
      } else if (type == 'Flag Lowering') {
        effectiveTitle = 'Flag Lowering Ceremony - $code';
      } else {
        effectiveTitle = 'Flag Ceremony - $code';
      }
    }

    return {
      'code': code,
      'title': effectiveTitle,
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
      'local_image_paths': localImagePaths,
      'local_file_paths': localFilePaths,
      'needs_sync': needsSync,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  Document copyWith({
    String? code,
    String? title,
    String? type,
    String? fromOrTo,
    String? mode,
    String? assignedTo,
    String? filePath,
    String? remarks,
    String? person,
    bool? incoming,
    List<HistoryEntry>? history,
    String? status,
    List<String>? imageUrls,
    List<String>? fileUrls,
    List<String>? localImagePaths,
    List<String>? localFilePaths,
    bool? needsSync,
    DateTime? createdAt,
  }) {
    return Document(
      code: code ?? this.code,
      title: title ?? this.title,
      type: type ?? this.type,
      fromOrTo: fromOrTo ?? this.fromOrTo,
      mode: mode ?? this.mode,
      assignedTo: assignedTo ?? this.assignedTo,
      filePath: filePath ?? this.filePath,
      remarks: remarks ?? this.remarks,
      person: person ?? this.person,
      incoming: incoming ?? this.incoming,
      history: history ?? this.history,
      status: status ?? this.status,
      imageUrls: imageUrls ?? this.imageUrls,
      fileUrls: fileUrls ?? this.fileUrls,
      localImagePaths: localImagePaths ?? this.localImagePaths,
      localFilePaths: localFilePaths ?? this.localFilePaths,
      needsSync: needsSync ?? this.needsSync,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
