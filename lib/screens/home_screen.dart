import 'package:flutter/material.dart';
import '../models/document.dart';
import '../services/cached_document_service.dart';
import '../services/notification_service.dart';
import '../services/supabase_service.dart';
import '../services/connectivity_service.dart';
import '../widgets/sync_banner.dart';
import '../utils/delete_utils.dart';
import '../utils/date_time_utils.dart';
import 'add_document_screen.dart';
import 'incoming_documents_screen.dart';
import 'outgoing_documents_screen.dart';
import 'circulated_documents_screen.dart';
import 'add_flag_ceremony_screen.dart';
import 'flag_ceremony_documents_screen.dart';
import 'attendance_movs_screen.dart';
import 'add_attendance_movs_screen.dart';
import 'delete_history_screen.dart';
import 'notification_history_screen.dart';
import 'calendar_screen.dart';

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
  @override
  void initState() {
    super.initState();
    _loadDocuments();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadDocuments() async {
    try {
      final loadedDocuments = await _documentService.fetchDocuments();
      print('Loaded documents: ${loadedDocuments.map((d) => '${d.code}: incoming=${d.incoming}').toList()}');
      setState(() {
        documents = loadedDocuments;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      // Handle error - could show a snackbar
      print('Error loading documents: $e');
    }
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
      if (!documents[index].incoming) {
        documents[index].addHistoryEntry(newAssignee, transferredBy, notes: notes);
      } else {
        documents[index].transferTo(newAssignee, transferredBy, notes: notes);
      }

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

      setState(() {});
    } catch (e) {
      print('Error transferring document: $e');
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
          print('Error deleting urgent notifications: $e');
        }
      }

      // Add history entry for status change
      String statusAction = customHistoryAction ?? 'Status changed to $newStatus';
      if (customHistoryAction == null && newStatus == 'For Compliance' && complianceAssignee != null && complianceAssignee!.isNotEmpty) {
        statusAction = 'Status changed to $newStatus assigned to $complianceAssignee';
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
              print('Error recording notification history or sending notifications: $e');
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
          print('Error recording urgent notification history: $e');
        }
      }

      setState(() {});
    } catch (e) {
      print('Error updating document status: $e');
      // Could show error snackbar here
    }
  }

  Future<void> _deleteDocument(int index) async {
    final success = await confirmAndDeleteRecord(context, documents[index], _documentService);
    if (success) {
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
      print('Error syncing document: $e');
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
      print('Error syncing all documents: $e');
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
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_outlined),
            onSelected: (value) {
              if (value == 'sync') {
                _syncAllDocuments();
              } else if (value == 'calendar') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CalendarScreen(),
                  ),
                );
              } else if (value == 'delete_history') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const DeleteHistoryScreen(),
                  ),
                );
              } else if (value == 'notification_history') {
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
                  SizedBox(
                    height: 34,
                    child: Center(child: _buildUrgentIndicator()),
                  ),
                  const SizedBox(height: 16),
                  Image.asset(
                    'assets/image/officeLogo.png',
                    height: 80,
                    width: 80,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "City Planning and Development Coordinator's Office\nFile Tracking System",
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onBackground, // Neutral, classy tone
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 40),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final buttonWidth = (constraints.maxWidth - 16) / 2; // spacing 16, for 2 buttons
                      return Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        alignment: WrapAlignment.center,
                        children: [
                          SizedBox(
                            width: buttonWidth,
                            child: _buildFolderButton(
                              context,
                              Icons.folder,
                              "Incoming Documents",
                              LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFFFFE0B2), Color.fromARGB(255, 245, 183, 90)],
                              ),
                              () {
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
                                );
                              },
                            ),
                          ),
                          SizedBox(
                            width: buttonWidth,
                            child: _buildFolderButton(
                              context,
                              Icons.folder,
                              "Outgoing Documents",
                              const LinearGradient(
                                colors: [Color(0xFF89F7FE), Color(0xFF66A6FF)], 
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              () {
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
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          SizedBox(
                            width: buttonWidth,
                            child: _buildFolderButton(
                              context,
                              Icons.folder,
                              "Flag Ceremony Docs",
                              LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFFA8E6CF), Color.fromARGB(255, 129, 211, 137)],
                              ),
                              () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => FlagCeremonyDocumentsScreen(
                                      documents: documents,
                                      transferDocument: _transferDocument,
                                      updateDocumentStatus: _updateDocumentStatus,
                                      deleteDocument: _deleteDocument,
                                      syncDocument: _syncDocument,
                                      onRefresh: _loadDocuments,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          SizedBox(
                            width: buttonWidth,
                            child: _buildFolderButton(
                              context,
                              Icons.folder,
                              "Office Function MOVs",
                              LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFFD4A5FF), Color(0xFF957DAD)],
                              ),
                              () {
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
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      Align(
        alignment: Alignment.bottomLeft,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            "by: Margaux🌻",
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
              // fontStyle: FontStyle.italic,
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
                  _buildPill('Flag Ceremony', '', () {
                    _showFlagCeremonyForm(context);
                    setState(() => _showPills = false);
                  }),
                  const SizedBox(height: 8),
                  _buildPill('Function MOVs', '', () {
                    _showAttendanceMovForm(context);
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
          backgroundColor: const Color.fromARGB(255, 0, 217, 255),
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



  Widget _buildUrgentIndicator() {
    final urgentCount = documents.where((doc) => doc.status == 'Urgent').length;
    if (urgentCount == 0) {
      return const SizedBox.shrink();
    }
    return Chip(
      avatar: const Icon(Icons.warning, color: Colors.red, size: 16),
      label: Text(
        'Urgent: $urgentCount',
        style: const TextStyle(
          color: Colors.red,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
      backgroundColor: Colors.redAccent.withOpacity(0.1),
      side: BorderSide(color: Colors.redAccent.withOpacity(0.4)),
      elevation: 2,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddDocumentScreen(incoming: incoming),
      ),
    );
    // Reload documents since the add screen handles saving and uploads
    await _loadDocuments();
  }

  void _showFlagCeremonyForm(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AddFlagCeremonyScreen(),
      ),
    );
    // Reload documents since the add screen handles saving and uploads
    await _loadDocuments();
  }

  void _showAttendanceMovForm(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AddAttendanceMovScreen(),
      ),
    );
    // Reload documents since the add screen handles saving and uploads
    await _loadDocuments();
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


}
