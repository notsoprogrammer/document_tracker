import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/cabinet_item.dart';

// SQL to create the table in Supabase (run once in SQL editor):
//
// CREATE TABLE IF NOT EXISTS cabinet_items (
//   id           BIGSERIAL PRIMARY KEY,
//   cabinet_name TEXT NOT NULL,
//   item_name    TEXT NOT NULL,
//   category     TEXT DEFAULT 'document',
//   status       TEXT DEFAULT 'available',
//   borrower_name TEXT,
//   borrow_date  TIMESTAMPTZ,
//   expected_return TEXT,
//   actual_return_date TIMESTAMPTZ,
//   moved_to     TEXT,
//   notes        TEXT,
//   borrow_history JSONB DEFAULT '[]',
//   created_at   TIMESTAMPTZ DEFAULT NOW(),
//   updated_at   TIMESTAMPTZ DEFAULT NOW()
// );

class CabinetService {
  final SupabaseClient _client = Supabase.instance.client;
  static const _table = 'cabinet_items';

  Future<List<CabinetItem>> fetchAll() async {
    try {
      final response = await _client
          .from(_table)
          .select()
          .order('cabinet_name')
          .order('item_name');
      return (response as List).map((e) => CabinetItem.fromJson(e)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<CabinetItem?> fetchById(int id) async {
    try {
      final response = await _client.from(_table).select().eq('id', id).single();
      return CabinetItem.fromJson(response);
    } catch (e) {
      return null;
    }
  }

  Future<CabinetItem?> addItem(CabinetItem item) async {
    try {
      final data = item.toJson()
        ..['created_at'] = DateTime.now().toIso8601String()
        ..['updated_at'] = DateTime.now().toIso8601String();
      data.remove('id');
      final response = await _client.from(_table).insert(data).select().single();
      return CabinetItem.fromJson(response);
    } catch (e) {
      return null;
    }
  }

  Future<bool> updateItem(int id, Map<String, dynamic> updates) async {
    try {
      updates['updated_at'] = DateTime.now().toIso8601String();
      await _client.from(_table).update(updates).eq('id', id);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deleteItem(int id) async {
    try {
      await _client.from(_table).delete().eq('id', id);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> borrowItem(int id, String borrowerName, String? expectedReturn, String? notes, List<CabinetBorrowEntry> existingHistory) async {
    final entry = CabinetBorrowEntry(
      borrowerName: borrowerName,
      borrowDate: DateTime.now(),
      notes: notes,
    );
    // Do not modify existingHistory list in-place; build new list
    final historyJson = [...existingHistory.map((e) => e.toJson()), entry.toJson()];
    return updateItem(id, {
      'status': 'borrowed',
      'borrower_name': borrowerName,
      'borrow_date': entry.borrowDate.toIso8601String(),
      'expected_return': expectedReturn,
      'actual_return_date': null,
      'borrow_history': historyJson,
    });
  }

  Future<bool> returnItem(int id, List<CabinetBorrowEntry> existingHistory, String borrowerName) async {
    final returnDate = DateTime.now();
    // Update the last open borrow entry for this borrower
    final updatedHistory = existingHistory.map((e) {
      if (e.returnDate == null && e.borrowerName == borrowerName) {
        return CabinetBorrowEntry(
          borrowerName: e.borrowerName,
          borrowDate: e.borrowDate,
          returnDate: returnDate,
          notes: e.notes,
        );
      }
      return e;
    }).toList();

    return updateItem(id, {
      'status': 'available',
      'borrower_name': null,
      'borrow_date': null,
      'expected_return': null,
      'actual_return_date': returnDate.toIso8601String(),
      'borrow_history': updatedHistory.map((e) => e.toJson()).toList(),
    });
  }

  Future<bool> moveItem(int id, String newCabinet, String? notes) async {
    return updateItem(id, {
      'status': 'moved',
      'moved_to': newCabinet,
      'notes': notes,
      'borrower_name': null,
      'borrow_date': null,
    });
  }

  Future<bool> removeItem(int id, String? reason) async {
    return updateItem(id, {
      'status': 'removed',
      'notes': reason,
      'borrower_name': null,
      'borrow_date': null,
    });
  }

  Future<bool> restoreItem(int id, String cabinetName) async {
    return updateItem(id, {
      'status': 'available',
      'moved_to': null,
      'cabinet_name': cabinetName,
      'borrower_name': null,
      'borrow_date': null,
    });
  }

  // Seeds initial cabinet data if the table is empty
  Future<void> seedInitialDataIfEmpty() async {
    try {
      final existing = await _client.from(_table).select('id').limit(1);
      if ((existing as List).isNotEmpty) return;

      final items = _buildSeedData();
      // Insert in batches of 50
      for (int i = 0; i < items.length; i += 50) {
        final batch = items.sublist(i, i + 50 > items.length ? items.length : i + 50);
        await _client.from(_table).insert(batch);
      }
    } catch (_) {}
  }

  List<Map<String, dynamic>> _buildSeedData() {
    final now = DateTime.now().toIso8601String();

    Map<String, dynamic> item(String cabinet, String name, String category) => {
      'cabinet_name': cabinet,
      'item_name': name,
      'category': category,
      'status': 'available',
      'borrow_history': '[]',
      'created_at': now,
      'updated_at': now,
    };

    final d = 'document';
    final s = 'supply';

    return [
      // Cabinet 1-2 (Planning Documents & References)
      item('Cabinet 1-2', 'Ecological Solid Waste Management (Household and Public Information)', d),
      item('Cabinet 1-2', 'Gender and Development', d),
      item('Cabinet 1-2', 'Local Environmental Code Formulation', d),
      item('Cabinet 1-2', "3R's of Fun in Waste", d),
      item('Cabinet 1-2', 'Annual Budget 2024', d),
      item('Cabinet 1-2', 'Comprehensive Development Plan 1978-2000 (Project Plan Reports Chapter 9)', d),
      item('Cabinet 1-2', 'Asphalt Overlay Manual', d),
      item('Cabinet 1-2', 'Project Identification, Preparation and Appraisal: Manual for Project Development Officers', d),
      item('Cabinet 1-2', 'Climate and Disaster Risk Assessment', d),
      item('Cabinet 1-2', 'FY. 2024 Financial Statements for the Period Ended Dec. 31, 2024', d),
      item('Cabinet 1-2', 'FY. 2025 Financial Statements for the Period Ended Dec. 31, 2025', d),
      item('Cabinet 1-2', 'Guidelines on the Hiring of Consultants for Government Projects (11-12-90)', d),
      item('Cabinet 1-2', 'Third Quarter 2019 RDC VIII Social Development Committee Meeting', d),
      item('Cabinet 1-2', 'Pangdan Expanded', d),
      item('Cabinet 1-2', '2017 Environmental Code of Catbalogan', d),
      item('Cabinet 1-2', 'BICS', d),
      item('Cabinet 1-2', 'SSIA', d),
      item('Cabinet 1-2', 'Notebooks', s),
      item('Cabinet 1-2', 'Planning Guide Book', d),
      item('Cabinet 1-2', 'Human Rights Situation Report July-December 2025', d),
      item('Cabinet 1-2', 'DILG/DBM', d),
      item('Cabinet 1-2', 'Locational Clearance Requirements', d),
      item('Cabinet 1-2', 'City Nutrition Action Plan 2020-2032', d),
      item('Cabinet 1-2', 'Development Transition Plan', d),
      item('Cabinet 1-2', 'Executive Order no. 09-009 series of 2022', d),
      item('Cabinet 1-2', 'CYDO Plan (2021-2022)', d),
      item('Cabinet 1-2', 'City Youth Development Plan 2023-2025', d),
      item('Cabinet 1-2', 'CDRMP (2022-2027)', d),
      item('Cabinet 1-2', 'ELA (2023-2025)', d),
      item('Cabinet 1-2', 'Landslide and Flood Threat Advisory', d),
      item('Cabinet 1-2', 'CLUP 2001-2010', d),
      item('Cabinet 1-2', 'Planning Strategically', d),
      item('Cabinet 1-2', "GIS Cookbook for LGU's", d),
      item('Cabinet 1-2', 'Coastal Hazard Advisory', d),
      item('Cabinet 1-2', 'RARA', d),
      item('Cabinet 1-2', "RARA for Coastal Brgy's", d),
      item('Cabinet 1-2', 'Coastal Land Reclamation', d),
      item('Cabinet 1-2', 'Devolution Transition Plan 2022-2024', d),
      item('Cabinet 1-2', 'Marine Spatial Plan', d),
      item('Cabinet 1-2', 'Essential EAFM', d),
      item('Cabinet 1-2', 'Provincial Development Counsel 2024', d),
      item('Cabinet 1-2', 'Comprehensive Development Plan', d),
      item('Cabinet 1-2', 'Brgy. Maulong Development Project', d),
      item('Cabinet 1-2', 'Local Shelter Plan 2016-2024', d),
      item('Cabinet 1-2', 'FLUP 2021-2031', d),
      item('Cabinet 1-2', 'Brgy. Solid Waste Management Plan 2023-2027', d),
      item('Cabinet 1-2', 'AIP 2026', d),
      item('Cabinet 1-2', 'AIP 2025', d),
      item('Cabinet 1-2', 'AIP 2024', d),
      item('Cabinet 1-2', 'Comprehensive Master Development Plan', d),
      item('Cabinet 1-2', 'CDDC Office 4th Floor, City Hall', d),
      item('Cabinet 1-2', 'Local Building Code 2024', d),

      // Cabinet 3-4 (CDRRMP / PSA / SAAOB)
      item('Cabinet 3-4', 'CDRRMP 2017-2021', d),
      item('Cabinet 3-4', 'CDRRMP 2022-2027', d),
      item('Cabinet 3-4', 'CRDM 2022-2027', d),
      item('Cabinet 3-4', 'PSA-CBMS TABLE 111-202', d),
      item('Cabinet 3-4', 'PSA-CBMS TABLE 65-100', d),
      item('Cabinet 3-4', 'PSA-CBMS TABLE 1-64', d),
      item('Cabinet 3-4', "Supervisor's 2022", d),
      item('Cabinet 3-4', 'Enumerators Manual 2022', d),
      item('Cabinet 3-4', "CSO's", d),
      item('Cabinet 3-4', 'Local Government Units Public Financial Management', d),
      item('Cabinet 3-4', 'Local Government Units Implementation Strategy', d),
      item('Cabinet 3-4', 'Local Government Units Reform Roadmap', d),
      item('Cabinet 3-4', 'SAAOB Jan-Feb 2026', d),
      item('Cabinet 3-4', 'SAAOB Jan-Nov 2025', d),
      item('Cabinet 3-4', 'SAAOB Jan 2024', d),
      item('Cabinet 3-4', 'SAAOB and SRP Feb 2024', d),
      item('Cabinet 3-4', 'Annual Budget 2025', d),
      item('Cabinet 3-4', 'Annual Budget 2024', d),
      item('Cabinet 3-4', 'Annual Budget 2023', d),
      item('Cabinet 3-4', 'CLUP Volume 3 2023-2033', d),
      item('Cabinet 3-4', 'CLUP Volume 2 2023-2033', d),
      item('Cabinet 3-4', 'CLUP Volume 1 2023-2033', d),
      item('Cabinet 3-4', 'CLUP Volume 3 2023-2032', d),
      item('Cabinet 3-4', 'CLUP Volume 2 2023-2032', d),
      item('Cabinet 3-4', 'CLUP Volume 1 2023-2032', d),
      item('Cabinet 3-4', 'Ecological Profile 2022-2033', d),
      item('Cabinet 3-4', 'CLUP Executive Summary', d),
      item('Cabinet 3-4', 'OPCR 2023', d),

      // Cabinet 5-6 (Annual Budgets / AIP / Supplies)
      item('Cabinet 5-6', 'Annual Budget 2021', d),
      item('Cabinet 5-6', 'Annual Budget 2020', d),
      item('Cabinet 5-6', 'Annual Budget 2019', d),
      item('Cabinet 5-6', 'AIP 2021', d),
      item('Cabinet 5-6', 'AIP 2020', d),
      item('Cabinet 5-6', 'AIP 2019', d),
      item('Cabinet 5-6', 'AIP 2018', d),
      item('Cabinet 5-6', 'FS 2020', d),
      item('Cabinet 5-6', 'FS 2019', d),
      item('Cabinet 5-6', 'FS 2018', d),
      item('Cabinet 5-6', 'Expandable Envelopes', s),
      item('Cabinet 5-6', 'LED Lights 5W', s),
      item('Cabinet 5-6', 'LED Lights 9W', s),
      item('Cabinet 5-6', 'LED Lights 20W', s),
      item('Cabinet 5-6', 'Christmas Lights', s),
      item('Cabinet 5-6', 'LBC Box', s),

      // Cabinet 7-8 (Paper / Folder Supplies)
      item('Cabinet 7-8', 'Ring Binder', s),
      item('Cabinet 7-8', 'Brown Expandable Envelopes', s),
      item('Cabinet 7-8', 'Green Folders', s),
      item('Cabinet 7-8', 'Columnar Sticker', s),
      item('Cabinet 7-8', 'Paper Blue-Green Expandable Envelopes', s),
      item('Cabinet 7-8', 'Green Expandable Envelopes', s),
      item('Cabinet 7-8', 'Brown Folder', s),
      item('Cabinet 7-8', 'White Folder', s),
      item('Cabinet 7-8', 'Brown Envelopes', s),
      item('Cabinet 7-8', 'Water Marked Laid Paper', s),
      item('Cabinet 7-8', 'Glossy Photopapers', s),
      item('Cabinet 7-8', 'Vellum Board', s),

      // Cabinet 9-10 (Office Supplies & Electronics)
      item('Cabinet 9-10', 'Ring Binder', s),
      item('Cabinet 9-10', 'PVC Cover Clear', s),
      item('Cabinet 9-10', 'Laminating Pouches', s),
      item('Cabinet 9-10', 'Official Record Books', s),
      item('Cabinet 9-10', 'Laptop SSD and Manuals', s),
      item('Cabinet 9-10', "CD's", s),
      item('Cabinet 9-10', 'White Envelopes', s),
      item('Cabinet 9-10', 'Triangular Ruler', s),
      item('Cabinet 9-10', 'Epson Inks', s),
      item('Cabinet 9-10', 'Epson Maintenance Box', s),
      item('Cabinet 9-10', 'Hub-ports', s),
      item('Cabinet 9-10', 'Ballpens', s),
      item('Cabinet 9-10', 'Nano-wireless USB Adaptor', s),
      item('Cabinet 9-10', 'Wireless Mouse', s),
      item('Cabinet 9-10', 'Cutter', s),
      item('Cabinet 9-10', 'Correction Tapes', s),
      item('Cabinet 9-10', 'Highlighters', s),
      item('Cabinet 9-10', 'Scissors', s),
      item('Cabinet 9-10', 'Yarn', s),
      item('Cabinet 9-10', 'Paper Clip', s),
      item('Cabinet 9-10', 'Masking Tapes', s),
      item('Cabinet 9-10', 'Packing Tape', s),
      item('Cabinet 9-10', 'Croco Tape', s),
      item('Cabinet 9-10', 'Plastic Fasteners', s),

      // Cabinet 11-12 (Protective Gear & Cleaning Supplies)
      item('Cabinet 11-12', 'Jackets', s),
      item('Cabinet 11-12', 'Epson Inks', s),
      item('Cabinet 11-12', 'Trash Bags', s),
      item('Cabinet 11-12', "ID's", s),
      item('Cabinet 11-12', 'Glitters', s),
      item('Cabinet 11-12', 'Full Face Masks', s),
      item('Cabinet 11-12', 'Potholder', s),
      item('Cabinet 11-12', 'Keyboard', s),
      item('Cabinet 11-12', 'Alcohols', s),
      item('Cabinet 11-12', 'Air Refresher', s),
      item('Cabinet 11-12', 'Hand Soap', s),
      item('Cabinet 11-12', 'Dishwashing Liquid', s),
      item('Cabinet 11-12', 'All-purpose Glue', s),

      // Cabinet 13-14 (Barangay Plans)
      item('Cabinet 13-14', 'Barangay Development Plans', d),
    ];
  }
}
