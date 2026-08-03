import '../models/document.dart';
import 'document_search.dart';

/// Filters documents based on search query.
/// Field list lives in [documentMatchesQuery] so every screen searches alike.
List<Document> searchDocuments(List<Document> documents, String query) {
  if (query.isEmpty) return documents;
  return documents.where((doc) => documentMatchesQuery(doc, query)).toList();
}

/// Filters documents based on selected criteria.
/// Filters by date range (using creation date from history).
/// Comparison is only by DATE (ignores time of day).
List<Document> filterDocuments(
  List<Document> documents, {
  DateTime? startDate,
  DateTime? endDate,
  DateTime? specificDate,
}) {
  return documents.where((doc) {
    if (doc.history.isEmpty) return false;
    final creationDate = doc.history.first.timestamp;

    // Normalize to just the date (year, month, day)
    final docDate = DateTime(creationDate.year, creationDate.month, creationDate.day);

    if (specificDate != null) {
      final targetDate = DateTime(specificDate.year, specificDate.month, specificDate.day);
      return docDate == targetDate;
    }

    if (startDate != null) {
      final start = DateTime(startDate.year, startDate.month, startDate.day);
      if (docDate.isBefore(start)) return false;
    }

    if (endDate != null) {
      final end = DateTime(endDate.year, endDate.month, endDate.day);
      if (docDate.isAfter(end)) return false;
    }

    return true;
  }).toList();
}

/// Combines search and filter operations.
/// Date filter is independent of search.
List<Document> searchAndFilterDocuments(
  List<Document> documents, {
  String? searchQuery,
  DateTime? startDate,
  DateTime? endDate,
  DateTime? specificDate,
}) {
  List<Document> result = documents;

  // Apply date filters first
  if (startDate != null || endDate != null || specificDate != null) {
    result = filterDocuments(
      result,
      startDate: startDate,
      endDate: endDate,
      specificDate: specificDate,
    );
  }

  // Then apply search if query is provided
  if (searchQuery != null && searchQuery.trim().isNotEmpty) {
    result = searchDocuments(result, searchQuery);
  }

  return result;
}
