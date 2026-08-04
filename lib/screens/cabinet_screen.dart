import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/cabinet_item.dart';
import '../services/cabinet_service.dart';

class CabinetScreen extends StatefulWidget {
  /// Pre-fills the search box, e.g. a document code so the library opens
  /// already filtered down to that document's cabinet entry.
  final String? initialSearch;

  const CabinetScreen({super.key, this.initialSearch});

  @override
  State<CabinetScreen> createState() => _CabinetScreenState();
}

class _CabinetScreenState extends State<CabinetScreen> {
  final CabinetService _service = CabinetService();
  List<CabinetItem> _items = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _statusFilter = 'All';
  String _categoryFilter = 'All';
  final TextEditingController _searchCtrl = TextEditingController();

  // Mutable so users can add new cabinets at runtime
  final List<String> _knownCabinets = CabinetService.defaultCabinets.toList();

  static const Map<String, Color> _cabinetColors = {
    'Cabinet 1-2':  Color(0xFF1565C0),
    'Cabinet 3-4':  Color(0xFF00838F),
    'Cabinet 5-6':  Color(0xFF6A1B9A),
    'Cabinet 7-8':  Color(0xFFF57C00),
    'Cabinet 9-10': Color(0xFF2E7D32),
    'Cabinet 11-12':Color(0xFFC62828),
    'Cabinet 13-14':Color(0xFF4527A0),
  };

  // Palette for dynamically added cabinets
  static const List<Color> _extraColors = [
    Color(0xFF00695C), Color(0xFF4527A0), Color(0xFF37474F),
    Color(0xFF880E4F), Color(0xFF33691E), Color(0xFFE65100),
  ];

  @override
  void initState() {
    super.initState();
    final initial = widget.initialSearch?.trim() ?? '';
    if (initial.isNotEmpty) {
      _searchQuery = initial;
      _searchCtrl.text = initial;
    }
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    await _service.seedInitialDataIfEmpty();
    final items = await _service.fetchAll();
    if (mounted) setState(() { _items = items; _isLoading = false; });
  }

  List<CabinetItem> get _filtered {
    return _items.where((item) {
      // Status filter
      if (_statusFilter != 'All' && item.status.toLowerCase() != _statusFilter.toLowerCase()) return false;
      // Category filter
      if (_categoryFilter != 'All' && item.category != _categoryFilter.toLowerCase()) return false;
      // Search
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchName = item.itemName.toLowerCase().contains(q);
        final matchCabinet = item.cabinetName.toLowerCase().contains(q);
        final matchBorrower = item.borrowerName?.toLowerCase().contains(q) ?? false;
        final matchMovedTo = item.movedTo?.toLowerCase().contains(q) ?? false;
        // Notes carry the [doc:CODE] tag, so searching a document code finds its entry
        final matchNotes = item.notes?.toLowerCase().contains(q) ?? false;
        if (!matchName && !matchCabinet && !matchBorrower && !matchMovedTo && !matchNotes) return false;
      }
      return true;
    }).toList();
  }

  Map<String, List<CabinetItem>> get _groupedByCabinet {
    final filtered = _filtered;
    final map = <String, List<CabinetItem>>{};
    for (final item in filtered) {
      map.putIfAbsent(item.cabinetName, () => []).add(item);
    }
    return map;
  }

  List<String> get _orderedCabinets {
    final grouped = _groupedByCabinet;
    // Show all known cabinets (even empty ones) + any item-derived cabinets not in the list
    final known = _knownCabinets.toList();
    final extra = grouped.keys.where((c) => !_knownCabinets.contains(c)).toList()
      ..sort(CabinetService.compareCabinetNames);
    // If search/filter active, hide cabinets with no matching items
    if (_searchQuery.isNotEmpty || _statusFilter != 'All' || _categoryFilter != 'All') {
      return [...known.where((c) => grouped.containsKey(c)), ...extra];
    }
    return [...known, ...extra];
  }

  Color _cabinetColor(String cabinetName) {
    if (_cabinetColors.containsKey(cabinetName)) return _cabinetColors[cabinetName]!;
    final index = _knownCabinets.indexOf(cabinetName);
    return _extraColors[index.isNegative ? 0 : index % _extraColors.length];
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        // Explicit blue/white pair: the gradient lives in flexibleSpace, so
        // without these the bar falls back to the light M3 surface colour and
        // the white search text becomes unreadable.
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        title: const Text('Cabinet Library', style: TextStyle(fontWeight: FontWeight.w700)),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: 'Add Cabinet',
            onPressed: _showAddCabinetDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            tooltip: 'Refresh',
            onPressed: _loadData,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list_outlined),
            tooltip: 'Filter',
            onSelected: (v) {
              if (v.startsWith('status:')) {
                setState(() => _statusFilter = v.substring(7));
              } else if (v.startsWith('cat:')) {
                setState(() => _categoryFilter = v.substring(4));
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(enabled: false, child: Text('STATUS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey))),
              ...[
                ('All', 'All'),
                ('Available', 'available'),
                ('Borrowed', 'borrowed'),
                ('Moved', 'moved'),
                ('Removed', 'removed'),
              ].map((e) => PopupMenuItem(
                value: 'status:${e.$2}',
                child: Row(
                  children: [
                    Icon(_statusIcon(e.$2), size: 16, color: _statusColor(e.$2)),
                    const SizedBox(width: 8),
                    Text(e.$1),
                    if (_statusFilter == e.$2 || (_statusFilter == 'All' && e.$2 == 'All'))
                      const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.check, size: 14, color: Colors.blue)),
                  ],
                ),
              )),
              const PopupMenuDivider(),
              const PopupMenuItem(enabled: false, child: Text('CATEGORY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey))),
              ...[
                ('All Types', 'All'),
                ('Documents', 'document'),
                ('Supplies', 'supply'),
              ].map((e) => PopupMenuItem(
                value: 'cat:${e.$2}',
                child: Row(
                  children: [
                    Icon(e.$2 == 'document' ? Icons.description_outlined : e.$2 == 'supply' ? Icons.inventory_2_outlined : Icons.apps_outlined, size: 16, color: Colors.blueGrey),
                    const SizedBox(width: 8),
                    Text(e.$1),
                    if (_categoryFilter == e.$2)
                      const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.check, size: 14, color: Colors.blue)),
                  ],
                ),
              )),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildSearchField(),
                _buildSummaryBar(),
                if (_statusFilter != 'All' || _categoryFilter != 'All' || _searchQuery.isNotEmpty)
                  _buildActiveFilters(),
                Expanded(child: _buildBody()),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddItemDialog,
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add Item'),
      ),
    );
  }

  Widget _buildSearchField() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: TextField(
        controller: _searchCtrl,
        style: const TextStyle(color: Colors.black87, fontSize: 14),
        cursorColor: const Color(0xFF1565C0),
        decoration: InputDecoration(
          hintText: 'Search items, borrowers, cabinets...',
          hintStyle: TextStyle(color: Colors.grey[500], fontSize: 13),
          prefixIcon: Icon(Icons.search, size: 20, color: Colors.grey[600]),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  color: Colors.grey[600],
                  tooltip: 'Clear search',
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _searchQuery = '');
                  },
                ),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          filled: true,
          fillColor: const Color(0xFFF1F4F9),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
        onChanged: (v) => setState(() => _searchQuery = v),
      ),
    );
  }

  Widget _buildSummaryBar() {
    final total = _items.length;
    final available = _items.where((i) => i.status == 'available').length;
    final borrowed = _items.where((i) => i.status == 'borrowed').length;
    final moved = _items.where((i) => i.status == 'moved').length;
    final removed = _items.where((i) => i.status == 'removed').length;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _summaryChip('$total Total', Colors.blueGrey),
          const SizedBox(width: 8),
          _summaryChip('$available Available', const Color(0xFF2E7D32)),
          const SizedBox(width: 8),
          if (borrowed > 0) ...[
            _summaryChip('$borrowed Borrowed', Colors.orange[700]!),
            const SizedBox(width: 8),
          ],
          if (moved > 0) ...[
            _summaryChip('$moved Moved', Colors.purple),
            const SizedBox(width: 8),
          ],
          if (removed > 0)
            _summaryChip('$removed Removed', Colors.red),
        ],
      ),
    );
  }

  Widget _summaryChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildActiveFilters() {
    return Container(
      color: const Color(0xFFF0F4FF),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.filter_alt_outlined, size: 14, color: Colors.blueGrey),
          const SizedBox(width: 6),
          if (_statusFilter != 'All')
            _filterTag(_statusFilter, () => setState(() => _statusFilter = 'All')),
          if (_categoryFilter != 'All')
            _filterTag(_categoryFilter == 'document' ? 'Documents' : 'Supplies', () => setState(() => _categoryFilter = 'All')),
          if (_searchQuery.isNotEmpty)
            _filterTag('"$_searchQuery"', () {
              setState(() { _searchQuery = ''; _searchCtrl.clear(); });
            }),
          const Spacer(),
          Text('${_filtered.length} results', style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
        ],
      ),
    );
  }

  Widget _filterTag(String label, VoidCallback onRemove) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Chip(
        label: Text(label, style: const TextStyle(fontSize: 11)),
        deleteIcon: const Icon(Icons.close, size: 14),
        onDeleted: onRemove,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        backgroundColor: const Color(0xFFE3F2FD),
        side: BorderSide.none,
      ),
    );
  }

  Widget _buildBody() {
    final cabinets = _orderedCabinets;
    if (cabinets.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_outlined, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text('No items found', style: TextStyle(color: Colors.grey[400], fontSize: 15)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
      itemCount: cabinets.length,
      itemBuilder: (context, i) {
        final cabinetName = cabinets[i];
        final items = _groupedByCabinet[cabinetName] ?? [];
        return _buildCabinetCard(cabinetName, items);
      },
    );
  }

  Widget _buildCabinetCard(String cabinetName, List<CabinetItem> items) {
    final color = _cabinetColor(cabinetName);
    final borrowedCount = items.where((i) => i.status == 'borrowed').length;
    final movedCount = items.where((i) => i.status == 'moved').length;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: _searchQuery.isNotEmpty || _statusFilter != 'All',
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.inventory_outlined, color: color, size: 22),
        ),
        title: Text(
          cabinetName,
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: color),
        ),
        subtitle: Row(
          children: [
            Text('${items.length} item${items.length != 1 ? 's' : ''}', style: const TextStyle(fontSize: 11)),
            if (borrowedCount > 0) ...[
              const SizedBox(width: 6),
              _miniChip('$borrowedCount borrowed', Colors.orange),
            ],
            if (movedCount > 0) ...[
              const SizedBox(width: 6),
              _miniChip('$movedCount moved', Colors.purple),
            ],
          ],
        ),
        collapsedBackgroundColor: Colors.white,
        backgroundColor: Colors.white,
        children: [
          const Divider(height: 1, color: Color(0xFFEEEEEE)),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox_outlined, size: 16, color: Colors.grey[400]),
                  const SizedBox(width: 8),
                  Text('No items yet', style: TextStyle(fontSize: 12, color: Colors.grey[400], fontStyle: FontStyle.italic)),
                ],
              ),
            ),
          ...items.map((item) => _buildItemTile(item, color)),
          // Add item to this cabinet shortcut
          InkWell(
            onTap: () => _showAddItemDialog(prefillCabinet: cabinetName),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.add_circle_outline, size: 16, color: color.withValues(alpha: 0.7)),
                  const SizedBox(width: 8),
                  Text('Add item to $cabinetName', style: TextStyle(fontSize: 12, color: color.withValues(alpha: 0.7))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildItemTile(CabinetItem item, Color cabinetColor) {
    final statusColor = _statusColor(item.status);
    return InkWell(
      onTap: () => _showItemActions(item),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // Status dot
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 12),
            // Category icon
            Icon(
              item.category == 'supply' ? Icons.inventory_2_outlined : Icons.description_outlined,
              size: 15,
              color: Colors.grey[400],
            ),
            const SizedBox(width: 8),
            // Name + sub-info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.itemName,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: item.status == 'removed' ? Colors.grey : Colors.black87,
                      decoration: item.status == 'removed' ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (item.status == 'borrowed' && item.borrowerName != null) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.person_outline, size: 11, color: Colors.orange[700]),
                        const SizedBox(width: 3),
                        Text(
                          'Borrowed by ${item.borrowerName}',
                          style: TextStyle(fontSize: 11, color: Colors.orange[700]),
                        ),
                        if (item.borrowDate != null) ...[
                          Text(
                            ' · ${DateFormat('MMM d').format(item.borrowDate!)}',
                            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                          ),
                        ],
                      ],
                    ),
                    if (item.expectedReturn != null && item.expectedReturn!.isNotEmpty)
                      Text(
                        'Due: ${item.expectedReturn}',
                        style: TextStyle(fontSize: 10, color: Colors.red[400]),
                      ),
                  ],
                  if (item.status == 'moved' && item.movedTo != null) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.drive_file_move_outline, size: 11, color: Colors.purple[400]),
                        const SizedBox(width: 3),
                        Text(
                          'Moved to ${item.movedTo}',
                          style: TextStyle(fontSize: 11, color: Colors.purple[400]),
                        ),
                      ],
                    ),
                  ],
                  if (CabinetService.isDocumentLink(item)) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.link, size: 11, color: Colors.blue[600]),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            _linkedDocLabel(item),
                            style: TextStyle(fontSize: 11, color: Colors.blue[600]),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (item.status == 'removed' && !CabinetService.isDocumentLink(item) && item.notes != null && item.notes!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.notes!,
                      style: TextStyle(fontSize: 10, color: Colors.grey[500], fontStyle: FontStyle.italic),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Status chip
            _statusChip(item.status),
          ],
        ),
      ),
    );
  }

  /// Turns "[doc:ABC-123] Folder: Blue binder" into "Document ABC-123 · Blue binder".
  String _linkedDocLabel(CabinetItem item) {
    final notes = item.notes ?? '';
    final code = RegExp(r'\[doc:([^\]]+)\]').firstMatch(notes)?.group(1) ?? '';
    final folder = notes.split('Folder:').length > 1 ? notes.split('Folder:').last.trim() : '';
    final label = code.isEmpty ? 'Linked document' : 'Document $code';
    return folder.isEmpty ? label : '$label · $folder';
  }

  Widget _statusChip(String status) {
    final color = _statusColor(status);
    final label = status[0].toUpperCase() + status.substring(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700)),
    );
  }

  // ─── Item action bottom sheet ───────────────────────────────────────────────

  void _showItemActions(CabinetItem item) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true,
      builder: (ctx) => _ItemActionsSheet(
        item: item,
        cabinetColors: _cabinetColors,
        cabinetOrder: _knownCabinets,
        onBorrow: (borrower, expected, notes) async {
          Navigator.pop(ctx);
          final ok = await _service.borrowItem(item.id!, borrower, expected, notes, item.borrowHistory);
          if (ok) _loadData();
        },
        onReturn: () async {
          Navigator.pop(ctx);
          final ok = await _service.returnItem(item.id!, item.borrowHistory, item.borrowerName ?? '');
          if (ok) _loadData();
        },
        onMove: (newCabinet, notes) async {
          Navigator.pop(ctx);
          final ok = await _service.moveItem(item.id!, newCabinet, notes);
          if (ok) _loadData();
        },
        onRestore: (cabinetName) async {
          Navigator.pop(ctx);
          final ok = await _service.restoreItem(item.id!, cabinetName);
          if (ok) _loadData();
        },
        onRemove: (reason) async {
          Navigator.pop(ctx);
          final ok = await _service.removeItem(item.id!, reason);
          if (ok) _loadData();
        },
        onEdit: (newName, newCategory, newNotes) async {
          Navigator.pop(ctx);
          final ok = await _service.updateItem(item.id!, {
            'item_name': newName,
            'category': newCategory,
            'notes': newNotes,
          });
          if (ok) _loadData();
        },
        onDelete: () async {
          Navigator.pop(ctx);
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Delete Item'),
              content: Text('Permanently delete "${item.itemName}"? This cannot be undone.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Delete'),
                ),
              ],
            ),
          );
          if (confirmed == true) {
            await _service.deleteItem(item.id!);
            _loadData();
          }
        },
      ),
    );
  }

  // ─── Add Item dialog ────────────────────────────────────────────────────────

  void _showAddCabinetDialog() {
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.create_new_folder_outlined, size: 20),
            SizedBox(width: 10),
            Text('Add New Cabinet'),
          ],
        ),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(
            labelText: 'Cabinet Name',
            border: OutlineInputBorder(),
            hintText: 'e.g. Cabinet 15-16',
          ),
          textCapitalization: TextCapitalization.words,
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              if (!_knownCabinets.contains(name)) {
                setState(() => _knownCabinets.add(name));
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showAddItemDialog({String? prefillCabinet}) {
    final nameCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String selectedCabinet = prefillCabinet ?? _knownCabinets.first;
    String selectedCategory = 'document';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Add New Item'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedCabinet,
                  decoration: const InputDecoration(labelText: 'Cabinet', border: OutlineInputBorder()),
                  items: _knownCabinets.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                  onChanged: (v) => setS(() => selectedCabinet = v!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Item Name', border: OutlineInputBorder()),
                  textCapitalization: TextCapitalization.words,
                  autofocus: prefillCabinet != null,
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'document', label: Text('Document'), icon: Icon(Icons.description_outlined)),
                    ButtonSegment(value: 'supply', label: Text('Supply'), icon: Icon(Icons.inventory_2_outlined)),
                  ],
                  selected: {selectedCategory},
                  onSelectionChanged: (s) => setS(() => selectedCategory = s.first),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(labelText: 'Notes (optional)', border: OutlineInputBorder()),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(ctx);
                final newItem = CabinetItem(
                  cabinetName: selectedCabinet,
                  itemName: name,
                  category: selectedCategory,
                  notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
                );
                await _service.addItem(newItem);
                _loadData();
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Helpers ────────────────────────────────────────────────────────────────

  Color _statusColor(String status) {
    switch (status) {
      case 'available': return const Color(0xFF2E7D32);
      case 'borrowed':  return Colors.orange[700]!;
      case 'moved':     return Colors.purple;
      case 'removed':   return Colors.red;
      default:          return Colors.blueGrey;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'available': return Icons.check_circle_outline;
      case 'borrowed':  return Icons.person_outline;
      case 'moved':     return Icons.drive_file_move_outline;
      case 'removed':   return Icons.delete_outline;
      default:          return Icons.apps_outlined;
    }
  }
}

// ─── Item Actions Bottom Sheet ───────────────────────────────────────────────

class _ItemActionsSheet extends StatelessWidget {
  final CabinetItem item;
  final Map<String, Color> cabinetColors;
  final List<String> cabinetOrder;
  final Future<void> Function(String borrower, String? expected, String? notes) onBorrow;
  final Future<void> Function() onReturn;
  final Future<void> Function(String newCabinet, String? notes) onMove;
  final Future<void> Function(String cabinetName) onRestore;
  final Future<void> Function(String? reason) onRemove;
  final Future<void> Function(String name, String category, String? notes) onEdit;
  final Future<void> Function() onDelete;

  const _ItemActionsSheet({
    required this.item,
    required this.cabinetColors,
    required this.cabinetOrder,
    required this.onBorrow,
    required this.onReturn,
    required this.onMove,
    required this.onRestore,
    required this.onRemove,
    required this.onEdit,
    required this.onDelete,
  });

  Color _statusColor(String status) {
    switch (status) {
      case 'available': return const Color(0xFF2E7D32);
      case 'borrowed':  return Colors.orange[700]!;
      case 'moved':     return Colors.purple;
      case 'removed':   return Colors.red;
      default:          return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cabinetColor = cabinetColors[item.cabinetName] ?? Colors.blueGrey;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cabinetColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    item.category == 'supply' ? Icons.inventory_2_outlined : Icons.description_outlined,
                    color: cabinetColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.itemName,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        item.cabinetName,
                        style: TextStyle(fontSize: 12, color: cabinetColor),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(item.status).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    item.status[0].toUpperCase() + item.status.substring(1),
                    style: TextStyle(fontSize: 12, color: _statusColor(item.status), fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          // Borrow info if currently borrowed
          if (item.status == 'borrowed') ...[
            Container(
              margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.person_outline, size: 16, color: Colors.orange[800]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Borrowed by: ${item.borrowerName}', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.orange[800])),
                        if (item.borrowDate != null)
                          Text('Since: ${DateFormat('MMM dd, yyyy').format(item.borrowDate!)}', style: TextStyle(fontSize: 11, color: Colors.orange[600])),
                        if (item.expectedReturn != null && item.expectedReturn!.isNotEmpty)
                          Text('Due: ${item.expectedReturn}', style: TextStyle(fontSize: 11, color: Colors.red[600])),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const Divider(height: 1),
          // Action buttons
          if (item.status == 'available') ...[
            _actionTile(context, Icons.person_add_outlined, 'Borrow', Colors.orange, () => _showBorrowDialog(context)),
            _actionTile(context, Icons.drive_file_move_outlined, 'Move to Another Cabinet', Colors.purple, () => _showMoveDialog(context)),
            _actionTile(context, Icons.delete_outline, 'Mark as Removed', Colors.red, () => _showRemoveDialog(context)),
          ],
          if (item.status == 'borrowed') ...[
            _actionTile(context, Icons.assignment_return_outlined, 'Return Item', const Color(0xFF2E7D32), () => onReturn()),
            _actionTile(context, Icons.drive_file_move_outlined, 'Move to Another Cabinet', Colors.purple, () => _showMoveDialog(context)),
          ],
          if (item.status == 'moved') ...[
            _actionTile(context, Icons.undo_outlined, 'Restore to Cabinet', const Color(0xFF2E7D32), () => _showRestoreDialog(context)),
            _actionTile(context, Icons.delete_outline, 'Mark as Removed', Colors.red, () => _showRemoveDialog(context)),
          ],
          if (item.status == 'removed') ...[
            _actionTile(context, Icons.restore_outlined, 'Restore Item', const Color(0xFF2E7D32), () => _showRestoreDialog(context)),
          ],
          const Divider(height: 1),
          _actionTile(context, Icons.edit_outlined, 'Edit Item', Colors.blueGrey, () => _showEditDialog(context)),
          if (item.borrowHistory.isNotEmpty)
            _actionTile(context, Icons.history_outlined, 'View Borrow History', const Color(0xFF1565C0), () => _showBorrowHistory(context)),
          _actionTile(context, Icons.delete_forever_outlined, 'Delete Permanently', Colors.red[800]!, () => onDelete()),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _actionTile(BuildContext context, IconData icon, String label, Color color, VoidCallback onTap) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: color == Colors.blueGrey ? Colors.black87 : color)),
      onTap: onTap,
      dense: true,
    );
  }

  void _showBorrowDialog(BuildContext context) {
    final borrowerCtrl = TextEditingController();
    final expectedCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrow Item'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: borrowerCtrl,
              decoration: const InputDecoration(labelText: 'Borrower Name *', border: OutlineInputBorder()),
              autofocus: true,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: expectedCtrl,
              decoration: const InputDecoration(
                labelText: 'Expected Return (optional)',
                border: OutlineInputBorder(),
                hintText: 'e.g. Jan 15, 2026 or "next week"',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notesCtrl,
              decoration: const InputDecoration(labelText: 'Notes (optional)', border: OutlineInputBorder()),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final borrower = borrowerCtrl.text.trim();
              if (borrower.isEmpty) return;
              Navigator.pop(ctx);
              onBorrow(borrower, expectedCtrl.text.trim().isEmpty ? null : expectedCtrl.text.trim(), notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim());
            },
            child: const Text('Confirm Borrow'),
          ),
        ],
      ),
    );
  }

  void _showMoveDialog(BuildContext context) {
    String destination = cabinetOrder.firstWhere((c) => c != item.cabinetName, orElse: () => cabinetOrder.first);
    final notesCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Move to Another Cabinet'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: destination,
                decoration: const InputDecoration(labelText: 'Move to', border: OutlineInputBorder()),
                items: cabinetOrder.where((c) => c != item.cabinetName).map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) => setS(() => destination = v!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesCtrl,
                decoration: const InputDecoration(labelText: 'Reason / Notes (optional)', border: OutlineInputBorder()),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                onMove(destination, notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim());
              },
              child: const Text('Move'),
            ),
          ],
        ),
      ),
    );
  }

  void _showRestoreDialog(BuildContext context) {
    String targetCabinet = item.status == 'moved' && item.movedTo != null
        ? item.cabinetName
        : item.cabinetName;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Restore Item'),
          content: DropdownButtonFormField<String>(
            value: targetCabinet,
            decoration: const InputDecoration(labelText: 'Restore to Cabinet', border: OutlineInputBorder()),
            items: cabinetOrder.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
            onChanged: (v) => setS(() => targetCabinet = v!),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                onRestore(targetCabinet);
              },
              child: const Text('Restore'),
            ),
          ],
        ),
      ),
    );
  }

  void _showRemoveDialog(BuildContext context) {
    final reasonCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark as Removed'),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(
            labelText: 'Reason (optional)',
            border: OutlineInputBorder(),
            hintText: 'e.g. Disposed, Lost, Worn out...',
          ),
          maxLines: 2,
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              onRemove(reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim());
            },
            child: const Text('Mark Removed'),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext context) {
    final nameCtrl = TextEditingController(text: item.itemName);
    final notesCtrl = TextEditingController(text: item.notes ?? '');
    String category = item.category;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Edit Item'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Item Name', border: OutlineInputBorder()),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'document', label: Text('Document'), icon: Icon(Icons.description_outlined)),
                  ButtonSegment(value: 'supply', label: Text('Supply'), icon: Icon(Icons.inventory_2_outlined)),
                ],
                selected: {category},
                onSelectionChanged: (s) => setS(() => category = s.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesCtrl,
                decoration: const InputDecoration(labelText: 'Notes', border: OutlineInputBorder()),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(ctx);
                onEdit(name, category, notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim());
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showBorrowHistory(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.history_outlined, size: 20),
            const SizedBox(width: 8),
            const Text('Borrow History'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: item.borrowHistory.isEmpty
              ? const Text('No borrow history.', style: TextStyle(color: Colors.grey))
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: item.borrowHistory.length,
                  separatorBuilder: (context2, index2) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final entry = item.borrowHistory[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            entry.returnDate != null ? Icons.check_circle_outline : Icons.hourglass_empty_outlined,
                            size: 16,
                            color: entry.returnDate != null ? Colors.green : Colors.orange,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(entry.borrowerName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                Text(
                                  'Borrowed: ${DateFormat('MMM dd, yyyy').format(entry.borrowDate)}',
                                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                                ),
                                if (entry.returnDate != null)
                                  Text(
                                    'Returned: ${DateFormat('MMM dd, yyyy').format(entry.returnDate!)}',
                                    style: const TextStyle(fontSize: 11, color: Colors.green),
                                  )
                                else
                                  const Text('Not yet returned', style: TextStyle(fontSize: 11, color: Colors.orange)),
                                if (entry.notes != null && entry.notes!.isNotEmpty)
                                  Text(entry.notes!, style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }
}
