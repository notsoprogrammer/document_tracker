import 'package:flutter/material.dart';
import '../models/document.dart';
import '../services/cached_document_service.dart';
import '../widgets/connectivity_banner.dart';

class FlagCeremonyScreen extends StatefulWidget {
  const FlagCeremonyScreen({super.key});

  @override
  State<FlagCeremonyScreen> createState() => _FlagCeremonyScreenState();
}

class _FlagCeremonyScreenState extends State<FlagCeremonyScreen> {
  final CachedDocumentService _documentService = CachedDocumentService();
  List<Document> documents = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDocuments();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh documents when returning to this screen
    _loadDocuments();
  }

  Future<void> _loadDocuments() async {
    try {
      final loadedDocuments = await _documentService.fetchDocuments();
      // Filter for flag ceremony documents by mode
      setState(() {
        documents = loadedDocuments.where((doc) => doc.mode == 'Flag Ceremony').toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConnectivityBanner(
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Flag Ceremony Records"),
        ),
        body: RefreshIndicator(
          onRefresh: _loadDocuments,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : documents.isEmpty
                  ? const Center(child: Text("No flag ceremony records found."))
                  : ListView.builder(
                      itemCount: documents.length,
                      itemBuilder: (context, index) {
                        final doc = documents[index];
                        return ListTile(
                          title: Text(doc.code),
                          subtitle: Text(doc.remarks.isNotEmpty ? doc.remarks : 'No remarks'),
                          trailing: Text(doc.status),
                        );
                      },
                    ),
        ),
      ),
    );
  }
}
