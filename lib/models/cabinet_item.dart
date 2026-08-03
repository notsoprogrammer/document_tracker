import 'dart:convert';

class CabinetBorrowEntry {
  final String borrowerName;
  final DateTime borrowDate;
  final DateTime? returnDate;
  final String? notes;

  CabinetBorrowEntry({
    required this.borrowerName,
    required this.borrowDate,
    this.returnDate,
    this.notes,
  });

  factory CabinetBorrowEntry.fromJson(Map<String, dynamic> json) {
    return CabinetBorrowEntry(
      borrowerName: json['borrower_name'] ?? '',
      borrowDate: DateTime.parse(json['borrow_date']),
      returnDate: json['return_date'] != null ? DateTime.parse(json['return_date']) : null,
      notes: json['notes'],
    );
  }

  Map<String, dynamic> toJson() => {
    'borrower_name': borrowerName,
    'borrow_date': borrowDate.toIso8601String(),
    'return_date': returnDate?.toIso8601String(),
    'notes': notes,
  };
}

class CabinetItem {
  final int? id;
  final String cabinetName;
  String itemName;
  String category; // 'document' or 'supply'
  String status;   // 'available', 'borrowed', 'moved', 'removed'
  String? borrowerName;
  DateTime? borrowDate;
  String? expectedReturn;
  DateTime? actualReturnDate;
  String? movedTo;
  String? notes;
  List<CabinetBorrowEntry> borrowHistory;
  final DateTime? createdAt;
  DateTime? updatedAt;

  CabinetItem({
    this.id,
    required this.cabinetName,
    required this.itemName,
    this.category = 'document',
    this.status = 'available',
    this.borrowerName,
    this.borrowDate,
    this.expectedReturn,
    this.actualReturnDate,
    this.movedTo,
    this.notes,
    List<CabinetBorrowEntry>? borrowHistory,
    this.createdAt,
    this.updatedAt,
  }) : borrowHistory = borrowHistory ?? [];

  factory CabinetItem.fromJson(Map<String, dynamic> json) {
    List<CabinetBorrowEntry> history = [];
    final rawHistory = json['borrow_history'];
    if (rawHistory != null) {
      dynamic parsed = rawHistory is String ? jsonDecode(rawHistory) : rawHistory;
      if (parsed is List) {
        history = parsed
            .map((e) => CabinetBorrowEntry.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    }
    return CabinetItem(
      id: json['id'],
      cabinetName: json['cabinet_name'] ?? '',
      itemName: json['item_name'] ?? '',
      category: json['category'] ?? 'document',
      status: json['status'] ?? 'available',
      borrowerName: json['borrower_name'],
      borrowDate: json['borrow_date'] != null ? DateTime.parse(json['borrow_date']) : null,
      expectedReturn: json['expected_return'],
      actualReturnDate: json['actual_return_date'] != null ? DateTime.parse(json['actual_return_date']) : null,
      movedTo: json['moved_to'],
      notes: json['notes'],
      borrowHistory: history,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at']) : null,
    );
  }

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'cabinet_name': cabinetName,
    'item_name': itemName,
    'category': category,
    'status': status,
    'borrower_name': borrowerName,
    'borrow_date': borrowDate?.toIso8601String(),
    'expected_return': expectedReturn,
    'actual_return_date': actualReturnDate?.toIso8601String(),
    'moved_to': movedTo,
    'notes': notes,
    'borrow_history': borrowHistory.map((e) => e.toJson()).toList(),
  };
}
