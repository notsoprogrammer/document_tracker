import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../models/document.dart';
import '../services/cached_document_service.dart';
import 'add_document_screen.dart';
import 'incoming_documents_screen.dart';
import 'outgoing_documents_screen.dart';

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
    'Arnie',
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
    try {
      final documentCode = documents[index].code;

      // Delete through cached service (handles both local and remote)
      await _documentService.deleteDocument(documentCode);

      // Remove from local list
      setState(() {
        documents.removeAt(index);
      });
    } catch (e) {
      print('Error deleting document: $e');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("CPDCO Document Tracker"),
      ),
      body: Container(
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
                "Document Management",
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => IncomingDocumentsScreen(
                              documents: documents,
                              transferDocument: _transferDocument,
                              updateDocumentStatus: _updateDocumentStatus,
                              deleteDocument: _deleteDocument,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.arrow_downward, color: Colors.white),
                      label: const Text("Incoming Documents"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFB74D), // Pastel orange
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => OutgoingDocumentsScreen(
                              documents: documents,
                              transferDocument: _transferDocument,
                              updateDocumentStatus: _updateDocumentStatus,
                              deleteDocument: _deleteDocument,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.arrow_upward, color: Colors.white),
                      label: const Text("Outgoing Documents"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2196F3), // Blue complementing orange
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => _showAddMenu(context),
                icon: const Icon(Icons.add),
                label: const Text("Add New Document"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),

            ],
          ),
        ),
      ),
    );
  }

  void _showAddMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Add New Document",
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _buildAddOption(
                    context,
                    Icons.arrow_downward,
                    "Incoming",
                    "Receive documents",
                    () {
                      Navigator.pop(context);
                      _showForm(context, true);
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildAddOption(
                    context,
                    Icons.arrow_upward,
                    "Outgoing",
                    "Send documents",
                    () {
                      Navigator.pop(context);
                      _showForm(context, false);
                    },
                  ),
                ),
              ],
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

  void _showForm(BuildContext context, bool incoming) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddDocumentScreen(incoming: incoming),
      ),
    );
    if (result != null && result is Document) {
      _addDocument(result);
    }
  }
}
