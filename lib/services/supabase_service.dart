import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/document.dart';

class SupabaseService {
  final SupabaseClient _client = Supabase.instance.client;

  // Documents table operations
  Future<List<Document>> fetchDocuments() async {
    try {
      print('Fetching documents from Supabase...');
      final response = await _client.from('documents').select('''
        *,
        history:history_entries(*)
      ''');
      print('Raw response: $response');

      final documents = response.map((doc) {
        final history = (doc['history'] as List<dynamic>?)
            ?.map((entry) => HistoryEntry.fromJson(entry))
            .toList() ?? [];
        return Document.fromJson(doc)..history.addAll(history);
      }).toList();

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

    final response = await _client.from('documents').insert(docData).select().single();

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

  // History operations
  Future<void> addHistoryEntry(String documentCode, HistoryEntry entry, {String? personnel}) async {
    try {
      print('Adding history entry for document $documentCode: ${entry.action}');
      await _client.from('history_entries').insert({
        'document_code': documentCode,
        'personnel': personnel,
        ...entry.toJson(),
      });
      print('History entry added successfully');
    } catch (e) {
      print('Error adding history entry: $e');
      rethrow;
    }
  }

  Future<List<HistoryEntry>> fetchHistory(String documentCode) async {
    final response = await _client
        .from('history_entries')
        .select()
        .eq('document_code', documentCode)
        .order('timestamp', ascending: true);

    return response.map((entry) => HistoryEntry.fromJson(entry)).toList();
  }
}
