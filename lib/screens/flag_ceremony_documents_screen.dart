import 'package:flutter/material.dart';
import '../models/document.dart';

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

  final List<String> _filterOptions = ['All', 'Flag Raising', 'Flag Lowering'];

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
            doc.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
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
                padding: const EdgeInsets.all(16),
                itemCount: _filteredDocuments.length,
                itemBuilder: (context, index) {
                  final document = _filteredDocuments[index];
                  return Card(
                    elevation: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      title: Text(
                        document.title,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Code: ${document.code}'),
                          Text('Type: ${document.type}'),
                          Text('Date: ${document.fromOrTo}'),
                          Text('Recorded by: ${document.person}'),
                          Text('Status: ${document.status}'),
                        ],
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          switch (value) {
                            case 'view':
                              _viewDocumentDetails(document);
                              break;
                            case 'delete':
                              _confirmDelete(index);
                              break;
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'view',
                            child: Text('View Details'),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete'),
                          ),
                        ],
                      ),
                      onTap: () => _viewDocumentDetails(document),
                    ),
                  );
                },
              ),
      ),
    );
  }

  void _viewDocumentDetails(Document document) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(document.title),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('Code', document.code),
              _buildDetailRow('Type', document.type),
              _buildDetailRow('Date', document.fromOrTo),
              _buildDetailRow('Recorded by', document.person),
              _buildDetailRow('Status', document.status),
              if (document.remarks.isNotEmpty) _buildDetailRow('Remarks', document.remarks),
              if (document.imageUrls.isNotEmpty) _buildDetailRow('Images', '${document.imageUrls.length} attached'),
              if (document.fileUrls.isNotEmpty) _buildDetailRow('Files', '${document.fileUrls.length} attached'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  void _confirmDelete(int index) {
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
              widget.deleteDocument(widget.documents.indexOf(_filteredDocuments[index]));
              setState(() {
                _filteredDocuments.removeAt(index);
              });
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
