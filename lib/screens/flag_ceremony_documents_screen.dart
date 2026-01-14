import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/document.dart';
import '../services/upload_queue_manager.dart';
import '../utils/snackbar_utils.dart';

class FlagCeremonyDocumentsScreen extends StatefulWidget {
  final List<Document> documents;
  final Function(int, String, String, {String? notes}) transferDocument;
  final Function(int, String, String, {String? notes}) updateDocumentStatus;
  final Function(int) deleteDocument;
  final Function(String) syncDocument;

  const FlagCeremonyDocumentsScreen({
    super.key,
    required this.documents,
    required this.transferDocument,
    required this.updateDocumentStatus,
    required this.deleteDocument,
    required this.syncDocument,
  });

  @override
  State<FlagCeremonyDocumentsScreen> createState() => _FlagCeremonyDocumentsScreenState();
}

class _FlagCeremonyDocumentsScreenState extends State<FlagCeremonyDocumentsScreen> {
  late List<Document> _filteredDocuments;
  String _searchQuery = '';
  String _selectedFilter = 'All';
  final Set<int> _expandedTiles = {};

  final List<String> _filterOptions = ['All', 'Flag Raising', 'Flag Lowering'];

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

  @override
  void initState() {
    super.initState();
    _filteredDocuments = widget.documents.where((doc) => doc.mode == 'Flag Ceremony').toList();
  }

  void _filterDocuments() {
    setState(() {
      _filteredDocuments = widget.documents.where((doc) {
        if (doc.mode != 'Flag Ceremony') return false;

        // Search filter
        bool matchesSearch = _searchQuery.isEmpty ||
            doc.code.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            doc.type.toLowerCase().contains(_searchQuery.toLowerCase());

        // Type filter
        bool matchesFilter = _selectedFilter == 'All' || doc.type == _selectedFilter;

        return matchesSearch && matchesFilter;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Flag Ceremony Documents"),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(120),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Search documents...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (value) {
                    _searchQuery = value;
                    _filterDocuments();
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _selectedFilter,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  items: _filterOptions.map((filter) => DropdownMenuItem(
                    value: filter,
                    child: Text(filter),
                  )).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      _selectedFilter = value;
                      _filterDocuments();
                    }
                  },
                ),
              ],
            ),
          ),
        ),
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
        child: _filteredDocuments.isEmpty
            ? const Center(
                child: Text(
                  'No Flag Ceremony documents found',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
                itemCount: _filteredDocuments.length,
                itemBuilder: (context, index) {
                  final document = _filteredDocuments[index];
                  final originalIndex = widget.documents.indexOf(document);
                  final queueManager = UploadQueueManager();
                  final pendingUploads = queueManager.getPendingUploads(document.code);
                  final uploadingUploads = queueManager.getAllItems().where((item) =>
                    item['documentCode'] == document.code && item['status'] == 'uploading'
                  ).toList();

                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    elevation: 2,
                    child: ExpansionTile(
                      onExpansionChanged: (expanded) {
                        setState(() {
                          if (expanded) {
                            _expandedTiles.add(index);
                          } else {
                            _expandedTiles.remove(index);
                          }
                        });
                      },
                      leading: CircleAvatar(
                        backgroundColor: document.needsSync ? Colors.red : Theme.of(context).colorScheme.primary,
                        child: Icon(
                          document.needsSync ? Icons.sync : Icons.flag,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        "${document.type}",
                        style: const TextStyle(fontWeight: FontWeight.w400),
                      ),
                      subtitle: Row(
                        children: [
                          Text("${document.code}  "),
                          if (_expandedTiles.contains(index))
                            IconButton(
                              icon: const Icon(Icons.copy, size: 16),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: document.code));
                              SnackbarUtils.showInfoSnackBar(context, 'Code copied to clipboard');
                            },
                              tooltip: 'Copy Code',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
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
                              _buildDetailRow(Icons.calendar_today, "Date", document.fromOrTo),
                              const SizedBox(height: 8),
                              _buildDetailRow(Icons.person, "Recorded by", document.person),
                              const SizedBox(height: 8),
                              _buildDetailRow(Icons.info, "Status", document.status),
                              if (document.remarks.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                _buildDetailRow(Icons.comment, "Remarks", document.remarks),
                              ],
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                alignment: WrapAlignment.center,
                                children: [
                                  ElevatedButton.icon(
                                    icon: const Icon(Icons.delete),
                                    label: const Text("Delete"),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color.fromARGB(255, 218, 87, 78),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    onPressed: () => _confirmDelete(originalIndex),
                                  ),
                                  if (document.imageUrls.isNotEmpty || document.localImagePaths.isNotEmpty)
                                    ElevatedButton.icon(
                                      icon: const Icon(Icons.image),
                                      label: const Text("View Image"),
                                      onPressed: () => _showImageDialog(context, document.imageUrls.isNotEmpty ? document.imageUrls : document.localImagePaths),
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                    ),
                                  if (document.filePath != null)
                                    ElevatedButton.icon(
                                      icon: const Icon(Icons.attach_file),
                                      label: const Text("View File"),
                                      onPressed: () => _viewFile(document.filePath!),
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                    ),
                                  ...document.fileUrls.map((url) => ElevatedButton.icon(
                                    icon: const Icon(Icons.attach_file),
                                    label: const Text("View File"),
                                    onPressed: () => _viewFile(url),
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  )),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }



  void _confirmDelete(int originalIndex) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Document'),
        content: const Text('Are you sure you want to delete this Flag Ceremony document?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              widget.deleteDocument(originalIndex);
              setState(() {
                _filteredDocuments.removeWhere((doc) => widget.documents.indexOf(doc) == originalIndex);
              });
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showImageDialog(BuildContext context, List<String> imageUrls) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (_) => Dialog(
        backgroundColor: Colors.black.withOpacity(0.8),
        insetPadding: const EdgeInsets.all(14),
        child: SizedBox.expand(
          child: Stack(
            children: [
              PageView.builder(
                itemCount: imageUrls.length,
                itemBuilder: (context, index) {
                  return InteractiveViewer(
                    child: Center(
                      child: Image.network(
                        imageUrls[index],
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 16),
                                Text(
                                  'wait la po...',
                                  style: TextStyle(color: Colors.white, fontSize: 16),
                                ),
                              ],
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return const Center(child: Text('Failed to load image'));
                        },
                      ),
                    ),
                  );
                },
              ),
              Positioned(
                top: 40,
                right: 20,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 30),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _viewFile(String filePath) async {
    final uri = Uri.parse(filePath);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      // Handle error
    }
  }
}
