import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../models/document.dart';
import '../models/activity.dart';
import '../services/cached_document_service.dart';
import '../services/notification_service.dart';
import '../services/supabase_service.dart';
import '../services/connectivity_service.dart';
import '../widgets/sync_banner.dart';
import '../utils/delete_utils.dart';
import '../utils/date_time_utils.dart';
import '../utils/document_search.dart';
import '../services/auth_service.dart';
import '../services/user_activity_service.dart';
import 'add_document_screen.dart';
import 'incoming_documents_screen.dart';
import 'outgoing_documents_screen.dart';
import 'add_resolution_screen.dart';
import 'resolutions_screen.dart';
import 'attendance_movs_screen.dart';
import 'add_attendance_movs_screen.dart';
import 'delete_history_screen.dart';
import 'notification_history_screen.dart';
import 'calendar_screen.dart';
import 'about_screen.dart';
import 'user_activity_screen.dart';
import 'public_repository_screen.dart';
import 'locational_zoning_screen.dart';
import 'add_locational_zoning_screen.dart';
import 'cdc_screen.dart';
import 'add_cdc_screen.dart';
import 'sp_documents_screen.dart';
import 'add_sp_documents_screen.dart';
import 'reclassification_screen.dart';
import 'add_reclassification_screen.dart';
import '../services/update_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'cabinet_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final CachedDocumentService _documentService = CachedDocumentService();
  List<Document> documents = [];
  bool _isLoading = true;
  bool _showPills = false;
  List<dynamic> _todayEvents = [];
  bool _isTodayActivitiesLoading = true;
  RealtimeChannel? _docsChannel;

  @override
  void initState() {
    super.initState();
    _loadDocuments();
    _loadTodayActivities();
    _checkAndRequestNotificationPermission();
    _logSessionResume();
    _checkForUpdates();
    _subscribeToDocumentChanges();
  }

  Future<void> _logSessionResume() async {
    final username = await AuthService.getUsername();
    if (username == null || username.isEmpty) return;
    // Skip if user just logged in (login_screen already logged the session)
    final recent = await UserActivityService().getLastSessionTime(username);
    final isJustLoggedIn = recent != null &&
        DateTime.now().difference(recent).inSeconds < 10;
    if (!isJustLoggedIn) {
      await UserActivityService().logAppOpen(username: username, method: 'App reopened');
    }
  }

  Future<void> _checkForUpdates() async {
    final update = await UpdateService.checkForUpdate();
    if (update == null || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Update Available'),
        content: Text(
          'Version ${update.latestVersion} is available. Update now to get the latest features and fixes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Update Now'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final progressNotifier = ValueNotifier<double>(0.0);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Downloading Update'),
          content: ValueListenableBuilder<double>(
            valueListenable: progressNotifier,
            builder: (context, progress, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: progress > 0 ? progress : null),
                const SizedBox(height: 8),
                Text(progress > 0 ? '${(progress * 100).toInt()}%' : 'Starting...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      await UpdateService.downloadAndInstall(
        update.downloadUrl,
        onProgress: (p) => progressNotifier.value = p,
      );
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Download failed. Please try again later.')),
        );
      }
    } finally {
      progressNotifier.dispose();
      if (mounted) Navigator.of(context).pop();
    }
  }

  void _subscribeToDocumentChanges() {
    _docsChannel = Supabase.instance.client
        .channel('public:documents')
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'documents',
          callback: (payload) {
            if (!mounted) return;
            final code = payload.oldRecord['code'] as String?;
            if (code != null) {
              setState(() => documents.removeWhere((d) => d.code == code));
            }
            _loadDocuments();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'documents',
          callback: (payload) {
            if (mounted) _loadDocuments();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'documents',
          callback: (payload) {
            if (mounted) _loadDocuments();
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _docsChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadDocuments() async {
    try {
      final loadedDocuments = await _documentService.fetchDocuments();
      setState(() {
        documents = loadedDocuments;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadTodayActivities() async {
    try {
      final today = DateTime.now();
      List<Activity> activities = [];
      List<Document> calendarDocs = [];
      await Future.wait([
        SupabaseService().fetchActivities().then((r) => activities = r),
        SupabaseService().fetchCalendarDocuments().then((r) => calendarDocs = r),
      ]);

      final todayDay = DateTime(today.year, today.month, today.day);

      final todayActivities = activities.where((a) {
        final actStart = DateTime(a.startTime.year, a.startTime.month, a.startTime.day);
        final actEnd = a.endTime != null
            ? DateTime(a.endTime!.year, a.endTime!.month, a.endTime!.day)
            : actStart;
        return !todayDay.isBefore(actStart) && !todayDay.isAfter(actEnd);
      });

      final todayDocs = calendarDocs.where((d) {
        final cd = d.calendarDeadline;
        if (cd == null) return false;
        final startDay = DateTime(cd.year, cd.month, cd.day);
        final endDay = d.calendarDeadlineEnd != null
            ? DateTime(d.calendarDeadlineEnd!.year, d.calendarDeadlineEnd!.month, d.calendarDeadlineEnd!.day)
            : startDay;
        return !todayDay.isBefore(startDay) && !todayDay.isAfter(endDay);
      });

      final combined = <dynamic>[...todayActivities, ...todayDocs]
        ..sort((a, b) {
          final aTime = a is Activity ? a.startTime : (a as Document).calendarDeadline!;
          final bTime = b is Activity ? b.startTime : (b as Document).calendarDeadline!;
          return aTime.compareTo(bTime);
        });

      setState(() {
        _todayEvents = combined;
        _isTodayActivitiesLoading = false;
      });


    } catch (_) {
      setState(() {
        _isTodayActivitiesLoading = false;
      });
    }
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour > 12 ? dt.hour - 12 : dt.hour == 0 ? 12 : dt.hour;
    final amPm = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute $amPm';
  }

  // Lists for dropdowns
  final List<String> offices = [
    'CMO - City Mayor\'s Office',
    'CVMO - City Vice Mayor\'s Office',
    'SP - Sangguniang Panlungsod Office',
    'CTO - City Treasurer\'s Office',
    'CAssO - City Assessor\'s Office',
    'CAccO - City Accounting Office',
    'CBO - City Budget Office',
    'CPDCO - City Planning and Development Coordinator\'s Office',
    'CHRMO - City Human Resource Management Office',
    'CCRO - City Civil Registrar\'s Office',
    'CAdmO - City Administrator\'s Office',
    'CLO - City Legal Office',
    'CICTO - City Information and Communications Technology Office',
    'CGSO - City General Services Office',
    'CDRRMO - City Disaster Risk Reduction and Management Office',
    'CIASO - City Internal Audit Services Office',
    'CPYDO - City Population and Youth Development Office',
    'CBPLO - City Business Processing and Licensing Office',
    'BCAO - Barangay And Community Affair\'s Office',
    'CPO - City Procurement Office',
    'CLEAO - Catbalogan Law Enforcement Auxiliary Office',
    'CCCC - Catbalogan City Community College',
    'CHO - City Health Office',
    'CSWDO - City Social Welfare and Development Office',
    'CPDAO - City Persons with Disability Affairs Office',
    'CPESO - City Public Employment Services Office',
    'CTCAO - City Tourism, Culture, Arts, and Information Office',
    'CAgrO - City Agriculture Office',
    'CENRO - City Environment & Natural Resources Office',
    'CEO - City Engineering Office',
    'CVetO - City Veterinary Office',
    'CCDO - City Cooperatives Development Office',
    'CAgBEO - City Agricultural and Biosystem Engineering Office',
    'CEDIPO - City Economic Development and Investment Promotions Office',
    'CEEPUO - City Economic Enterprise and Public Utility Office',
    'Other'
  ];

  final List<String> cpdcoStaff = [
    'Sir Arnie',
    'Rex',
    'Floro',
    'Arlene',
    'Sharmaine',
    'Path',
    'Jess',
    'Emie',
    'Pau',
    'Chris',
    'Wena',
    'N/A',
    'Arlyn',
    'Dari',
  ];


  Future<void> _transferDocument(int index, String newAssignee, String transferredBy, {String? notes}) async {
    try {
      // Update local document
      documents[index].transferTo(newAssignee, transferredBy, notes: notes);

      // Update through cached service (handles both local and remote)
      Map<String, dynamic> updates = {'addressed_to': documents[index].assignedTo};

      // Add history entry for both incoming and outgoing documents
      await _documentService.addHistoryEntry(documents[index].code, HistoryEntry(
        action: 'Transferred to $newAssignee',
        person: transferredBy,
        timestamp: getPhilippineTime(),
        notes: notes,
      ), personnel: transferredBy);

      // Update the document
      await _documentService.updateDocument(documents[index].code, updates);

      // Notify the new assignee 5 minutes after transfer
      SupabaseService().scheduleAssignmentNotification(
        documents[index].code,
        documents[index].title ?? 'Document',
        [newAssignee],
      );

      setState(() {});
    } catch (e) {
      // Could show error snackbar here
    }
  }

  Future<void> _updateDocumentStatus(int index, String newStatus, String updatedBy, {String? notes, DateTime? complianceDeadline, String? complianceAssignee, String? customHistoryAction}) async {
    // Check connectivity for notification-dependent statuses
    final connectivityService = ConnectivityService();
    final isOnline = await connectivityService.isOnline;
    if (!isOnline && (newStatus == 'Urgent' || newStatus == 'For Compliance')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot set notification-dependent status while offline')),
      );
      return;
    }

    try {
      // Update local document
      documents[index] = documents[index].copyWith(status: newStatus, complianceAssignee: complianceAssignee);

      // Update through cached service (handles both local and remote)
      Map<String, dynamic> updates = {'status': newStatus};
      if (complianceAssignee != null) {
        updates['compliance_assignee'] = complianceAssignee;
      }

      // Handle compliance deadline and notifications
      if (newStatus == 'For Compliance' && complianceDeadline != null) {
        updates['compliance_deadline'] = complianceDeadline.toString();

        // TODO: Call backend Edge Function to schedule FCM notifications
        // For now, just set deadline - FCM scheduling will be handled by backend cron
        updates['scheduled_notification_ids'] = [];

        // Update document with deadline
        documents[index] = documents[index].copyWith(
          complianceDeadline: complianceDeadline,
          scheduledNotificationIds: [],
        );

        // Add history entry for deadline setting
        final deadlineHistoryEntry = HistoryEntry(
          action: 'Deadline set to ${complianceDeadline.month}/${complianceDeadline.day}/${complianceDeadline.year}',
          person: updatedBy,
          timestamp: getPhilippineTime(),
          personnel: updatedBy,
        );
        await _documentService.addHistoryEntry(documents[index].code, deadlineHistoryEntry);
        documents[index].history.add(deadlineHistoryEntry);
      } else if (newStatus != 'For Compliance') {
        // Cancel any existing notifications if status changed away from For Compliance
        final notificationService = NotificationService();
        if (documents[index].scheduledNotificationIds != null) {
          await notificationService.cancelAll(documents[index].scheduledNotificationIds!);
        }
        updates['compliance_deadline'] = null;
        updates['scheduled_notification_ids'] = null;
        documents[index] = documents[index].copyWith(
          complianceDeadline: null,
          scheduledNotificationIds: null,
        );
      }

      // Mark notifications as completed if status is Completed
      if (newStatus == 'Completed') {
        await SupabaseService().updateNotificationsStatusByDocumentCode(documents[index].code, 'completed');
      }

      // Delete urgent notifications if status changed away from Urgent
      if (documents[index].status == 'Urgent' && newStatus != 'Urgent') {
        try {
          await SupabaseService().deleteNotificationsByDocumentCodeAndType(documents[index].code, 'urgent');
        } catch (e) {
        }
      }

      // Add history entry for status change
      String statusAction;
      if (newStatus == 'For Compliance' && complianceAssignee != null && complianceAssignee!.isNotEmpty) {
        statusAction = 'For Compliance: Assigned to $complianceAssignee';
      } else {
        statusAction = 'Status changed to $newStatus';
      }
      final statusHistoryEntry = HistoryEntry(
        action: statusAction,
        person: updatedBy,
        timestamp: getPhilippineTime(),
        notes: notes,
        personnel: updatedBy,
      );
      await _documentService.addHistoryEntry(documents[index].code, statusHistoryEntry);
      documents[index].history.add(statusHistoryEntry);

      // Update the document
      await _documentService.updateDocument(documents[index].code, updates);

          // Record notification history if status set to For Compliance
          if (newStatus == 'For Compliance' && complianceDeadline != null) {
            try {
              await SupabaseService().addNotificationHistory(
                documentCode: documents[index].code,
                notificationType: 'scheduled',
                notificationId: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                scheduledTime: complianceDeadline,
                status: 'scheduled',
              );
              // Send compliance notifications
              await SupabaseService().sendComplianceNotifications(documentCode: documents[index].code);
            } catch (e) {
            }
          }

      // Record notification history if status set to Urgent
      if (newStatus == 'Urgent') {
        try {
          await SupabaseService().addNotificationHistory(
            documentCode: documents[index].code,
            notificationType: 'urgent',
            notificationId: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            scheduledTime: DateTime.now(), // Use current time for urgent
            status: 'urgent',
          );
          // Note: No push notifications sent for urgent status
        } catch (e) {
        }
      }

      UserActivityService().logAction(
        action: 'Updated document status to $newStatus',
        screen: 'Documents',
        details: 'Code: ${documents[index].code}, by: $updatedBy',
      );
      setState(() {});
    } catch (e) {
    }
  }

  Future<void> _deleteDocument(int index) async {
    final docCode = documents[index].code;
    final success = await confirmAndDeleteRecord(context, documents[index], _documentService);
    if (success) {
      UserActivityService().logAction(
        action: 'Deleted document',
        screen: 'Documents',
        details: 'Code: $docCode',
      );
      setState(() {
        documents.removeAt(index);
      });
    }
  }

  Future<void> _syncDocument(String documentCode) async {
    try {
      await _documentService.syncSpecificDocument(documentCode);
      // Reload documents to reflect changes
      await _loadDocuments();
    } catch (e) {
      // Could show error snackbar here
    }
  }

  Future<void> _syncAllDocuments() async {
    try {
      await _documentService.syncAllData(context, reloadRecords: _loadDocuments);
      // Mark all documents as synced locally to update UI
      final allDocuments = await _documentService.fetchDocuments();
      for (var doc in allDocuments) {
        if (doc.needsSync) {
          await _documentService.updateDocument(doc.code, {'needs_sync': false});
        }
      }
      await _loadDocuments(); // Reload to reflect changes
    } catch (e) {
      // Could show error snackbar here
    }
  }




  @override
  Widget build(BuildContext context) {
    return SyncBanner(
      child: Scaffold(
        appBar: AppBar(
        title: const Text("FileTrack Hub"),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color.fromARGB(255, 228, 239, 252), // Soft pastel pink
                const Color.fromARGB(255, 13, 134, 205), // Lighter pastel pink
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_outlined),
            tooltip: 'Search all documents',
            onPressed: () async {
              final doc = await showSearch<Document?>(
                context: context,
                delegate: _DocumentSearchDelegate(
                  documents: documents,
                  getFolderName: _getFolderName,
                ),
              );
              if (doc != null && mounted) _navigateToDocumentFolder(doc);
            },
          ),
          if (documents.any((d) => d.status == 'Urgent'))
            Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  icon: Icon(Icons.warning_amber_rounded, color: Colors.red[700]),
                  tooltip: 'Urgent documents',
                  onPressed: () async {
                    final doc = await showSearch<Document?>(
                      context: context,
                      delegate: _DocumentSearchDelegate(
                        documents: documents,
                        getFolderName: _getFolderName,
                        urgentOnly: true,
                      ),
                    );
                    if (doc != null && mounted) _navigateToDocumentFolder(doc);
                  },
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text(
                      '${documents.where((d) => d.status == 'Urgent').length}',
                      style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_outlined),
            onSelected: (value) {
              if (value == 'sync') {
                _syncAllDocuments();
              } else if (value == 'cabinet') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CabinetScreen()),
                );
              } else if (value == 'calendar') {
                UserActivityService().logAction(action: 'Opened screen', screen: 'Calendar');
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CalendarScreen(),
                  ),
                ).then((_) { if (mounted) _loadTodayActivities(); });
              } else if (value == 'about') {
                UserActivityService().logAction(action: 'Opened screen', screen: 'About');
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AboutScreen(),
                  ),
                );
              } else if (value == 'delete_history') {
                UserActivityService().logAction(action: 'Opened screen', screen: 'Delete History');
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const DeleteHistoryScreen(),
                  ),
                );
              } else if (value == 'notification_history') {
                UserActivityService().logAction(action: 'Opened screen', screen: 'Notification History');
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const NotificationHistoryScreen(),
                  ),
                );
              } else if (value == 'test_notification') {
                _testNotification();
              } else if (value == 'check_permissions') {
                _checkPermissions();
              } else if (value == 'notification_settings') {
                _showNotificationSettings();
              } else if (value == 'user_activity') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const UserActivityScreen(),
                  ),
                );
              } else if (value == 'repository') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PublicRepositoryScreen(),
                  ),
                );
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'sync',
                child: ListTile(
                  leading: Icon(Icons.sync_outlined),
                  title: Text('Sync All Documents'),
                ),
              ),
              const PopupMenuItem(
                value: 'cabinet',
                child: ListTile(
                  leading: Icon(Icons.inventory_2_outlined),
                  title: Text('Cabinet Library'),
                ),
              ),
              const PopupMenuItem(
                value: 'calendar',
                child: ListTile(
                  leading: Icon(Icons.calendar_today),
                  title: Text('Calendar'),
                ),
              ),
              const PopupMenuItem(
                value: 'delete_history',
                child: ListTile(
                  leading: Icon(Icons.history),
                  title: Text('Delete History'),
                ),
              ),
              const PopupMenuItem(
                value: 'notification_history',
                child: ListTile(
                  leading: Icon(Icons.notifications_active),
                  title: Text('Notification History'),
                ),
              ),
              const PopupMenuItem(
                value: 'notification_settings',
                child: ListTile(
                  leading: Icon(Icons.settings),
                  title: Text('Notification Settings'),
                ),
              ),
              const PopupMenuItem(
                value: 'user_activity',
                child: ListTile(
                  leading: Icon(Icons.people_outline),
                  title: Text('User Activity'),
                ),
              ),
              const PopupMenuItem(
                value: 'repository',
                child: ListTile(
                  leading: Icon(Icons.folder_shared_outlined),
                  title: Text('Public Repository'),
                ),
              ),
              const PopupMenuItem(
                value: 'about',
                child: ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('About'),
                ),
              ),
            ],
          ),
        ],
),
backgroundColor: Colors.transparent,
body: Container(
  height: double.infinity,
  width: double.infinity,
  decoration: BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFFFDF6EC),
        Color(0xFFE3F2FD),
        Color(0xFFE8F5E9),
      ],
    ),
  ),
  child: Stack(
    children: [
      RefreshIndicator(
        onRefresh: _loadDocuments,
        child: Container(
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.all(10.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 10),
                  _buildHeaderCard(),
                  const SizedBox(height: 14),
                  _buildTodayActivitiesSection(),
                  const SizedBox(height: 16),
                  _buildFoldersSection(),
                  const SizedBox(height: 88),
                ],
              ),
            ),
          ),
        ),
      ),
Positioned(
  bottom: 16.0,
  right: 16.0,
  child: Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.end, // ✅ align to right
    children: [
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: _showPills
            ? Column(
                key: const ValueKey('pills'),
                crossAxisAlignment: CrossAxisAlignment.end, // ✅ keep pills right-aligned
                children: [
                  _buildPill('Incoming', '', () {
                    _showForm(context, true);
                    setState(() => _showPills = false);
                  }),
                  const SizedBox(height: 8),
                  _buildPill('Outgoing', '', () {
                    _showForm(context, false);
                    setState(() => _showPills = false);
                  }),
                  const SizedBox(height: 8),
                  _buildPill('Resolutions', '', () {
                    _showResolutionsForm(context);
                    setState(() => _showPills = false);
                  }),
                  const SizedBox(height: 8),
                  _buildPill('Function MOVs', '', () {
                    _showAttendanceMovForm(context);
                    setState(() => _showPills = false);
                  }),
                  const SizedBox(height: 8),
                  _buildPill('Locational & Zoning', '', () {
                    _showLocationalZoningForm(context);
                    setState(() => _showPills = false);
                  }),
                  const SizedBox(height: 8),
                  _buildPill('CDC Documents', '', () {
                    _showCdcForm(context);
                    setState(() => _showPills = false);
                  }),
                  const SizedBox(height: 8),
                  _buildPill('SP Documents', '', () {
                    _showSpDocumentsForm(context);
                    setState(() => _showPills = false);
                  }),
                  const SizedBox(height: 8),
                  _buildPill('Reclassification', '', () {
                    _showReclassificationForm(context);
                    setState(() => _showPills = false);
                  }),
                ],
              )
            : const SizedBox.shrink(),
      ),
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerRight,
        child: FloatingActionButton(
          onPressed: () => setState(() => _showPills = !_showPills),
          backgroundColor: const Color(0xFF4988C4),
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          child: const Icon(Icons.add),
        ),
      ),
    ],
  ),
)
    ],
  ),
),
      ),
    );
  }



  Widget _buildHeaderCard() {
    final urgentCount = documents.where((d) => d.status == 'Urgent').length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBBDEFB), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Image.asset('assets/image/officeLogo.png', height: 48, width: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "CPDCO File Tracking",
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Colors.blueGrey[800],
                  ),
                ),
                Text(
                  "City Planning and Development Coordinator's Office",
                  style: TextStyle(fontSize: 10, color: Colors.blueGrey[400]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${documents.length}',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22, color: Color(0xFF4988C4)),
              ),
              Text('docs', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
            ],
          ),
          if (urgentCount > 0) ...[
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$urgentCount',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22, color: Colors.red),
                ),
                Text('urgent', style: TextStyle(fontSize: 10, color: Colors.red[300])),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFoldersSection() {
    final incomingCount = documents.where((d) =>
        d.incoming &&
        d.mode != 'Resolutions' &&
        d.mode != 'Office Function MOVs' &&
        d.mode != 'Locational & Zoning' &&
        d.mode != 'CDC Documents' &&
        d.mode != 'SP Documents' &&
        d.mode != 'Reclassification').length;
    final outgoingCount = documents.where((d) =>
        !d.incoming &&
        d.mode != 'Resolutions' &&
        d.mode != 'Office Function MOVs' &&
        d.mode != 'Locational & Zoning' &&
        d.mode != 'CDC Documents' &&
        d.mode != 'SP Documents' &&
        d.mode != 'Reclassification').length;
    final resolutionCount = documents.where((d) => d.mode == 'Resolutions').length;
    final movsCount = documents.where((d) => d.mode == 'Office Function MOVs' || d.mode == 'Flag Ceremony').length;
    final lzCount = documents.where((d) => d.mode == 'Locational & Zoning').length;
    final cdcCount = documents.where((d) => d.mode == 'CDC Documents').length;
    final spCount = documents.where((d) => d.mode == 'SP Documents').length;
    final reclassCount = documents.where((d) => d.mode == 'Reclassification').length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            "Document Folders",
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: Colors.blueGrey[700],
              letterSpacing: 0.3,
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: _buildFolderCard(
                icon: Icons.move_to_inbox_outlined,
                title: "Incoming",
                subtitle: "Received documents",
                count: incomingCount,
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFCC80), Color(0xFFF57C00)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                onTap: () {
                  UserActivityService().logAction(action: 'Opened screen', screen: 'Incoming Documents');
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => IncomingDocumentsScreen(
                        documents: documents,
                        transferDocument: _transferDocument,
                        updateDocumentStatus: _updateDocumentStatus,
                        deleteDocument: _deleteDocument,
                        syncDocument: _syncDocument,
                        onRefresh: _loadDocuments,
                        syncAllDocuments: _syncAllDocuments,
                      ),
                    ),
                  ).then((_) { if (mounted) _loadTodayActivities(); });
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildFolderCard(
                icon: Icons.outbox_outlined,
                title: "Outgoing",
                subtitle: "Sent documents",
                count: outgoingCount,
                gradient: const LinearGradient(
                  colors: [Color(0xFF64B5F6), Color(0xFF1565C0)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                onTap: () {
                  UserActivityService().logAction(action: 'Opened screen', screen: 'Outgoing Documents');
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => OutgoingDocumentsScreen(
                        documents: documents,
                        transferDocument: _transferDocument,
                        updateDocumentStatus: _updateDocumentStatus,
                        deleteDocument: _deleteDocument,
                        syncDocument: _syncDocument,
                        onRefresh: _loadDocuments,
                        syncAllDocuments: _syncAllDocuments,
                      ),
                    ),
                  ).then((_) { if (mounted) _loadTodayActivities(); });
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildFolderCard(
                icon: Icons.gavel_outlined,
                title: "SP Documents",
                subtitle: "Resolutions & ordinances",
                count: spCount,
                gradient: const LinearGradient(
                  colors: [Color(0xFF7986CB), Color(0xFF283593)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                onTap: () {
                  UserActivityService().logAction(action: 'Opened screen', screen: 'SP Documents');
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SpDocumentsScreen(
                        documents: documents,
                        transferDocument: _transferDocument,
                        updateDocumentStatus: _updateDocumentStatus,
                        deleteDocument: _deleteDocument,
                        syncDocument: _syncDocument,
                        onRefresh: _loadDocuments,
                      ),
                    ),
                  ).then((_) { if (mounted) _loadTodayActivities(); });
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildFolderCard(
                icon: Icons.gavel_outlined,
                title: "Other Resolutions",
                subtitle: "City resolutions and others",
                count: resolutionCount,
                gradient: const LinearGradient(
                  colors: [Color(0xFFCE93D8), Color(0xFF6A1B9A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                onTap: () {
                  UserActivityService().logAction(action: 'Opened screen', screen: 'Resolutions');
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ResolutionsScreen(
                        documents: documents,
                        transferDocument: _transferDocument,
                        updateDocumentStatus: _updateDocumentStatus,
                        deleteDocument: _deleteDocument,
                        syncDocument: _syncDocument,
                        onRefresh: _loadDocuments,
                      ),
                    ),
                  ).then((_) { if (mounted) _loadTodayActivities(); });
                },
              ),
            ),
                        
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildFolderCard(
                icon: Icons.map_outlined,
                title: "Locational & Zoning",
                subtitle: "Clearances & certificates",
                count: lzCount,
                gradient: const LinearGradient(
                  colors: [Color(0xFF4DD0E1), Color(0xFF00838F)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                onTap: () {
                  UserActivityService().logAction(action: 'Opened screen', screen: 'Locational & Zoning');
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => LocalationalZoningScreen(
                        documents: documents,
                        transferDocument: _transferDocument,
                        updateDocumentStatus: _updateDocumentStatus,
                        deleteDocument: _deleteDocument,
                        syncDocument: _syncDocument,
                        onRefresh: _loadDocuments,
                      ),
                    ),
                  ).then((_) { if (mounted) _loadTodayActivities(); });
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildFolderCard(
                icon: Icons.swap_horizontal_circle_outlined,
                title: "Reclassification",
                subtitle: "CLUP zoning docs",
                count: reclassCount,
                gradient: const LinearGradient(
                  colors: [Color(0xFF81C784), Color(0xFF1B5E20)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                onTap: () {
                  UserActivityService().logAction(action: 'Opened screen', screen: 'Reclassification');
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ReclassificationScreen(
                        documents: documents,
                        transferDocument: _transferDocument,
                        updateDocumentStatus: _updateDocumentStatus,
                        deleteDocument: _deleteDocument,
                        syncDocument: _syncDocument,
                        onRefresh: _loadDocuments,
                      ),
                    ),
                  ).then((_) { if (mounted) _loadTodayActivities(); });
                },
              ),
            ),

          ],
        ),
        
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildFolderCard(
                icon: Icons.event_note_outlined,
                title: "Function MOVs",
                subtitle: "Office activities",
                count: movsCount,
                gradient: const LinearGradient(
                  colors: [Color(0xFFCE93D8), Color(0xFF6A1B9A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                onTap: () {
                  UserActivityService().logAction(action: 'Opened screen', screen: 'Attendance & MOVs');
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AttendanceMovsScreen(
                        documents: documents,
                        transferDocument: _transferDocument,
                        updateDocumentStatus: _updateDocumentStatus,
                        deleteDocument: _deleteDocument,
                        syncDocument: _syncDocument,
                        onRefresh: _loadDocuments,
                      ),
                    ),
                  ).then((_) { if (mounted) _loadTodayActivities(); });
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildFolderCard(
                icon: Icons.groups_outlined,
                title: "CDC Documents",
                subtitle: "Council records",
                count: cdcCount,
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF8A65), Color(0xFFBF360C)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                onTap: () {
                  UserActivityService().logAction(action: 'Opened screen', screen: 'CDC Documents');
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CdcScreen(
                        documents: documents,
                        transferDocument: _transferDocument,
                        updateDocumentStatus: _updateDocumentStatus,
                        deleteDocument: _deleteDocument,
                        syncDocument: _syncDocument,
                        onRefresh: _loadDocuments,
                      ),
                    ),
                  ).then((_) { if (mounted) _loadTodayActivities(); });
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFolderCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required int count,
    required Gradient gradient,
    required VoidCallback onTap,
  }) {
    return Material(
      borderRadius: BorderRadius.circular(16),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          height: 108,
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, size: 20, color: Colors.white),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$count',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getFolderName(Document doc) {
    if (doc.mode == 'Resolutions') return 'Other Resolutions';
    if (doc.mode == 'Office Function MOVs' || doc.mode == 'Flag Ceremony') return 'Function MOVs';
    if (doc.mode == 'Locational & Zoning') return 'Locational & Zoning';
    if (doc.mode == 'CDC Documents') return 'CDC Documents';
    if (doc.mode == 'SP Documents') return 'SP Documents';
    if (doc.mode == 'Reclassification') return 'Reclassification';
    return doc.flowStage == 'incoming' ? 'Incoming' : 'Outgoing';
  }

  void _navigateToDocumentFolder(Document doc) {
    Widget screen;
    if (doc.mode == 'Resolutions') {
      screen = ResolutionsScreen(
        documents: documents,
        transferDocument: _transferDocument,
        updateDocumentStatus: _updateDocumentStatus,
        deleteDocument: _deleteDocument,
        syncDocument: _syncDocument,
        onRefresh: _loadDocuments,
        initialDocumentCode: doc.code,
      );
    } else if (doc.mode == 'Office Function MOVs' || doc.mode == 'Flag Ceremony') {
      screen = AttendanceMovsScreen(
        documents: documents,
        transferDocument: _transferDocument,
        updateDocumentStatus: _updateDocumentStatus,
        deleteDocument: _deleteDocument,
        syncDocument: _syncDocument,
        onRefresh: _loadDocuments,
        initialDocumentCode: doc.code,
      );
    } else if (doc.mode == 'Locational & Zoning') {
      screen = LocalationalZoningScreen(
        documents: documents,
        transferDocument: _transferDocument,
        updateDocumentStatus: _updateDocumentStatus,
        deleteDocument: _deleteDocument,
        syncDocument: _syncDocument,
        onRefresh: _loadDocuments,
        initialDocumentCode: doc.code,
      );
    } else if (doc.mode == 'CDC Documents') {
      screen = CdcScreen(
        documents: documents,
        transferDocument: _transferDocument,
        updateDocumentStatus: _updateDocumentStatus,
        deleteDocument: _deleteDocument,
        syncDocument: _syncDocument,
        onRefresh: _loadDocuments,
        initialDocumentCode: doc.code,
      );
    } else if (doc.mode == 'SP Documents') {
      screen = SpDocumentsScreen(
        documents: documents,
        transferDocument: _transferDocument,
        updateDocumentStatus: _updateDocumentStatus,
        deleteDocument: _deleteDocument,
        syncDocument: _syncDocument,
        onRefresh: _loadDocuments,
        initialDocumentCode: doc.code,
      );
    } else if (doc.mode == 'Reclassification') {
      screen = ReclassificationScreen(
        documents: documents,
        transferDocument: _transferDocument,
        updateDocumentStatus: _updateDocumentStatus,
        deleteDocument: _deleteDocument,
        syncDocument: _syncDocument,
        onRefresh: _loadDocuments,
        initialDocumentCode: doc.code,
      );
    } else if (doc.flowStage == 'incoming') {
      screen = IncomingDocumentsScreen(
        documents: documents,
        transferDocument: _transferDocument,
        updateDocumentStatus: _updateDocumentStatus,
        deleteDocument: _deleteDocument,
        syncDocument: _syncDocument,
        onRefresh: _loadDocuments,
        syncAllDocuments: _syncAllDocuments,
        initialDocumentCode: doc.code,
      );
    } else {
      screen = OutgoingDocumentsScreen(
        documents: documents,
        transferDocument: _transferDocument,
        updateDocumentStatus: _updateDocumentStatus,
        deleteDocument: _deleteDocument,
        syncDocument: _syncDocument,
        onRefresh: _loadDocuments,
        syncAllDocuments: _syncAllDocuments,
        initialDocumentCode: doc.code,
      );
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen))
        .then((_) { if (mounted) _loadDocuments(); });
  }


  Widget _buildTodayActivitiesSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBBDEFB), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
            child: Row(
              children: [
                const Icon(Icons.event_note, size: 16, color: Color(0xFF4988C4)),
                const SizedBox(width: 7),
                Text(
                  "Today's Activities",
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Colors.blueGrey[800],
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    UserActivityService().logAction(action: 'Opened screen', screen: 'Calendar');
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CalendarScreen()),
                    ).then((_) { if (mounted) _loadTodayActivities(); });
                  },
                  child: Row(
                    children: [
                      Text(
                        'View Calendar',
                        style: TextStyle(fontSize: 11, color: Colors.blue[400]),
                      ),
                      Icon(Icons.arrow_forward_ios, size: 10, color: Colors.blue[300]),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFE3F2FD)),
          // Body
          if (_isTodayActivitiesLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4988C4)),
                ),
              ),
            )
          else if (_todayEvents.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: Text(
                  'No activities scheduled for today',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[400],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            )
          else
            ...List.generate(_todayEvents.length, (i) => Column(
              children: [
                if (i > 0) const Divider(height: 1, indent: 14, endIndent: 14, color: Color(0xFFE3F2FD)),
                _todayEvents[i] is Activity
                    ? _buildActivityCard(_todayEvents[i] as Activity)
                    : _buildDocumentEventCard(_todayEvents[i] as Document),
              ],
            )),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildActivityCard(Activity activity) {
    return InkWell(
      onTap: () {
        UserActivityService().logAction(action: 'Viewed activity from home', screen: 'Home');
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CalendarScreen(initialActivity: activity),
          ),
        );
      },
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            // Time badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFE3F2FD),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _formatTime(activity.startTime),
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF1565C0),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Title + location
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    activity.title ?? 'Activity',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (activity.location != null && activity.location!.isNotEmpty)
                    Row(
                      children: [
                        Icon(Icons.location_on_outlined, size: 11, color: Colors.grey[500]),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            activity.location!,
                            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentEventCard(Document doc) {
    return InkWell(
      onTap: () {
        UserActivityService().logAction(action: 'Viewed document event from home', screen: 'Home');
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CalendarScreen(initialDocument: doc),
          ),
        );
      },
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _formatTime(doc.calendarDeadline!),
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF2E7D32),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    doc.title ?? doc.code,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    doc.type,
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  Widget _buildFolderButton(
    BuildContext context,
    IconData icon,
    String title,
    Gradient gradient,
    VoidCallback onTap,
  ) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.transparent,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        padding: EdgeInsets.zero,
        elevation: 4,
      ),
      child: Ink(
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          child: Column(
            children: [
              Icon(icon, size: 48, color: Colors.white),
              Icon(Icons.arrow_forward, size: 16, color: Colors.white.withOpacity(0.7)),
              const SizedBox(height: 12),
              Text(
                title,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 18 * MediaQuery.of(context).textScaleFactor,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPill(String label, String emoji, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF616161),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        elevation: 4,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 4),
          Text(
            emoji,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ],
      ),
    );
  }





 

  void _showForm(BuildContext context, bool incoming) async {
    UserActivityService().logAction(
      action: 'Opened Add Document screen',
      screen: incoming ? 'Incoming Documents' : 'Outgoing Documents',
    );
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddDocumentScreen(incoming: incoming),
      ),
    );
    await Future.wait([_loadDocuments(), _loadTodayActivities()]);
  }

  void _showResolutionsForm(BuildContext context) async {
    UserActivityService().logAction(action: 'Opened screen', screen: 'Add Resolution');
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AddResolutionScreen(),
      ),
    );
    await Future.wait([_loadDocuments(), _loadTodayActivities()]);
  }

  void _showAttendanceMovForm(BuildContext context) async {
    UserActivityService().logAction(action: 'Opened screen', screen: 'Add Attendance / MOV');
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AddAttendanceMovScreen(),
      ),
    );
    await Future.wait([_loadDocuments(), _loadTodayActivities()]);
  }

  void _showLocationalZoningForm(BuildContext context) async {
    UserActivityService().logAction(action: 'Opened screen', screen: 'Add Locational / Zoning');
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AddLocationalZoningScreen(),
      ),
    );
    await Future.wait([_loadDocuments(), _loadTodayActivities()]);
  }

  void _showCdcForm(BuildContext context) async {
    UserActivityService().logAction(action: 'Opened screen', screen: 'Add CDC Document');
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AddCdcScreen(),
      ),
    );
    await Future.wait([_loadDocuments(), _loadTodayActivities()]);
  }

  void _showSpDocumentsForm(BuildContext context) async {
    UserActivityService().logAction(action: 'Opened screen', screen: 'Add SP Document');
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AddSpDocumentsScreen(),
      ),
    );
    await Future.wait([_loadDocuments(), _loadTodayActivities()]);
  }

  void _showReclassificationForm(BuildContext context) async {
    UserActivityService().logAction(action: 'Opened screen', screen: 'Add Reclassification');
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AddReclassificationScreen(),
      ),
    );
    await Future.wait([_loadDocuments(), _loadTodayActivities()]);
  }

  Future<void> _testNotification() async {
    try {
      final notificationService = NotificationService();
      await notificationService.showTestNotification();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Test notification sent!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send test notification: $e')),
      );
    }
  }

  Future<void> _checkAndRequestNotificationPermission() async {
    if (!kIsWeb) return; // Only for web

    try {
      final notificationService = NotificationService();
      final permissions = await notificationService.checkPermissions();
      final isGranted = permissions['notification'] ?? false;

      if (!isGranted) {
        // Show dialog to request permission
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Text('Enable Notifications'),
              content: const Text(
                'This app uses notifications to keep you updated on important document deadlines and updates. '
                'Would you like to enable notifications?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Not Now'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    try {
                      await notificationService.requestNotificationPermission();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Notification permission requested')),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to request permission: $e')),
                      );
                    }
                  },
                  child: const Text('Enable'),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
    }
  }

  Future<void> _checkPermissions() async {
    try {
      final notificationService = NotificationService();
      final permissions = await notificationService.checkPermissions();
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Notification Permissions'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Notification: ${(permissions['notification'] ?? false) ? 'Granted' : 'Denied'}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to check permissions: $e')),
      );
    }
  }

  Future<void> _showNotificationSettings() async {
    final notificationService = NotificationService();
    final currentPrefs = await notificationService.getNotificationPreferences();

    bool immediate = currentPrefs['immediateNotifications'] ?? false;
    bool twentyFourHour = currentPrefs['twentyFourHourNotifications'] ?? true;
    bool overdue = currentPrefs['overdueNotifications'] ?? true;
    bool activity = currentPrefs['activityNotifications'] ?? true;
    bool assignment = currentPrefs['assignmentNotifications'] ?? true;
    bool eventReminders = currentPrefs['eventReminders'] ?? true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.notifications_outlined,
                          color: Theme.of(context).colorScheme.primary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Notification Settings',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                )),
                        Text('Choose which alerts you receive',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.grey.shade500,
                                )),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Section label
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                child: Text('COMPLIANCE',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        )),
              ),
              _notifTile(
                ctx: ctx,
                setS: setS,
                icon: Icons.flash_on_outlined,
                iconColor: Colors.orange,
                title: 'Immediate',
                subtitle: 'Notify as soon as a document needs action',
                value: immediate,
                onChanged: (v) => setS(() => immediate = v),
              ),
              _notifTile(
                ctx: ctx,
                setS: setS,
                icon: Icons.schedule_outlined,
                iconColor: Colors.blue,
                title: '24 Hours Before Deadline',
                subtitle: 'Remind a day before compliance deadlines',
                value: twentyFourHour,
                onChanged: (v) => setS(() => twentyFourHour = v),
              ),
              _notifTile(
                ctx: ctx,
                setS: setS,
                icon: Icons.warning_amber_outlined,
                iconColor: Colors.red,
                title: 'Overdue',
                subtitle: 'Alert when a compliance deadline has passed',
                value: overdue,
                onChanged: (v) => setS(() => overdue = v),
              ),
              const Divider(height: 24, indent: 20, endIndent: 20),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Text('ACTIVITY & ASSIGNMENTS',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        )),
              ),
              _notifTile(
                ctx: ctx,
                setS: setS,
                icon: Icons.today_outlined,
                iconColor: Colors.teal,
                title: 'Daily Activity Summary',
                subtitle: 'Morning push with today\'s events at 8:10 AM',
                value: activity,
                onChanged: (v) => setS(() => activity = v),
              ),
              _notifTile(
                ctx: ctx,
                setS: setS,
                icon: Icons.notifications_active_outlined,
                iconColor: Colors.indigo,
                title: 'Event Reminders',
                subtitle: 'Remind at 8:10 AM, or 1 hour before early-morning events',
                value: eventReminders,
                onChanged: (v) => setS(() => eventReminders = v),
              ),
              _notifTile(
                ctx: ctx,
                setS: setS,
                icon: Icons.person_add_alt_outlined,
                iconColor: Colors.purple,
                title: 'Assignment',
                subtitle: 'Notify when a document is addressed or transferred to you',
                value: assignment,
                onChanged: (v) => setS(() => assignment = v),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.save_outlined, size: 18),
                        label: const Text('Save'),
                        onPressed: () async {
                          try {
                            await notificationService.setNotificationPreferences(
                              immediateNotifications: immediate,
                              twentyFourHourNotifications: twentyFourHour,
                              overdueNotifications: overdue,
                              activityNotifications: activity,
                              assignmentNotifications: assignment,
                              eventReminders: eventReminders,
                            );
                            if (!ctx.mounted) return;
                            Navigator.of(ctx).pop();
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(content: Text('Notification settings saved')),
                            );
                          } catch (e) {
                            if (!ctx.mounted) return;
                            if (e.toString().contains('Notification') ||
                                e.toString().contains('permission')) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Settings saved, but notification permission is blocked')),
                              );
                              Navigator.of(ctx).pop();
                            } else {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(content: Text('Failed to save settings: $e')),
                              );
                            }
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _notifTile({
    required BuildContext ctx,
    required StateSetter setS,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: value
            ? Theme.of(ctx).colorScheme.primaryContainer.withValues(alpha: 0.35)
            : Theme.of(ctx).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setS(() => onChanged(!value)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: value
                        ? iconColor.withValues(alpha: 0.15)
                        : Colors.grey.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon,
                      size: 20,
                      color: value ? iconColor : Colors.grey.shade400),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: value
                                ? Theme.of(ctx).colorScheme.onSurface
                                : Colors.grey.shade500,
                          )),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          )),
                    ],
                  ),
                ),
                Switch(
                  value: value,
                  onChanged: (v) => setS(() => onChanged(v)),
                  activeThumbColor: Theme.of(ctx).colorScheme.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

}

class _DocumentSearchDelegate extends SearchDelegate<Document?> {
  final List<Document> documents;
  final String Function(Document) getFolderName;
  final bool urgentOnly;

  _DocumentSearchDelegate({
    required this.documents,
    required this.getFolderName,
    this.urgentOnly = false,
  });

  @override
  String get searchFieldLabel => 'Search all documents...';

  @override
  List<Widget> buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
  ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () => close(context, null),
  );

  @override
  Widget buildResults(BuildContext context) => _buildList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildList(context);

  List<Document> get _filtered {
    final base = urgentOnly
        ? documents.where((d) => d.status == 'Urgent').toList()
        : List<Document>.from(documents);
    if (query.trim().isEmpty) return base;
    return base.where((d) => documentMatchesQuery(d, query)).toList();
  }

  Widget _buildList(BuildContext context) {
    final results = _filtered;
    if (results.isEmpty) {
      return Center(
        child: Text(
          query.isEmpty ? 'Type to search documents' : 'No documents found',
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }
    return ListView.separated(
      itemCount: results.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final doc = results[i];
        final folder = getFolderName(doc);
        return ListTile(
          leading: _statusIcon(doc.status),
          title: Text(
            doc.code,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (doc.title != null && doc.title!.isNotEmpty)
                Text(
                  doc.title!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE3F2FD),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      folder,
                      style: const TextStyle(fontSize: 10, color: Color(0xFF1565C0), fontWeight: FontWeight.w500),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _statusColor(doc.status).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      doc.status,
                      style: TextStyle(fontSize: 10, color: _statusColor(doc.status), fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ],
          ),
          trailing: const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
          onTap: () => close(context, doc),
        );
      },
    );
  }

  Widget _statusIcon(String status) {
    switch (status) {
      case 'Urgent':
        return const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20);
      case 'Completed':
        return const Icon(Icons.check_circle_outline, color: Colors.green, size: 20);
      case 'For Compliance':
        return const Icon(Icons.access_time, color: Colors.orange, size: 20);
      default:
        return const Icon(Icons.description_outlined, color: Color(0xFF4988C4), size: 20);
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Urgent': return Colors.red;
      case 'Completed': return Colors.green;
      case 'For Compliance': return Colors.orange;
      default: return Colors.blueGrey;
    }
  }
}
