import 'package:flutter/material.dart';
import '../models/document.dart';
import '../services/cached_document_service.dart';
import '../widgets/sync_banner.dart';
import '../utils/delete_utils.dart';
import '../utils/date_time_utils.dart';
import 'add_document_screen.dart';
import 'incoming_documents_screen.dart';
import 'outgoing_documents_screen.dart';
import 'add_flag_ceremony_screen.dart';
import 'flag_ceremony_documents_screen.dart';
import 'delete_history_screen.dart';

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
        timestamp: getPhilippineTime(),
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
              } else if (value == 'more') {
                _showSidebar(context);
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
                value: 'more',
                child: ListTile(
                  leading: Icon(Icons.more_horiz_outlined),
                  title: Text('More Options'),
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
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onBackground, // Neutral, classy tone
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 40),
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    alignment: WrapAlignment.center,
                    children: [
                      SizedBox(
                        width: 150,
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
                      SizedBox(
                        width: 150,
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
                      SizedBox(
                        width: 150,
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
                    ],
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
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
        duration: const Duration(milliseconds: 300),
        child: _showPills
            ? Column(
                key: const ValueKey('pills'),
                crossAxisAlignment: CrossAxisAlignment.end, // ✅ keep pills right-aligned
                children: [
                  _buildPill('Incoming', '📥', () {
                    _showForm(context, true);
                    setState(() => _showPills = false);
                  }),
                  const SizedBox(height: 8),
                  _buildPill('Outgoing', '📤', () {
                    _showForm(context, false);
                    setState(() => _showPills = false);
                  }),
                  const SizedBox(height: 8),
                  _buildPill('Flag Ceremony', '🚩', () {
                    _showFlagCeremonyForm(context);
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
          backgroundColor: Theme.of(context).colorScheme.primary,
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



  Widget _buildFolderButton(BuildContext context, IconData icon, String title, Color color, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        padding: EdgeInsets.zero,
        elevation: 4,
      ),
      child: Card(
        color: color,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          child: Column(
            children: [
              Icon(icon, size: 48, color: Colors.white),
              Icon(Icons.arrow_forward, size: 16, color: Colors.white.withOpacity(0.7)),
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

  void _showSidebar(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Material(
        elevation: 8,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.more_horiz,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Options',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              // Menu Items
              ...ListTile.divideTiles(
                context: context,
                tiles: [
                  ListTile(
                    leading: Icon(
                      Icons.history,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    title: const Text('Delete History'),
                    subtitle: const Text('View deletion logs'),
                    onTap: () {
                      Navigator.pop(context); // Close bottom sheet
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const DeleteHistoryScreen(),
                        ),
                      );
                    },
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  ),
                  // Add more menu items here if needed
                ],
              ).toList(),
            ],
          ),
        ),
      ),
    );
  }
}
