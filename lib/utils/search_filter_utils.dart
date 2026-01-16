import '../models/document.dart';

/// Filters documents based on search query.
/// Searches in title, assignedTo (personnel), person (cpdco staff), remarks, notes (from history), type, office (fromOrTo), status.
List<Document> searchDocuments(List<Document> documents, String query) {
  if (query.isEmpty) return documents;
  final lowerQuery = query.toLowerCase();
  return documents.where((doc) {
    return
           (doc.title?.toLowerCase().contains(lowerQuery) ?? false) ||
           doc.assignedTo.toLowerCase().contains(lowerQuery) ||
           doc.person.toLowerCase().contains(lowerQuery) ||
           doc.remarks.toLowerCase().contains(lowerQuery) ||
           doc.history.any((entry) => entry.notes?.toLowerCase().contains(lowerQuery) ?? false) ||
           doc.mode.toLowerCase().contains(lowerQuery) ||
           doc.type.toLowerCase().contains(lowerQuery) ||
           doc.fromOrTo.toLowerCase().contains(lowerQuery) ||
           doc.status.toLowerCase().contains(lowerQuery) ||
           doc.code.toLowerCase().contains(lowerQuery);
  }).toList();
}

/// Filters documents based on selected criteria.
/// Filters by date range (using creation date from history).
List<Document> filterDocuments(List<Document> documents, {
  DateTime? startDate,
  DateTime? endDate,
}) {
  return documents.where((doc) {
    // Date filter: use the first history entry timestamp as creation date
    if (startDate != null || endDate != null) {
      if (doc.history.isEmpty) return false;
      final creationDate = doc.history.first.timestamp;
      // Adjust startDate to start of day (00:00:00)
      final adjustedStartDate = startDate != null
          ? DateTime(startDate.year, startDate.month, startDate.day)
          : null;
      // Adjust endDate to end of day (23:59:59)
      final adjustedEndDate = endDate != null
          ? DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59)
          : null;
      if (adjustedStartDate != null && creationDate.isBefore(adjustedStartDate)) return false;
      if (adjustedEndDate != null && creationDate.isAfter(adjustedEndDate)) return false;
    }

    return true;
  }).toList();
}

/// Combines search and filter operations.
List<Document> searchAndFilterDocuments(List<Document> documents, {
  String? searchQuery,
  DateTime? startDate,
  DateTime? endDate,
}) {
  List<Document> result = documents;

  // Apply date filters first if provided
  final hasFilter = startDate != null || endDate != null;
  if (hasFilter) {
    result = filterDocuments(result,
      startDate: startDate,
      endDate: endDate,
    );
  }

  // Then apply search if query is provided
  if (searchQuery != null && searchQuery.trim().isNotEmpty) {
    result = searchDocuments(result, searchQuery);
  }

  return result;
}
