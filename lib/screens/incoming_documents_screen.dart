import 'package:flutter/material.dart';
import '../models/document.dart';

class IncomingDocumentsScreen extends StatefulWidget {
  final List<Document> documents;
  final Function(int, String, String, {String? notes}) transferDocument;
  final Function(int, String, String, {String? notes}) updateDocumentStatus;

  const IncomingDocumentsScreen({
    super.key,
    required this.documents,
    required this.transferDocument,
    required this.updateDocumentStatus,
  });

  @override
  State<IncomingDocumentsScreen> createState() => _IncomingDocumentsScreenState();
}

class _IncomingDocumentsScreenState extends State<IncomingDocumentsScreen> {
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

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 12,
                ),
              ),
              Text(value, style: const TextStyle(fontSize: 14)),
            ],
          ),
        ),
      ],
    );
  }

  void _showTransferDialog(BuildContext context, int index) {
    final newAssigneeController = TextEditingController();
    final transferredByController = TextEditingController();
    final notesController = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Transfer Document"),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: newAssigneeController,
                decoration: const InputDecoration(labelText: "New Assignee"),
              ),
              TextField(
                controller: transferredByController,
                decoration: const InputDecoration(labelText: "Transferred By"),
              ),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(labelText: "Notes (Optional)"),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            child: const Text("Transfer"),
            onPressed: () {
              if (newAssigneeController.text.isNotEmpty && transferredByController.text.isNotEmpty) {
                widget.transferDocument(
                  index,
                  newAssigneeController.text,
                  transferredByController.text,
                  notes: notesController.text.isNotEmpty ? notesController.text : null,
                );
                Navigator.pop(context);
              }
            },
          ),
        ],
      ),
    );
  }

  void _showStatusUpdateDialog(BuildContext context, int index) {
    String? selectedStatus;
    final updatedByController = TextEditingController();
    final notesController = TextEditingController();

    final List<String> statusOptions = [
      'Pending',
      'Received',
      'In Progress',
      'Under Review',
      'Approved',
      'Rejected',
      'Returned',
      'Completed',
      'Archived'
    ];

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text("Update Document Status"),
          content: SingleChildScrollView(
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  value: selectedStatus,
                  decoration: const InputDecoration(labelText: "New Status"),
                  items: statusOptions.map((status) => DropdownMenuItem(value: status, child: Text(status))).toList(),
                  onChanged: (value) => setState(() => selectedStatus = value),
                ),
                TextField(
                  controller: updatedByController,
                  decoration: const InputDecoration(labelText: "Updated By"),
                ),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(labelText: "Notes (Optional)"),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              child: const Text("Update"),
              onPressed: () {
                if (selectedStatus != null && updatedByController.text.isNotEmpty) {
                  widget.updateDocumentStatus(
                    index,
                    selectedStatus!,
                    updatedByController.text,
                    notes: notesController.text.isNotEmpty ? notesController.text : null,
                  );
                  Navigator.pop(context);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final incomingDocuments = widget.documents.where((doc) => doc.incoming).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Incoming Documents"),
        backgroundColor: const Color(0xFFFFB74D), // Pastel orange
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              // TODO: Implement search functionality
            },
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () {
              // TODO: Implement filter functionality
            },
          ),
        ],
      ),
      body: incomingDocuments.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.document_scanner,
                    size: 80,
                    color: const Color(0xFFFFB74D).withOpacity(0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "No incoming documents yet",
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Incoming documents will appear here",
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                        ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 80),
              itemCount: incomingDocuments.length,
              itemBuilder: (context, index) {
                final doc = incomingDocuments[index];
                final originalIndex = widget.documents.indexOf(doc);
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  elevation: 2,
                  child: ExpansionTile(
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFFFFB74D),
                      child: const Icon(
                        Icons.arrow_downward,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      "${doc.code} - ${doc.title}",
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Row(
                      children: [
                        Icon(
                          Icons.input,
                          size: 16,
                          color: const Color(0xFFFFB74D),
                        ),
                        const SizedBox(width: 4),
                        Text("Incoming • ${doc.type}"),
                      ],
                    ),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(12),
                            bottomRight: Radius.circular(12),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildDetailRow(Icons.person, "From", doc.fromOrTo),
                            const SizedBox(height: 8),
                            _buildDetailRow(Icons.send, "Mode", doc.mode),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildDetailRow(Icons.assignment_ind, "Assigned To", doc.assignedTo),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.swap_horiz),
                                  onPressed: () => _showTransferDialog(context, originalIndex),
                                  tooltip: "Transfer Document",
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildDetailRow(Icons.info, "Status", doc.status),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  onPressed: () => _showStatusUpdateDialog(context, originalIndex),
                                  tooltip: "Update Status",
                                ),
                              ],
                            ),
                            if (doc.filePath != null) ...[
                              const SizedBox(height: 8),
                              _buildDetailRow(Icons.attach_file, "Attachment", doc.filePath!.split('/').last),
                            ],
                            const SizedBox(height: 8),
                            _buildDetailRow(Icons.comment, "Remarks", doc.remarks),
                            const SizedBox(height: 8),
                            _buildDetailRow(Icons.receipt, "Received by", doc.person),
                            const SizedBox(height: 16),
                            ExpansionTile(
                              title: Text(
                                "Document History (${doc.history.length})",
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                              ),
                              leading: const Icon(Icons.history),
                              children: doc.history.isEmpty
                                  ? [const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Text("No history available"),
                                    )]
                                  : doc.history.map((entry) => Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Icon(
                                            Icons.circle,
                                            size: 12,
                                            color: const Color(0xFFFFB74D),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  entry.action,
                                                  style: const TextStyle(fontWeight: FontWeight.w500),
                                                ),
                                                Text(
                                                  "by ${entry.person} • ${_formatDateTime(entry.timestamp)}",
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                                  ),
                                                ),
                                                if (entry.notes != null && entry.notes!.isNotEmpty) ...[
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    "Notes: ${entry.notes}",
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontStyle: FontStyle.italic,
                                                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    )).toList(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
