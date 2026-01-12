import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/document.dart';

class SupabaseService {
  final SupabaseClient _client = Supabase.instance.client;

  // Documents table operations
  Future<List<Document>> fetchDocuments() async {
    try {
      print('Fetching documents from Supabase...');
      final response = await _client.from('documents').select('*');
      print('Raw response: $response');

      final documents = response.map((doc) => Document.fromJson(doc)).toList();

      print('Parsed ${documents.length} documents');
      return documents;
    } catch (e) {
      print('Error fetching documents: $e');
      return [];
    }
  }

  Future<Document> createDocument(Document document) async {
    final docData = document.toJson();
    docData.remove('history'); // Remove history as it's stored separately

    print('Creating document with data: $docData'); // Debug log

    final response = await _client.from('documents').insert(docData).select().single();

    print('Document created successfully: $response'); // Debug log

    // Create initial history entry
    if (document.history.isNotEmpty) {
      await _client.from('history_entries').insert(
        document.history.map((entry) => {
          'document_code': response['code'],
          'personnel': entry.person, // Set personnel to the person who performed the action
          ...entry.toJson(),
        }).toList()
      );
    }

    return Document.fromJson(response)..history.addAll(document.history);
  }

  Future<void> updateDocument(String documentCode, Map<String, dynamic> updates) async {
    await _client.from('documents').update(updates).eq('code', documentCode);
  }

  Future<void> deleteDocument(String documentCode) async {
    await _client.from('documents').delete().eq('code', documentCode);
  }

  // History operations - simplified to work with existing table structure
  Future<void> addHistoryEntry(String documentCode, HistoryEntry entry, {String? personnel}) async {
    // For now, history is handled by the Document model locally
    // In the future, this could be extended to store history in a separate table
    print('History entry added locally for document $documentCode: ${entry.action}');
  }

  Future<List<HistoryEntry>> fetchHistory(String documentCode) async {
    // Return empty list for now - history is handled by Document model
    return [];
  }
}
