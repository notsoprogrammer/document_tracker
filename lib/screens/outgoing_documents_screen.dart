import 'package:flutter/material.dart';
import '../models/document.dart';

class OutgoingDocumentsScreen extends StatefulWidget {
  final List<Document> documents;
  final Function(int, String, String, {String? notes}) transferDocument;
  final Function(int, String, String, {String? notes}) updateDocumentStatus;

  const OutgoingDocumentsScreen({
    super.key,
    required this.documents,
    required this.transferDocument,
    required this.updateDocumentStatus,
  });

  @override
  State<OutgoingDocumentsScreen> createState() => _OutgoingDocumentsScreenState();
}

class _OutgoingDocumentsScreenState extends State<OutgoingDocumentsScreen> {
  final List<String> cpdcoStaff = [
    'Arnie',
    'Rex',
    'Floro',
    'Arlene',
    'Sharmaine',
    'Path',
    'Jess',
    'Emiliana',
    'Pau',
    'Chris',
    'Wena',
    'Arlyn',
    'Dari',
    'Other'
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



  void _showStatusUpdateDialog(BuildContext context, int index) {
    String? selectedStatus;
    final updatedByController = TextEditingController();
    final officeController = TextEditingController(text: widget.documents[index].fromOrTo);
    final forwardedToController = TextEditingController();
    final notesController = TextEditingController();

    final List<String> statusOptions = [
      'Pending',
      'Received',
      'In Progress',
      'Under Review',
      'Approved',
      'Returned',
      'Rejected',
      'Completed',
      'Archived'
    ];

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Icon(Icons.edit, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  const Text("Update Document Status", style: TextStyle(fontSize: 16)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 16),
                    RawAutocomplete<String>(
                      textEditingController: TextEditingController(text: selectedStatus),
                      focusNode: FocusNode(),
                      optionsBuilder: (TextEditingValue textEditingValue) {
                        if (textEditingValue.text == '') {
                          return const Iterable<String>.empty();
                        }
                        return statusOptions.where((String option) {
                          return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
                        });
                      },
                      onSelected: (String selection) {
                        setState(() => selectedStatus = selection);
                      },
                      fieldViewBuilder: (BuildContext context, TextEditingController textEditingController, FocusNode focusNode, VoidCallback onFieldSubmitted) {
                        return TextField(
                          controller: textEditingController,
                          focusNode: focusNode,
                          decoration: InputDecoration(
                            labelText: "New Status",
                            prefixIcon: const Icon(Icons.info),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onChanged: (value) => setState(() => selectedStatus = value),
                        );
                      },
                      optionsViewBuilder: (BuildContext context, AutocompleteOnSelected<String> onSelected, Iterable<String> options) {
                        return Align(
                          alignment: Alignment.topLeft,
                          child: Material(
                            elevation: 4.0,
                            child: SizedBox(
                              width: 350,
                              height: (options.length * 56.0 + 16.0).clamp(0.0, 200.0),
                              child: ListView.builder(
                                padding: const EdgeInsets.all(8.0),
                                itemCount: options.length,
                                itemBuilder: (BuildContext context, int index) {
                                  final String option = options.elementAt(index);
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
                    RawAutocomplete<String>(
                      textEditingController: officeController,
                      focusNode: FocusNode(),
                      optionsBuilder: (TextEditingValue textEditingValue) {
                        if (textEditingValue.text == '') {
                          return const Iterable<String>.empty();
                        }
                        return offices.where((String option) {
                          return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
                        });
                      },
                      onSelected: (String selection) {
                        setState(() {
                          officeController.text = selection;
                        });
                      },
                      fieldViewBuilder: (BuildContext context, TextEditingController textEditingController, FocusNode focusNode, VoidCallback onFieldSubmitted) {
                        return TextField(
                          controller: textEditingController,
                          focusNode: focusNode,
                          decoration: InputDecoration(
                            labelText: "Office",
                            prefixIcon: const Icon(Icons.business),
                            suffixIcon: textEditingController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      setState(() {
                                        textEditingController.clear();
                                      });
                                    },
                                  )
                                : null,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        );
                      },
                      optionsViewBuilder: (BuildContext context, AutocompleteOnSelected<String> onSelected, Iterable<String> options) {
                        return Align(
                          alignment: Alignment.topLeft,
                          child: Material(
                            elevation: 4.0,
                            child: SizedBox(
                              width: 350,
                              height: (options.length * 56.0 + 16.0).clamp(0.0, 200.0),
                              child: ListView.builder(
                                padding: const EdgeInsets.all(8.0),
                                itemCount: options.length,
                                itemBuilder: (BuildContext context, int index) {
                                  final String option = options.elementAt(index);
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
                      optionsBuilder: (TextEditingValue textEditingValue) {
                        if (textEditingValue.text == '') {
                          return const Iterable<String>.empty();
                        }
                        return cpdcoStaff.where((String option) {
                          return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
                        });
                      },
                      onSelected: (String selection) {
                        setState(() {
                          updatedByController.text = selection;
                        });
                      },
                      fieldViewBuilder: (BuildContext context, TextEditingController textEditingController, FocusNode focusNode, VoidCallback onFieldSubmitted) {
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
                      optionsViewBuilder: (BuildContext context, AutocompleteOnSelected<String> onSelected, Iterable<String> options) {
                        return Align(
                          alignment: Alignment.topLeft,
                          child: Material(
                            elevation: 4.0,
                            child: SizedBox(
                              width: 350,
                              height: (options.length * 56.0 + 16.0).clamp(0.0, 200.0),
                              child: ListView.builder(
                                padding: const EdgeInsets.all(8.0),
                                itemCount: options.length,
                                itemBuilder: (BuildContext context, int index) {
                                  final String option = options.elementAt(index);
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
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.update),
                  label: const Text("Update", style: TextStyle(fontSize: 10)),
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () {
                    if (selectedStatus != null && updatedByController.text.isNotEmpty && forwardedToController.text.isNotEmpty) {
                      String combinedNotes = "${officeController.text} - ${forwardedToController.text}";
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
                      if (forwardedToController.text != widget.documents[index].assignedTo) {
                        widget.transferDocument(
                          index,
                          forwardedToController.text,
                          updatedByController.text,
                          notes: combinedNotes,
                        );
                      }
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final outgoingDocuments = widget.documents.where((doc) => !doc.incoming).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Outgoing Documents"),
        backgroundColor: const Color(0xFF2196F3), // Blue complementing orange
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              // TODO: Implement search functionality
            },
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () {
              // TODO: Implement filter functionality
            },
          ),
        ],
      ),
      body: outgoingDocuments.isEmpty
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
                    "No outgoing documents yet",
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Outgoing documents will appear here",
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                        ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 80),
              itemCount: outgoingDocuments.length,
              itemBuilder: (context, index) {
                final doc = outgoingDocuments[index];
                final originalIndex = widget.documents.indexOf(doc);
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  elevation: 2,
                  child: ExpansionTile(
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFF2196F3),
                      child: const Icon(
                        Icons.arrow_upward,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      "${doc.code} - ${doc.title}",
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Row(
                      children: [
                        Icon(
                          Icons.output,
                          size: 16,
                          color: const Color(0xFF2196F3),
                        ),
                        const SizedBox(width: 4),
                        Text("Outgoing • ${doc.type}"),
                      ],
                    ),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
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
                            _buildDetailRow(Icons.assignment_ind, "Forwarded To", doc.assignedTo),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildDetailRow(Icons.info, "Status", doc.status),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  onPressed: () => _showStatusUpdateDialog(context, originalIndex),
                                  tooltip: "Update Status",
                                ),
                              ],
                            ),
                            if (doc.filePath != null) ...[
                              const SizedBox(height: 8),
                              _buildDetailRow(Icons.attach_file, "Attachment", doc.filePath!.split('/').last),
                            ],
                            const SizedBox(height: 8),
                            _buildDetailRow(Icons.comment, "Remarks", doc.remarks),
                            const SizedBox(height: 8),
                            _buildDetailRow(Icons.send, "Released by", doc.person),
                            const SizedBox(height: 16),
                            ExpansionTile(
                              leading: const Icon(Icons.history),
                                // compute visible entries (creation + status changes)
                                title: Text(
                                  "Document History (" + (doc.history.isEmpty ? '0' : doc.history.asMap().entries.where((me) => me.key == 0 || me.value.action.startsWith('Status changed to ')).length.toString()) + ")",
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                ),
                                children: (() {
                                  final entries = doc.history;
                                  if (entries.isEmpty) {
                                    return [const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Text("No history available"),
                                    )];
                                  }

                                  // Only include the creation entry (index 0), status-change entries, and transfer entries.
                                  final visible = entries.asMap().entries.where((me) {
                                    return me.key == 0 || me.value.action.startsWith('Status changed to ');
                                  }).toList();

                                  return visible.map((mapEntry) {
                                  final originalIndex = mapEntry.key;
                                  final entry = mapEntry.value;
                                  String office = doc.fromOrTo;
                                  String personnel = doc.assignedTo;
                                  String? additionalNotes;

                                  // If the history entry has notes, parse them to get office and personnel (creation stores a snapshot there).
                                  if (entry.notes != null && entry.notes!.isNotEmpty) {
                                    final parts = entry.notes!.split(' | ');
                                    final officePersonnelStr = parts[0].trim();
                                    final sepIndex = officePersonnelStr.lastIndexOf(' - ');
                                    if (sepIndex != -1) {
                                      office = officePersonnelStr.substring(0, sepIndex).trim();
                                      personnel = officePersonnelStr.substring(sepIndex + 3).trim();
                                    } else {
                                      final officePersonnel = officePersonnelStr.split(' - ');
                                      if (officePersonnel.length >= 2) {
                                        office = officePersonnel[0].trim();
                                        personnel = officePersonnel[1].trim();
                                      }
                                    }
                                    if (parts.length > 1) {
                                      additionalNotes = parts.sublist(1).join(' | ').trim();
                                    }
                                  }

                                  String mainLine;
                                  final byLine = "by: ${entry.person} | Time: ${_formatDateTime(entry.timestamp)}";
                                  if (originalIndex == 0) {
                                    // Creation: keep original assignedTo (do not change even if later updates modify assignedTo)
                                    mainLine = "Created and forwarded c/o $office - $personnel";
                                  } else {
                                    // Status change: format as "(Status) c/o (office) - (personnel)"
                                    final status = entry.action.replaceFirst('Status changed to ', '');
                                    mainLine = "$status c/o $office - $personnel";
                                  }

                                  return Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          Icons.circle,
                                          size: 12,
                                          color: const Color(0xFF2196F3),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                mainLine,
                                                style: const TextStyle(fontWeight: FontWeight.w500),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                byLine,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                                                ),
                                              ),
                                              if (additionalNotes != null && additionalNotes.isNotEmpty) ...[
                                                const SizedBox(height: 6),
                                                Text(
                                                  "Notes: $additionalNotes",
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontStyle: FontStyle.italic,
                                                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
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
