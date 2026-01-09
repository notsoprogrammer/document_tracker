import '../models/document.dart';

/// Filters documents based on search query.
/// Searches in title, assignedTo (personnel), person (cpdco staff), remarks.
List<Document> searchDocuments(List<Document> documents, String query) {
  if (query.isEmpty) return documents;
  final lowerQuery = query.toLowerCase();
  return documents.where((doc) {
    return doc.title.toLowerCase().contains(lowerQuery) ||
           doc.assignedTo.toLowerCase().contains(lowerQuery) ||
           doc.person.toLowerCase().contains(lowerQuery) ||
           doc.remarks.toLowerCase().contains(lowerQuery);
  }).toList();
}

/// Filters documents based on selected criteria.
/// Filters by date range (using creation date from history), type, office (fromOrTo).
List<Document> filterDocuments(List<Document> documents, {
  DateTime? startDate,
  DateTime? endDate,
  String? type,
  String? office,
}) {
  return documents.where((doc) {
    // Date filter: use the first history entry timestamp as creation date
    if (startDate != null || endDate != null) {
      if (doc.history.isEmpty) return false;
      final creationDate = doc.history.first.timestamp;
      if (startDate != null && creationDate.isBefore(startDate)) return false;
      if (endDate != null && creationDate.isAfter(endDate)) return false;
    }

    // Type filter
    if (type != null && type.isNotEmpty && doc.type != type) return false;

    // Office filter (fromOrTo)
    if (office != null && office.isNotEmpty && !doc.fromOrTo.toLowerCase().contains(office.toLowerCase())) return false;

    return true;
  }).toList();
}

/// Combines search and filter operations.
List<Document> searchAndFilterDocuments(List<Document> documents, {
  String? searchQuery,
  DateTime? startDate,
  DateTime? endDate,
  String? type,
  String? office,
}) {
  // If any filter criteria are provided, apply filters-only (prioritize filters).
  final hasFilter = startDate != null || endDate != null || (type != null && type.isNotEmpty) || (office != null && office.isNotEmpty);
  if (hasFilter) {
    return filterDocuments(documents,
      startDate: startDate,
      endDate: endDate,
      type: type,
      office: office,
    );
  }

  // If a search query is provided (and no filters), perform search-only.
  if (searchQuery != null && searchQuery.trim().isNotEmpty) {
    return searchDocuments(documents, searchQuery);
  }

  // No search or filters — return original list
  return documents;
}
