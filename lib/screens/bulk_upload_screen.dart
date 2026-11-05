import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import '../models/document.dart';
import '../services/cached_document_service.dart';
import '../services/upload_queue_manager.dart';
import '../services/auth_service.dart';
import '../utils/snackbar_utils.dart';
import '../utils/date_time_utils.dart';
import '../constants/document_types.dart';

/// Which list the bulk upload feeds into.
enum BulkUploadTarget { spDocuments, resolutions }

/// Returns the year "folder" a document belongs to, derived from its M/D/YYYY date.
int? documentYear(Document doc) {
  final parts = doc.fromOrTo.split('/');
  if (parts.length != 3) return null;
  return int.tryParse(parts[2].trim());
}

class _BulkItem {
  final String fileName; // original name, with extension
  final String path; // local path (or web key)
  final int size;
  final TextEditingController numberController; // reso/ordinance number (defaults to file name)
  String? spType; // SP Resolution / SP Ordinance (SP Documents only)

  _BulkItem({required this.fileName, required this.path, required this.size, required String number, this.spType})
      : numberController = TextEditingController(text: number);

  String get extension => fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
  bool get isImage => ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'heic'].contains(extension);
}

class BulkUploadScreen extends StatefulWidget {
  final BulkUploadTarget target;
  final int? initialYear;

  const BulkUploadScreen({super.key, required this.target, this.initialYear});

  @override
  State<BulkUploadScreen> createState() => _BulkUploadScreenState();
}

class _BulkUploadScreenState extends State<BulkUploadScreen> {
  static const int _maxFileSize = 50 * 1024 * 1024;

  final List<_BulkItem> _items = [];
  final Map<String, List<int>> _webFileBytes = {};
  final remarksController = TextEditingController();

  String _person = '';
  List<int> _years = [];
  int? _selectedYear;
  DateTime? _selectedDate;
  Set<String> _existingCodes = {};

  // Resolutions only: one type applied to the whole batch
  List<String> _resolutionTypes = [];
  TextEditingController? _typeFieldController;

  bool _isPicking = false;
  bool _isSaving = false;
  bool _showValidationErrors = false;
  int _savedCount = 0;

  bool get _isSp => widget.target == BulkUploadTarget.spDocuments;
  String get _mode => _isSp ? 'SP Documents' : 'Resolutions';
  Color get _accent => _isSp ? const Color(0xFF5C6BC0) : const Color(0xFF9C27B0);

  @override
  void initState() {
    super.initState();
    _loadContext();
  }

  @override
  void dispose() {
    for (final item in _items) {
      item.numberController.dispose();
    }
    remarksController.dispose();
    super.dispose();
  }

  Future<void> _loadContext() async {
    final username = await AuthService.getUsername();
    final docs = await CachedDocumentService().fetchDocuments();
    final modeDocs = docs.where((d) => d.mode == _mode);
    final currentYear = getPhilippineTime().year;
    final years = <int>{currentYear, ...modeDocs.map(documentYear).whereType<int>()};
    if (widget.initialYear != null) years.add(widget.initialYear!);
    final types = modeDocs.where((d) => d.category != null && d.category!.isNotEmpty).map((d) => d.category!).toSet().toList()..sort();
    if (!mounted) return;
    setState(() {
      _person = username ?? '';
      _existingCodes = docs.map((d) => d.code).toSet();
      _years = years.toList()..sort((a, b) => b.compareTo(a));
      _resolutionTypes = types;
      _setYear(widget.initialYear ?? currentYear);
    });
  }

  void _setYear(int year) {
    _selectedYear = year;
    final now = getPhilippineTime();
    // Keep the date inside the chosen folder's year
    if (_selectedDate == null || _selectedDate!.year != year) {
      _selectedDate = year == now.year ? DateTime(now.year, now.month, now.day) : DateTime(year, 1, 1);
    }
  }

  Future<void> _addYearFolder() async {
    final controller = TextEditingController();
    final year = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Year Folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 4,
          decoration: const InputDecoration(labelText: 'Year', hintText: 'e.g. 2019', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final y = int.tryParse(controller.text.trim());
              if (y == null || y < 1900 || y > 2100) {
                SnackbarUtils.showErrorSnackBar(context, 'Enter a valid year');
                return;
              }
              Navigator.pop(context, y);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (year == null || !mounted) return;
    setState(() {
      if (!_years.contains(year)) _years = [..._years, year]..sort((a, b) => b.compareTo(a));
      _setYear(year);
    });
  }

  Future<void> _selectDate() async {
    final year = _selectedYear ?? getPhilippineTime().year;
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime(year, 1, 1),
      firstDate: DateTime(year, 1, 1),
      lastDate: DateTime(year, 12, 31),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  /// Guesses SP type from the file name; defaults to SP Resolution.
  String _guessSpType(String name) {
    final lower = name.toLowerCase();
    if (RegExp(r'\bord').hasMatch(lower) || lower.contains('ordinance')) return 'SP Ordinance';
    return 'SP Resolution';
  }

  String _stripExtension(String name) {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  Future<void> _pickFiles() async {
    setState(() => _isPicking = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
        allowMultiple: true,
        withData: kIsWeb,
      );
      if (result == null || result.files.isEmpty) return;
      final skipped = <String>[];
      int added = 0;
      for (final file in result.files) {
        if (_items.any((i) => i.fileName == file.name)) continue;
        String? path;
        int size = 0;
        if (kIsWeb) {
          if (file.bytes == null) continue;
          path = 'web_file_${DateTime.now().microsecondsSinceEpoch}_${file.name}';
          size = file.bytes!.length;
          _webFileBytes[path] = file.bytes!;
        } else {
          path = file.path;
          if (path == null || path.isEmpty) continue;
          size = File(path).lengthSync();
        }
        if (size == 0) continue;
        if (size > _maxFileSize) {
          skipped.add(file.name);
          _webFileBytes.remove(path);
          continue;
        }
        _items.add(_BulkItem(
          fileName: file.name,
          path: path,
          size: size,
          number: _stripExtension(file.name).trim(),
          spType: _isSp ? _guessSpType(file.name) : null,
        ));
        added++;
      }
      if (!mounted) return;
      if (skipped.isNotEmpty) SnackbarUtils.showErrorSnackBar(context, 'Skipped (>50MB): ${skipped.join(', ')}');
      if (added > 0) SnackbarUtils.showSuccessSnackBar(context, '$added file(s) added');
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  void _removeItem(_BulkItem item) {
    setState(() {
      _items.remove(item);
      _webFileBytes.remove(item.path);
    });
    item.numberController.dispose();
  }

  void _setAllSpTypes(String type) {
    setState(() {
      for (final item in _items) {
        item.spType = type;
      }
    });
  }

  String _codeFor(_BulkItem item) {
    final number = item.numberController.text.trim().replaceAll(RegExp(r'\s+'), '-');
    if (!_isSp) return 'RES-$number';
    final prefix = typeMapping[item.spType] ?? 'SPRES';
    final d = _selectedDate!;
    final dateStr = '${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}${d.year.toString().substring(2)}';
    return '$prefix-$number-$dateStr';
  }

  /// Returns a problem description for the item, or null if it can be saved.
  String? _problemFor(_BulkItem item, Map<String, int> codeCounts) {
    if (item.numberController.text.trim().isEmpty) return 'Number is required';
    if (_isSp && item.spType == null) return 'Select a type';
    if (_selectedDate == null) return null;
    final code = _codeFor(item);
    if (_existingCodes.contains(code)) return 'Already exists ($code)';
    if ((codeCounts[code] ?? 0) > 1) return 'Duplicate in this batch';
    return null;
  }

  Map<String, int> _codeCounts() {
    final counts = <String, int>{};
    if (_selectedDate == null) return counts;
    for (final item in _items) {
      final code = _codeFor(item);
      counts[code] = (counts[code] ?? 0) + 1;
    }
    return counts;
  }

  Future<void> _save() async {
    final typeText = (_typeFieldController?.text ?? '').trim();
    setState(() => _showValidationErrors = true);
    if (_items.isEmpty) {
      SnackbarUtils.showErrorSnackBar(context, 'Add at least one file');
      return;
    }
    if (_selectedDate == null || _person.isEmpty || (!_isSp && typeText.isEmpty)) return;
    final counts = _codeCounts();
    if (_items.any((i) => _problemFor(i, counts) != null)) {
      SnackbarUtils.showErrorSnackBar(context, 'Fix the highlighted files before saving');
      return;
    }

    setState(() {
      _isSaving = true;
      _savedCount = 0;
    });
    final navigator = Navigator.of(context);
    final dateStr = '${_selectedDate!.month}/${_selectedDate!.day}/${_selectedDate!.year}';
    final failed = <_BulkItem>[];

    for (final item in List<_BulkItem>.from(_items)) {
      final code = _codeFor(item);
      final number = item.numberController.text.trim();
      final type = _isSp ? item.spType! : typeText;
      final webBytes = _webFileBytes[item.path];
      UploadQueueManager().addToQueue(documentCode: code, filePath: item.path, isImage: item.isImage, localPath: item.path, bytes: webBytes);
      final doc = Document(
        code: code,
        title: number,
        description: _isSp ? null : number,
        type: type,
        fromOrTo: dateStr,
        mode: _mode,
        assignedTo: _person,
        filePath: null,
        remarks: remarksController.text.trim(),
        person: _person,
        incoming: false,
        status: 'Completed',
        imageUrls: [],
        fileUrls: [],
        localImagePaths: item.isImage ? [item.path] : [],
        localFilePaths: item.isImage ? [] : [item.path],
        category: type,
        createdAt: getPhilippineTime(),
      );
      try {
        await CachedDocumentService().createDocument(doc);
        _existingCodes.add(code);
        if (mounted) setState(() => _savedCount++);
      } catch (_) {
        UploadQueueManager().removeFromQueue(code, item.path);
        failed.add(item);
      }
    }

    CachedDocumentService().processPendingUploads();
    if (!mounted) return;

    if (failed.isEmpty) {
      SnackbarUtils.showSuccessSnackBar(context, '$_savedCount record(s) saved — uploading files in background');
      navigator.pop(true);
      return;
    }
    // Keep only failed items so the user can retry
    setState(() {
      for (final item in _items.where((i) => !failed.contains(i)).toList()) {
        _items.remove(item);
        _webFileBytes.remove(item.path);
      }
      _isSaving = false;
    });
    SnackbarUtils.showErrorSnackBar(context, '${failed.length} file(s) failed to save. Saved: $_savedCount');
  }

  Future<bool> _confirmExit() async {
    if (_items.isEmpty || _isSaving) return !_isSaving;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard bulk upload?'),
        content: Text('${_items.length} file(s) have not been saved.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yes')),
        ],
      ),
    );
    return result ?? false;
  }

  String _formatSize(int bytes) {
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  Widget _sectionTitle(String text) => Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
      );

  Widget _buildFolderCard() {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sectionTitle('Year Folder'),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ..._years.map((year) => ChoiceChip(
                  avatar: Icon(_selectedYear == year ? Icons.folder_open : Icons.folder, size: 18, color: _accent),
                  label: Text('$year'),
                  selected: _selectedYear == year,
                  onSelected: _isSaving ? null : (_) => setState(() => _setYear(year)),
                )),
            ActionChip(
              avatar: const Icon(Icons.create_new_folder_outlined, size: 18),
              label: const Text('New Folder'),
              onPressed: _isSaving ? null : _addYearFolder,
            ),
          ]),
          const SizedBox(height: 16),
          InkWell(
            onTap: _isSaving ? null : _selectDate,
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: _isSp ? 'Receiving Date *' : 'Date *',
                helperText: 'Applied to all files in this batch',
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
                errorText: _showValidationErrors && _selectedDate == null ? 'Date is required' : null,
                suffixIcon: const Icon(Icons.calendar_today),
              ),
              child: Text(_selectedDate != null ? '${_selectedDate!.month}/${_selectedDate!.day}/${_selectedDate!.year}' : 'Select date'),
            ),
          ),
          if (!_isSp) ...[
            const SizedBox(height: 16),
            Autocomplete<String>(
              optionsBuilder: (value) {
                final query = value.text.toLowerCase();
                if (query.isEmpty) return _resolutionTypes;
                return _resolutionTypes.where((t) => t.toLowerCase().contains(query));
              },
              onSelected: (_) => setState(() {}),
              fieldViewBuilder: (context, controller, focusNode, _) {
                _typeFieldController = controller;
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: !_isSaving,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Resolution Type *',
                    hintText: 'Type or select existing…',
                    helperText: 'Applied to all files in this batch',
                    border: const OutlineInputBorder(),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surface,
                    errorText: _showValidationErrors && controller.text.trim().isEmpty ? 'Resolution type is required' : null,
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: remarksController,
            enabled: !_isSaving,
            decoration: InputDecoration(
              labelText: 'Remarks (optional)',
              helperText: 'Applied to all files in this batch',
              border: const OutlineInputBorder(),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surface,
            ),
            maxLines: 2,
          ),
        ]),
      ),
    );
  }

  Widget _buildItem(_BulkItem item, Map<String, int> counts) {
    final problem = _problemFor(item, counts);
    final isPdf = item.extension == 'pdf';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: problem != null ? Colors.red.shade300 : Colors.grey.shade300),
        color: problem != null ? Colors.red.withValues(alpha: 0.04) : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(isPdf ? Icons.picture_as_pdf : Icons.image_outlined, size: 18, color: isPdf ? Colors.red.shade400 : Colors.blue.shade400),
          const SizedBox(width: 6),
          Expanded(child: Text(item.fileName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
          Text(_formatSize(item.size), style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            visualDensity: VisualDensity.compact,
            tooltip: 'Remove',
            onPressed: _isSaving ? null : () => _removeItem(item),
          ),
        ]),
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: TextField(
              controller: item.numberController,
              enabled: !_isSaving,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                isDense: true,
                labelText: _isSp ? 'Ordinance/Resolution No.' : 'Resolution No.',
                border: const OutlineInputBorder(),
                errorText: problem,
                errorMaxLines: 2,
              ),
            ),
          ),
          if (_isSp) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 150,
              child: DropdownButtonFormField<String>(
                value: item.spType,
                isDense: true,
                isExpanded: true,
                decoration: const InputDecoration(isDense: true, labelText: 'Type', border: OutlineInputBorder()),
                items: spDocumentTypes.map((t) => DropdownMenuItem(value: t, child: Text(t, overflow: TextOverflow.ellipsis))).toList(),
                onChanged: _isSaving ? null : (v) => setState(() => item.spType = v),
              ),
            ),
          ],
        ]),
      ]),
    );
  }

  Widget _buildFilesCard() {
    final counts = _codeCounts();
    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: _sectionTitle('Files (${_items.length})')),
            if (_isSp && _items.isNotEmpty)
              PopupMenuButton<String>(
                enabled: !_isSaving,
                tooltip: 'Set type for all',
                onSelected: _setAllSpTypes,
                itemBuilder: (_) => spDocumentTypes.map((t) => PopupMenuItem(value: t, child: Text('Set all to $t'))).toList(),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.done_all, size: 18, color: _accent),
                    const SizedBox(width: 4),
                    Text('Set all', style: TextStyle(color: _accent, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
          ]),
          const SizedBox(height: 4),
          Text(
            'The file name is used as the ${_isSp ? 'ordinance/resolution' : 'resolution'} number. Edit it below if needed.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: (_isPicking || _isSaving) ? null : _pickFiles,
              icon: _isPicking ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.upload_file),
              label: Text(_isPicking ? 'Selecting files...' : 'Select Files (PDF / Images)'),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          ),
          const SizedBox(height: 12),
          ..._items.map((item) => _buildItem(item, counts)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _confirmExit();
        if (shouldPop && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isSp ? 'Bulk Upload SP Documents' : 'Bulk Upload Resolutions'),
          backgroundColor: _accent,
          foregroundColor: Colors.white,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _buildFolderCard(),
            _buildFilesCard(),
            ElevatedButton(
              onPressed: _isSaving || _items.isEmpty ? null : _save,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                backgroundColor: _accent,
                foregroundColor: Colors.white,
              ),
              child: _isSaving
                  ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                      const SizedBox(width: 12),
                      Text('Saving $_savedCount / ${_items.length}...'),
                    ])
                  : Text(
                      _items.isEmpty ? 'Save Records' : 'Save ${_items.length} Record(s) to ${_selectedYear ?? ''}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
            ),
            const SizedBox(height: 24),
          ]),
        ),
      ),
    );
  }
}
