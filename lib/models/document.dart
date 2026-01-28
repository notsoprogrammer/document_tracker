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
  final String? description;
  final String? referenceLink;
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
  final List<String> fileNames; // Original file names for display
  final List<String> localImagePaths; // Local image file paths (for offline uploads)
  final List<String> localFilePaths; // Local file paths (for offline uploads)
  bool needsSync; // Indicates if document was added offline and needs syncing
  final DateTime? createdAt;
  final DateTime? complianceDeadline; // Deadline for compliance status
  final List<int>? scheduledNotificationIds; // IDs of scheduled notifications
  final String? complianceAssignee; // Assignee for compliance status
  final String? category; // Document category (e.g., Attendance, MOVs, Certificates)
  final DateTime? calendarDeadline; // Deadline for calendar entries
  final bool calendarAdded; // Whether added to calendar
  final List<String> attachments; // Combined image and file URLs for calendar
  final String? fileName; // Original file name for display
  final DateTime? receivingDate; // Date and time when document was received
  String flowStage; // 'incoming', 'outgoing', 'circulated'
  final List<String> remarksList; // List of sequential remarks

  Document({
    required this.code,
    this.title,
    this.description,
    this.referenceLink,
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
    List<String>? fileNames,
    List<String>? localImagePaths,
    List<String>? localFilePaths,
    this.needsSync = false,
    this.createdAt,
    this.complianceDeadline,
    this.scheduledNotificationIds,
    this.complianceAssignee,
    this.category,
    this.calendarDeadline,
    this.calendarAdded = false,
    List<String>? attachments,
    this.fileName,
    this.receivingDate,
   String? flowStage,
   bool addInitialHistory = true,
   List<String>? remarksList,
  }) : flowStage = flowStage ?? (incoming ? 'incoming' : 'outgoing'),
       history = history ?? [],
       imageUrls = imageUrls ?? [],
       fileUrls = fileUrls ?? [],
       fileNames = fileNames ?? [],
       localImagePaths = localImagePaths ?? [],
       localFilePaths = localFilePaths ?? [],
       attachments = attachments ?? [],
       remarksList = remarksList ?? [] {
    if (addInitialHistory && this.history.isEmpty) {
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

  void forwardDocument(String forwardedBy, {String? notes, String? action}) {
    // Update flowStage based on current state
    if (flowStage == 'incoming') {
      flowStage = 'outgoing';
    } else if (flowStage == 'outgoing') {
      flowStage = 'circulated';
    }
    addHistoryEntry(action ?? 'Document forwarded', forwardedBy, notes: notes);
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

    // Parse file_names if present
    List<String> fileNames = [];
    if (json['file_names'] != null) {
      if (json['file_names'] is List) {
        fileNames = List<String>.from(json['file_names']);
      } else if (json['file_names'] is String) {
        // Handle case where file_names is stored as JSON string
        try {
          final decoded = jsonDecode(json['file_names']);
          if (decoded is List) {
            fileNames = List<String>.from(decoded);
          }
        } catch (e) {
          // If parsing fails, treat as single name
          fileNames = [json['file_names']];
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

    // Parse scheduled_notification_ids if present
    List<int>? scheduledNotificationIds;
    if (json['scheduled_notification_ids'] != null) {
      if (json['scheduled_notification_ids'] is List) {
        scheduledNotificationIds = List<int>.from(json['scheduled_notification_ids']);
      } else if (json['scheduled_notification_ids'] is String) {
        // Handle case where scheduled_notification_ids is stored as JSON string
        try {
          final decoded = jsonDecode(json['scheduled_notification_ids']);
          if (decoded is List) {
            scheduledNotificationIds = List<int>.from(decoded);
          }
        } catch (e) {
          // If parsing fails, ignore
        }
      }
    }

    // Parse attachments if present
    List<String> attachments = [];
    if (json['attachments'] != null) {
      if (json['attachments'] is List) {
        attachments = List<String>.from(json['attachments']);
      } else if (json['attachments'] is String) {
        // Handle case where attachments is stored as JSON string
        try {
          final decoded = jsonDecode(json['attachments']);
          if (decoded is List) {
            attachments = List<String>.from(decoded);
          }
        } catch (e) {
          // If parsing fails, ignore
        }
      }
    }

    // Parse remarks_list if present
    List<String> remarksList = [];
    if (json['remarks_list'] != null) {
      if (json['remarks_list'] is List) {
        remarksList = List<String>.from(json['remarks_list']);
      } else if (json['remarks_list'] is String) {
        // Handle case where remarks_list is stored as JSON string
        try {
          final decoded = jsonDecode(json['remarks_list']);
          if (decoded is List) {
            remarksList = List<String>.from(decoded);
          }
        } catch (e) {
          // If parsing fails, ignore
        }
      }
    }

    return Document(
      code: json['code'],
      title: json['title'],
      description: json['description'],
      referenceLink: json['reference_link'],
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
      fileNames: fileNames,
      localImagePaths: localImagePaths,
      localFilePaths: localFilePaths,
      needsSync: json['needs_sync'] == 1 || json['needs_sync'] == true,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
      complianceDeadline: json['compliance_deadline'] != null ? DateTime.parse(json['compliance_deadline']) : null,
      scheduledNotificationIds: scheduledNotificationIds,
      complianceAssignee: json['compliance_assignee'],
      category: json['category'],
      calendarDeadline: json['calendar_deadline'] != null ? DateTime.parse(json['calendar_deadline']) : null,
      calendarAdded: json['calendar_added'] == 1 || json['calendar_added'] == true,
      attachments: attachments,
      fileName: json['file_name'],
      receivingDate: json['receiving_date'] != null ? DateTime.parse(json['receiving_date']) : null,
      flowStage: json['flow_stage'] ?? (json['incoming'] == 1 || json['incoming'] == true ? 'incoming' : 'outgoing'),
      addInitialHistory: false,
      remarksList: remarksList,
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
      'description': description,
      'reference_link': referenceLink,
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
      'file_names': fileNames,
      'local_image_paths': localImagePaths,
      'local_file_paths': localFilePaths,
      'needs_sync': needsSync,
      'created_at': createdAt?.toIso8601String(),
      'compliance_deadline': complianceDeadline?.toIso8601String(),
      'scheduled_notification_ids': scheduledNotificationIds,
      'compliance_assignee': complianceAssignee,
      'category': category,
      'calendar_deadline': calendarDeadline?.toIso8601String(),
      'calendar_added': calendarAdded,
      'attachments': attachments,
      'file_name': fileName,
      'receiving_date': receivingDate?.toIso8601String(),
      'flow_stage': flowStage,
      'remarks_list': remarksList,
    };
  }

  Document copyWith({
    String? code,
    String? title,
    String? description,
    String? referenceLink,
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
    List<String>? fileNames,
    List<String>? localImagePaths,
    List<String>? localFilePaths,
    bool? needsSync,
    DateTime? createdAt,
    DateTime? complianceDeadline,
    List<int>? scheduledNotificationIds,
    String? complianceAssignee,
    String? category,
    DateTime? calendarDeadline,
    bool? calendarAdded,
    List<String>? attachments,
    String? fileName,
    DateTime? receivingDate,
    String? flowStage,
    List<String>? remarksList,
  }) {
    return Document(
      code: code ?? this.code,
      title: title ?? this.title,
      description: description ?? this.description,
      referenceLink: referenceLink ?? this.referenceLink,
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
      fileNames: fileNames ?? this.fileNames,
      localImagePaths: localImagePaths ?? this.localImagePaths,
      localFilePaths: localFilePaths ?? this.localFilePaths,
      needsSync: needsSync ?? this.needsSync,
      createdAt: createdAt ?? this.createdAt,
      complianceDeadline: complianceDeadline ?? this.complianceDeadline,
      scheduledNotificationIds: scheduledNotificationIds ?? this.scheduledNotificationIds,
      complianceAssignee: complianceAssignee ?? this.complianceAssignee,
      category: category ?? this.category,
      calendarDeadline: calendarDeadline ?? this.calendarDeadline,
      calendarAdded: calendarAdded ?? this.calendarAdded,
      attachments: attachments ?? this.attachments,
      fileName: fileName ?? this.fileName,
      receivingDate: receivingDate ?? this.receivingDate,
      flowStage: flowStage ?? this.flowStage,
      remarksList: remarksList ?? this.remarksList,
    );
  }
}
