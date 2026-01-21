import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../models/document.dart';
import '../services/cached_document_service.dart';
import '../widgets/sync_banner.dart';
import '../utils/delete_utils.dart';
import 'add_document_screen.dart';
import 'incoming_documents_screen.dart';
import 'outgoing_documents_screen.dart';
import 'flag_ceremony_screen.dart';
import 'add_flag_ceremony_screen.dart';
import 'flag_ceremony_documents_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final CachedDocumentService _documentService = CachedDocumentService();
  List<Document> documents = [];
  bool _isLoading = true;
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

  String _generateCode(bool incoming) {
    final now = DateTime.now();
    final year = now.year;
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final timestamp = now.millisecondsSinceEpoch.toString().substring(8); // Last 4 digits
    final prefix = incoming ? 'IDL' : 'ODL';
    return '$prefix$year-$month-$day-$timestamp';
  }

  Future<void> _addDocument(Document doc) async {
    try {
      // Add initial history entry
      final historyAction = doc.incoming ? 'Document Received' : 'Created and forwarded to ${doc.fromOrTo} c/o ${doc.assignedTo}';
      doc.addHistoryEntry(historyAction, doc.person, notes: "${doc.fromOrTo}|${doc.assignedTo}");

      // Save to cached service (handles both local and remote)
      final savedDoc = await _documentService.createDocument(doc);

      setState(() {
        documents.add(savedDoc);
      });
    } catch (e) {
      print('Error adding document: $e');
      // Could show error snackbar here
    }
  }

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
        timestamp: DateTime.now(),
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

  Future<void> _updateDocumentStatus(int index, String newStatus, String updatedBy, {String? notes}) async {
    try {
      // Update local document
      documents[index].updateStatus(newStatus, updatedBy, notes: notes);

      // Update through cached service (handles both local and remote)
      Map<String, dynamic> updates = {'status': newStatus};

      // Add history entry for both incoming and outgoing documents
      await _documentService.addHistoryEntry(documents[index].code, HistoryEntry(
        action: 'Status changed to $newStatus',
        person: updatedBy,
        timestamp: DateTime.now(),
        notes: notes,
      ), personnel: updatedBy);

      // Update the document
      await _documentService.updateDocument(documents[index].code, updates);

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

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays == 0) {
      return "Today ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}";
    } else if (difference.inDays == 1) {
      return "Yesterday ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}";
    } else if (difference.inDays < 7) {
      return "${difference.inDays} days ago";
    } else {
      return "${dateTime.month}/${dateTime.day}/${dateTime.year}";
    }
  }

  String _formatDateTimeForStorage(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays == 0) {
      return "Today ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}";
    } else if (difference.inDays == 1) {
      return "Yesterday ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}";
    } else if (difference.inDays < 7) {
      return "${difference.inDays} days ago";
    } else {
      return "${dateTime.month}/${dateTime.day}/${dateTime.year}";
    }
  }

  void _showAddMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Add New Document',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildAddOption(
                  context,
                  Icons.arrow_downward,
                  "Incoming",
                  "Receive document",
                  () {
                    Navigator.pop(context);
                    _showForm(context, true);
                  },
                ),
                _buildAddOption(
                  context,
                  Icons.arrow_upward,
                  "Outgoing",
                  "Send document",
                  () {
                    Navigator.pop(context);
                    _showForm(context, false);
                  },
                ),
                _buildAddOption(
                  context,
                  Icons.flag,
                  "Flag Ceremony",
                  "Attendance",
                  () {
                    Navigator.pop(context);
                    _showFlagCeremonyForm(context);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SyncBanner(
      child: Scaffold(
        appBar: AppBar(
        title: const Text("FileTrack Hub"),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: _syncAllDocuments,
            tooltip: 'Sync All Documents',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadDocuments,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Theme.of(context).colorScheme.surface,
                Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
              ],
            ),
          ),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),
                  Image.asset(
                    'assets/image/officeLogo.png',
                    height: 80,
                    width: 80,
                  ),
                  const SizedBox(height: 16),
                Text(
                  "City Planning and Development Coordinator's Office\nFile Tracking System",
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onBackground, // Neutral, classy tone
                  ),
                ),
                  const SizedBox(height: 40),
                  Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _buildFolderButton(
                              context,
                              Icons.folder,
                              "Incoming Documents",
                              const Color(0xFFFFB74D), // Pastel orange
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
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildFolderButton(
                              context,
                              Icons.folder,
                              "Outgoing Documents",
                              const Color(0xFF2196F3), // Blue complementing orange
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
                        ],
                      ),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: MediaQuery.of(context).size.width * 0.43,
                          child: _buildFolderButton(
                            context,
                            Icons.folder,
                            "Flag Ceremony",
                            const Color(0xFF4EC377), // Soft green
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
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _showAddMenu(context),
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          child: const Icon(Icons.add),
        ),
      ),
    );
  }



  Widget _buildFolderButton(BuildContext context, IconData icon, String title, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, size: 48, color: Colors.white),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddOption(BuildContext context, IconData icon, String title, String subtitle, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, size: 32, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(subtitle, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6))),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactAddOption(BuildContext context, IconData icon, String title, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, size: 24, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 4),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          ],
        ),
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
}
