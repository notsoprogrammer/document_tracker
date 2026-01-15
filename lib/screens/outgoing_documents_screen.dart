import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/document.dart';
import '../utils/search_filter_utils.dart';
import '../utils/snackbar_utils.dart';

class OutgoingDocumentsScreen extends StatefulWidget {
  final List<Document> documents;
  final Function(int, String, String, {String? notes}) transferDocument;
  final Function(int, String, String, {String? notes}) updateDocumentStatus;
  // final Function(int, Document) editDocument;
  final Function(int) deleteDocument;
  final Function(String) syncDocument;

  const OutgoingDocumentsScreen({
    super.key,
    required this.documents,
    required this.transferDocument,
    required this.updateDocumentStatus,
    // required this.editDocument,
    required this.deleteDocument,
    required this.syncDocument,
  });

  @override
  State<OutgoingDocumentsScreen> createState() =>
      _OutgoingDocumentsScreenState();
}

class _OutgoingDocumentsScreenState extends State<OutgoingDocumentsScreen> {
  bool _isLoading = true;
  final List<String> cpdcoStaff = [
    'Sir Arnie',
    'Rex',
    'Floro',
    'Arlene',
    'Sharmaine',
    'Path',
    'Jess',
    'Emie',
    'Pau',
    'Chris',
    'Wena',
    'N/A',
    'Arlyn',
    'Dari',
  ];

  final List<String> offices = [
    'CMO - City Mayor\'s Office',
    'CVMO - City Vice Mayor\'s Office',
    'SP - Sangguniang Panlungsod Office',
    'CTO - City Treasurer\'s Office',
    'CAssO - City Assessor\'s Office',
    'CAccO - City Accounting Office',
    'CBO - City Budget Office',
    'CPDCO - City Planning and Development Coordinator\'s Office',
    'CHRMO - City Human Resource Management Office',
    'CCRO - City Civil Registrar\'s Office',
    'CAdmO - City Administrator\'s Office',
    'CLO - City Legal Office',
    'CICTO - City Information and Communications Technology Office',
    'CGSO - City General Services Office',
    'CDRRMO - City Disaster Risk Reduction and Management Office',
    'CIASO - City Internal Audit Services Office',
    'CPYDO - City Population and Youth Development Office',
    'CBPLO - City Business Processing and Licensing Office',
    'BCAO - Barangay And Community Affair\'s Office',
    'CPO - City Procurement Office',
    'CLEAO - Catbalogan Law Enforcement Auxiliary Office',
    'CCCC - Catbalogan City Community College',
    'CHO - City Health Office',
    'CSWDO - City Social Welfare and Development Office',
    'CPDAO - City Persons with Disability Affairs Office',
    'CPESO - City Public Employment Services Office',
    'CTCAO - City Tourism, Culture, Arts, and Information Office',
    'CAgrO - City Agriculture Office',
    'CENRO - City Environment & Natural Resources Office',
    'CEO - City Engineering Office',
    'CVetO - City Veterinary Office',
    'CCDO - City Cooperatives Development Office',
    'CAgBEO - City Agricultural and Biosystem Engineering Office',
    'CEDIPO - City Economic Development and Investment Promotions Office',
    'CEEPUO - City Economic Enterprise and Public Utility Office',
  ];

  String _searchQuery = '';
  DateTime? _startDate;
  DateTime? _endDate;
  DateTime? _specificDate;
  final Set<int> _expandedTiles = {};
  late final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.text = _searchQuery;
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });
    // Simulate loading for better UX
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    });
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays == 0) {
      return "Today ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}";
    } else if (difference.inDays == 1) {
      return "Yesterday ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}";
    } else if (difference.inDays < 7) {
      return "${difference.inDays} days ago";
    } else {
      return "${dateTime.month}/${dateTime.day}/${dateTime.year}";
    }
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 12,
                ),
              ),
              Text(value, style: const TextStyle(fontSize: 14)),
            ],
          ),
        ),
      ],
    );
  }

  void _showImageDialog(BuildContext context, List<String> imageUrls) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (_) => Dialog(
        backgroundColor: Colors.black.withOpacity(0.8),
        insetPadding: const EdgeInsets.all(14),
        child: SizedBox.expand(
          child: Stack(
            children: [
              PageView.builder(
                itemCount: imageUrls.length,
                itemBuilder: (context, index) {
                  return InteractiveViewer(
                    child: Center(
                      child: Image.network(
                        imageUrls[index],
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 16),
                                Text(
                                  'wait la po...',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return const Center(
                            child: Text('Failed to load image'),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
              Positioned(
                top: 40,
                right: 20,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 30),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFileDialog(BuildContext context, Document document) {
    final allFiles = <String>[];
    if (document.filePath != null) {
      allFiles.add(document.filePath!);
    }
    allFiles.addAll(document.fileUrls);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select File to View'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: allFiles.length,
            itemBuilder: (context, index) {
              final filePath = allFiles[index];
              final fileName = filePath.split('/').last.split('\\').last;
              return ListTile(
                leading: const Icon(Icons.attach_file),
                title: Text(fileName),
                onTap: () {
                  Navigator.pop(context);
                  _viewFile(filePath);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _viewFile(String filePath) async {
    final uri = Uri.parse(filePath);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      // Handle error
    }
  }

  void _showStatusUpdateDialog(BuildContext context, int index) {
    String? selectedStatus;
    final updatedByController = TextEditingController();
    final officeController = TextEditingController(
      text: widget.documents[index].fromOrTo,
    );
    final forwardedToController = TextEditingController();
    final notesController = TextEditingController();

    final List<String> statusOptions = [
      'Pending',
      'Received',
      'In Progress',
      'For follow-up',
      'Delivered',
      'Under Review',
      'Approved',
      'Returned',
      'Rejected',
      'Completed',
    ];

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Container(
                width: 400,
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.edit,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          "Update Document Status",
                          style: TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DropdownButtonFormField<String>(
                            value: selectedStatus,
                            decoration: InputDecoration(
                              labelText: "New Status",
                              prefixIcon: const Icon(Icons.info),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            items: statusOptions.map((String option) {
                              return DropdownMenuItem<String>(
                                value: option,
                                child: Text(option),
                              );
                            }).toList(),
                            onChanged: (String? value) {
                              setState(() => selectedStatus = value);
                            },
                          ),
                          const SizedBox(height: 16),
                          RawAutocomplete<String>(
                            textEditingController: officeController,
                            focusNode: FocusNode(),
                            optionsBuilder:
                                (TextEditingValue textEditingValue) {
                                  if (textEditingValue.text == '') {
                                    return const Iterable<String>.empty();
                                  }
                                  return offices.where((String option) {
                                    return option.toLowerCase().contains(
                                      textEditingValue.text.toLowerCase(),
                                    );
                                  });
                                },
                            onSelected: (String selection) {
                              setState(() {
                                officeController.text = selection;
                              });
                            },
                            fieldViewBuilder:
                                (
                                  BuildContext context,
                                  TextEditingController textEditingController,
                                  FocusNode focusNode,
                                  VoidCallback onFieldSubmitted,
                                ) {
                                  return SizedBox(
                                    width: 350,
                                    child: TextField(
                                      controller: textEditingController,
                                      focusNode: focusNode,
                                      decoration: InputDecoration(
                                        labelText: "Office",
                                        prefixIcon: const Icon(Icons.business),
                                        suffixIcon:
                                            textEditingController
                                                .text
                                                .isNotEmpty
                                            ? IconButton(
                                                icon: const Icon(Icons.clear),
                                                onPressed: () {
                                                  setState(() {
                                                    textEditingController
                                                        .clear();
                                                  });
                                                },
                                              )
                                            : null,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                            optionsViewBuilder:
                                (
                                  BuildContext context,
                                  AutocompleteOnSelected<String> onSelected,
                                  Iterable<String> options,
                                ) {
                                  return Align(
                                    alignment: Alignment.topLeft,
                                    child: Material(
                                      elevation: 4.0,
                                      child: SizedBox(
                                        width: 350,
                                        height: (options.length * 56.0 + 16.0)
                                            .clamp(0.0, 200.0),
                                        child: ListView.builder(
                                          padding: const EdgeInsets.all(8.0),
                                          itemCount: options.length,
                                          itemBuilder:
                                              (
                                                BuildContext context,
                                                int index,
                                              ) {
                                                final String option = options
                                                    .elementAt(index);
                                                return GestureDetector(
                                                  onTap: () {
                                                    onSelected(option);
                                                  },
                                                  child: ListTile(
                                                    title: Text(option),
                                                  ),
                                                );
                                              },
                                        ),
                                      ),
                                    ),
                                  );
                                },
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: forwardedToController,
                            decoration: InputDecoration(
                              labelText: "Personnel",
                              prefixIcon: const Icon(Icons.assignment_ind),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          RawAutocomplete<String>(
                            textEditingController: updatedByController,
                            focusNode: FocusNode(),
                            optionsBuilder:
                                (TextEditingValue textEditingValue) {
                                  if (textEditingValue.text == '') {
                                    return const Iterable<String>.empty();
                                  }
                                  return cpdcoStaff.where((String option) {
                                    return option.toLowerCase().contains(
                                      textEditingValue.text.toLowerCase(),
                                    );
                                  });
                                },
                            onSelected: (String selection) {
                              setState(
                                () => updatedByController.text = selection,
                              );
                            },
                            fieldViewBuilder:
                                (
                                  BuildContext context,
                                  TextEditingController textEditingController,
                                  FocusNode focusNode,
                                  VoidCallback onFieldSubmitted,
                                ) {
                                  return TextField(
                                    controller: textEditingController,
                                    focusNode: focusNode,
                                    decoration: InputDecoration(
                                      labelText: "Updated By",
                                      prefixIcon: const Icon(Icons.person),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  );
                                },
                            optionsViewBuilder:
                                (
                                  BuildContext context,
                                  AutocompleteOnSelected<String> onSelected,
                                  Iterable<String> options,
                                ) {
                                  return Align(
                                    alignment: Alignment.topLeft,
                                    child: Material(
                                      elevation: 4.0,
                                      child: SizedBox(
                                        width: 350,
                                        height: (options.length * 56.0 + 16.0)
                                            .clamp(0.0, 200.0),
                                        child: ListView.builder(
                                          padding: const EdgeInsets.all(8.0),
                                          itemCount: options.length,
                                          itemBuilder:
                                              (
                                                BuildContext context,
                                                int index,
                                              ) {
                                                final String option = options
                                                    .elementAt(index);
                                                return GestureDetector(
                                                  onTap: () {
                                                    onSelected(option);
                                                  },
                                                  child: ListTile(
                                                    title: Text(option),
                                                  ),
                                                );
                                              },
                                        ),
                                      ),
                                    ),
                                  );
                                },
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: notesController,
                            decoration: InputDecoration(
                              labelText: "Notes (Optional)",
                              prefixIcon: const Icon(Icons.note),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            maxLines: 3,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text("Cancel"),
                        ),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.update),
                          label: const Text(
                            "Update",
                            style: TextStyle(fontSize: 10),
                          ),
                          style: ElevatedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () {
                            if (selectedStatus != null &&
                                updatedByController.text.isNotEmpty &&
                                forwardedToController.text.isNotEmpty) {
                              String combinedNotes =
                                  "${officeController.text} - ${forwardedToController.text}";
                              if (notesController.text.isNotEmpty) {
                                combinedNotes += " | ${notesController.text}";
                              }
                              // Always record the status change
                              widget.updateDocumentStatus(
                                index,
                                selectedStatus!,
                                updatedByController.text,
                                notes: combinedNotes,
                              );
                              // Only record a transfer if the personnel actually changed
                              if (forwardedToController.text !=
                                  widget.documents[index].assignedTo) {
                                widget.transferDocument(
                                  index,
                                  forwardedToController.text,
                                  updatedByController.text,
                                  notes: combinedNotes,
                                );
                              }
                              Navigator.of(
                                context,
                              ).popUntil((route) => route.isFirst);
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showSearchDialog(BuildContext context) {
    final searchController = TextEditingController(text: _searchQuery);

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                "Search by docs,mode, cpdco staff, other personnel, remarks, type, office, status",
                style: const TextStyle(fontSize: 14),
                overflow: TextOverflow.visible, // allow wrapping
                softWrap: true,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              TextField(
                controller: searchController,
                decoration: InputDecoration(
                  labelText: "Type here to search",
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _searchQuery = '';
              });
              Navigator.pop(context);
            },
            child: const Text("Clear"),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.search),
            label: const Text("Search"),
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () {
              setState(() {
                _searchQuery = searchController.text;
              });
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  void _showFilterDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                Icons.filter_list,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              const Text("Filter Documents", style: TextStyle(fontSize: 16)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 16),
                TextField(
                  readOnly: true,
                  controller: TextEditingController(
                    text: _specificDate != null
                        ? "${_specificDate!.month}/${_specificDate!.day}/${_specificDate!.year}"
                        : '',
                  ),
                  decoration: InputDecoration(
                    labelText: "Specific Date",
                    prefixIcon: const Icon(Icons.calendar_today),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _specificDate ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setState(() {});
                      this.setState(() {
                        _specificDate = picked;
                        _startDate = picked;
                        _endDate = picked;
                      });
                      Navigator.pop(context);
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  readOnly: true,
                  controller: TextEditingController(
                    text: _startDate != null
                        ? "${_startDate!.month}/${_startDate!.day}/${_startDate!.year}"
                        : '',
                  ),
                  decoration: InputDecoration(
                    labelText: "Start Date",
                    prefixIcon: const Icon(Icons.calendar_today),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _startDate ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setState(() {});
                      this.setState(() {
                        _startDate = picked;
                        _specificDate =
                            null; // Clear specific date if range is used
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  readOnly: true,
                  controller: TextEditingController(
                    text: _endDate != null
                        ? "${_endDate!.month}/${_endDate!.day}/${_endDate!.year}"
                        : '',
                  ),
                  decoration: InputDecoration(
                    labelText: "End Date",
                    prefixIcon: const Icon(Icons.calendar_today),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _endDate ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setState(() {});
                      this.setState(() {
                        _endDate = picked;
                        _specificDate =
                            null; // Clear specific date if range is used
                      });
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {});
                this.setState(() {
                  _specificDate = null;
                  _startDate = null;
                  _endDate = null;
                });
                Navigator.pop(context);
              },
              child: const Text("Clear All"),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.filter_list),
              label: const Text("Apply"),
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, int index) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.delete, color: Colors.red),
            const SizedBox(width: 8),
            const Text("Delete Document", style: TextStyle(fontSize: 16)),
          ],
        ),
        content: const Text("Are you SUREEE? This action cannot be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.delete),
            label: const Text("Delete", style: TextStyle(fontSize: 10)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () {
              widget.deleteDocument(index);
              Navigator.pop(context);
              setState(() {
                // The documents list will be updated by the parent, so we just need to rebuild
              });
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final outgoingDocuments = widget.documents
        .where((doc) => !doc.incoming && doc.mode != 'Flag Ceremony')
        .toList();
    final filteredDocuments = searchAndFilterDocuments(
      outgoingDocuments,
      searchQuery: _searchQuery,
      startDate: _startDate,
      endDate: _endDate,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text("Outgoing Documents"),
        backgroundColor: const Color(0xFF2196F3), // Blue complementing orange
        foregroundColor: Colors.white,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(80),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      hintText: 'Search documents...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                setState(() {
                                  _searchQuery = '';
                                  _searchController.clear();
                                });
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.filter_list),
                  onPressed: () => _showFilterDialog(context),
                  tooltip: 'Filter by Date',
                ),
              ],
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading documents...', style: TextStyle(fontSize: 16)),
                ],
              ),
            )
          : filteredDocuments.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.document_scanner,
                    size: 80,
                    color: const Color(0xFF2196F3).withOpacity(0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    outgoingDocuments.isEmpty
                        ? "No outgoing documents yet"
                        : "No documents match your search/filter",
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    outgoingDocuments.isEmpty
                        ? "Outgoing documents will appear here"
                        : "Try adjusting your search or filter criteria",
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 80),
              itemCount: filteredDocuments.length,
              itemBuilder: (context, index) {
                final doc = filteredDocuments[index];
                final originalIndex = widget.documents.indexOf(doc);
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  elevation: 2,
                  child: ExpansionTile(
                    onExpansionChanged: (expanded) {
                      setState(() {
                        if (expanded) {
                          _expandedTiles.add(index);
                        } else {
                          _expandedTiles.remove(index);
                        }
                      });
                    },
                    leading: CircleAvatar(
                      backgroundColor: doc.needsSync
                          ? Colors.red
                          : const Color(0xFF2196F3),
                      child: Icon(
                        doc.needsSync ? Icons.sync : Icons.arrow_upward,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      "${doc.type} - ${doc.title}",
                      style: const TextStyle(fontWeight: FontWeight.w400),
                    ),
                    subtitle: Row(
                      children: [
                        Icon(
                          Icons.output,
                          size: 16,
                          color: const Color(0xFF2196F3),
                        ),
                        const SizedBox(width: 4),
                        Text("${doc.code}  "),
                        if (_expandedTiles.contains(index))
                          IconButton(
                            icon: const Icon(Icons.copy, size: 16),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: doc.code));
                              SnackbarUtils.showInfoSnackBar(
                                context,
                                'Code copied to clipboard',
                              );
                            },
                            tooltip: 'Copy Code',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                      ],
                    ),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceVariant.withOpacity(0.3),
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(12),
                            bottomRight: Radius.circular(12),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildDetailRow(Icons.person, "To", doc.fromOrTo),
                            const SizedBox(height: 8),
                            _buildDetailRow(Icons.send, "Mode", doc.mode),
                            const SizedBox(height: 8),
                            _buildDetailRow(
                              Icons.assignment_ind,
                              "Forwarded To",
                              doc.assignedTo,
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildDetailRow(
                                    Icons.info,
                                    "Status",
                                    doc.status,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  onPressed: () => _showStatusUpdateDialog(
                                    context,
                                    originalIndex,
                                  ),
                                  tooltip: "Update Status",
                                ),
                              ],
                            ),
                            if (doc.imageUrls.isNotEmpty) ...[
                              const SizedBox(height: 8),
                            ],

                            const SizedBox(height: 8),
                            _buildDetailRow(
                              Icons.comment,
                              "Remarks",
                              doc.remarks,
                            ),
                            const SizedBox(height: 8),
                            _buildDetailRow(
                              Icons.send,
                              "Released by",
                              doc.person,
                            ),
                            const SizedBox(height: 16),
                            ExpansionTile(
                              leading: const Icon(Icons.history),
                              // compute visible entries (creation + status changes)
                              title: Text(
                                "Document History (" +
                                    (doc.history.isEmpty
                                        ? '0'
                                        : doc.history
                                              .asMap()
                                              .entries
                                              .where(
                                                (me) =>
                                                    me.key == 0 ||
                                                    me.value.action.startsWith(
                                                      'Status changed to ',
                                                    ),
                                              )
                                              .length
                                              .toString()) +
                                    ")",
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              children: (() {
                                final entries = doc.history;
                                if (entries.isEmpty) {
                                  return [
                                    const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Text("No history available"),
                                    ),
                                  ];
                                }

                                // Only include the creation entry (index 0), status-change entries, and transfer entries.
                                final visible = entries.asMap().entries.where((
                                  me,
                                ) {
                                  return me.key == 0 ||
                                      me.value.action.startsWith(
                                        'Status changed to ',
                                      );
                                }).toList();

                                return visible.map((mapEntry) {
                                  final originalIndex = mapEntry.key;
                                  final entry = mapEntry.value;
                                  String office = doc.fromOrTo;
                                  String personnel = originalIndex == 0
                                      ? 'Original Assignee'
                                      : doc.assignedTo;
                                  String? additionalNotes;

                                  // If the history entry has notes, parse them to get office and personnel (creation stores a snapshot there).
                                  if (entry.notes != null &&
                                      entry.notes!.isNotEmpty) {
                                    final parts = entry.notes!.split('|');
                                    if (originalIndex == 0) {
                                      // Creation: notes = "office|personnel"
                                      if (parts.length >= 2) {
                                        office = parts[0].trim();
                                        personnel = parts[1].trim();
                                      }
                                    } else {
                                      // Status change: notes = "office - personnel|additional"
                                      final officePersonnelStr = parts[0]
                                          .trim();
                                      final sepIndex = officePersonnelStr
                                          .lastIndexOf(' - ');
                                      if (sepIndex != -1) {
                                        office = officePersonnelStr
                                            .substring(0, sepIndex)
                                            .trim();
                                        personnel = officePersonnelStr
                                            .substring(sepIndex + 3)
                                            .trim();
                                      } else {
                                        final officePersonnel =
                                            officePersonnelStr.split(' - ');
                                        if (officePersonnel.length >= 2) {
                                          office = officePersonnel[0].trim();
                                          personnel = officePersonnel[1].trim();
                                        }
                                      }
                                      if (parts.length > 1) {
                                        additionalNotes = parts
                                            .sublist(1)
                                            .join('|')
                                            .trim();
                                      }
                                    }
                                  }

                                  String mainLine;
                                  final byLine =
                                      "by: ${entry.person} | Time: ${_formatDateTime(entry.timestamp)}";
                                  if (originalIndex == 0) {
                                    // Creation: keep original assignedTo (do not change even if later updates modify assignedTo)
                                    mainLine =
                                        "Created and forwarded to $office c/o $personnel";
                                  } else {
                                    // Status change: format as "(Status) c/o (office) - (personnel)"
                                    final status = entry.action.replaceFirst(
                                      'Status changed to ',
                                      '',
                                    );
                                    mainLine = "$status: $office - $personnel";
                                  }

                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          Icons.circle,
                                          size: 12,
                                          color: const Color(0xFF2196F3),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                mainLine,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                byLine,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurface
                                                      .withOpacity(0.8),
                                                ),
                                              ),
                                              if (additionalNotes != null &&
                                                  additionalNotes
                                                      .isNotEmpty) ...[
                                                const SizedBox(height: 6),
                                                Text(
                                                  "Notes: $additionalNotes",
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontStyle: FontStyle.italic,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurface
                                                        .withOpacity(0.7),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList();
                              })(),
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.center,
                              children: [
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.delete),
                                  label: const Text("Delete"),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color.fromARGB(
                                      255,
                                      218,
                                      87,
                                      78,
                                    ),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  onPressed: () => _showDeleteConfirmation(
                                    context,
                                    originalIndex,
                                  ),
                                ),
                                if (doc.imageUrls.isNotEmpty)
                                  ElevatedButton.icon(
                                    icon: const Icon(Icons.image),
                                    label: const Text("View Image"),
                                    onPressed: () => _showImageDialog(
                                      context,
                                      doc.imageUrls,
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                                if (doc.filePath != null ||
                                    doc.fileUrls.isNotEmpty)
                                  ElevatedButton.icon(
                                    icon: const Icon(Icons.attach_file),
                                    label: Text(
                                      "View File${doc.filePath != null && doc.fileUrls.isNotEmpty ? 's' : ''}",
                                    ),
                                    onPressed: () {
                                      final allFiles = <String>[];
                                      if (doc.filePath != null) {
                                        allFiles.add(doc.filePath!);
                                      }
                                      allFiles.addAll(doc.fileUrls);
                                      if (allFiles.length == 1) {
                                        _viewFile(allFiles[0]);
                                      } else {
                                        _showFileDialog(context, doc);
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
