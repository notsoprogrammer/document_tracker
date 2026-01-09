import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../models/document.dart';

class AddDocumentScreen extends StatefulWidget {
  final bool incoming;

  const AddDocumentScreen({super.key, required this.incoming});

  @override
  State<AddDocumentScreen> createState() => _AddDocumentScreenState();
}

class _AddDocumentScreenState extends State<AddDocumentScreen> {
  final codeController = TextEditingController();
  final titleController = TextEditingController();
  String? selectedType;
  final fromToController = TextEditingController();
  String? selectedFrom;
  bool isCustomFrom = false;
  String? selectedMode;
  final assignedToController = TextEditingController();
  String? selectedStatus;
  String? selectedFilePath;
  final remarksController = TextEditingController();
  final personController = TextEditingController();
  String? selectedPerson;
  bool isCustomPerson = false;

  final List<String> documentTypes = [
    'Memo',
    'Travel',
    'Transmittal',
    'Executive Order',
    'Letter',
    'Report',
    'Endorsement',
    'Resolution',
    'Voucher/OBR',
    'Others'
  ];

  final List<String> modeOptions = [
    'Hand-carry / Hard copy',
    'Email / Soft copy',
    'Courier'
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
    'DILG',
    'DSHUD',
    'PSA'
  ];

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
  ];
  final List<String> statusOptions = [
    'Received','Delivered','Action Required', 'Returned', 'Completed', 'Urgent','Filed'
  ];

  @override
  void initState() {
    super.initState();
    codeController.text = _generateCode(widget.incoming);
  }

  String _generateCode(bool incoming) {
    final now = DateTime.now();
    final year = now.year;
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    // Simple per-session incremental sequence so codes increase from 001
    // These counters are static so multiple AddDocumentScreen instances share the sequence during app runtime
    if (incoming) {
      _AddDocumentScreenState._incomingSeq++;
      final seq = _AddDocumentScreenState._incomingSeq.toString().padLeft(3, '0');
      return 'IDL$year-$month-$day-$seq';
    } else {
      _AddDocumentScreenState._outgoingSeq++;
      final seq = _AddDocumentScreenState._outgoingSeq.toString().padLeft(3, '0');
      return 'ODL$year-$month-$day-$seq';
    }
  }

  static int _incomingSeq = 0;
  static int _outgoingSeq = 0;


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.incoming ? "Add Incoming Document" : "Add Outgoing Document"),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).colorScheme.surface,
              Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  elevation: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Basic Information",
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: codeController,
                          decoration: InputDecoration(
                            labelText: "Document Code",
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface,
                          ),
                          readOnly: true,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: titleController,
                          decoration: InputDecoration(
                            labelText: "Document Title",
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface,
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: selectedType,
                          decoration: InputDecoration(
                            labelText: "Document Type",
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface,
                          ),
                          items: documentTypes.map((type) => DropdownMenuItem(value: type, child: Text(type))).toList(),
                          onChanged: (value) => setState(() => selectedType = value),
                        ),
                      ],
                    ),
                  ),
                ),
                Card(
                  elevation: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.incoming ? "Sender Information" : "Recipient Information",
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (widget.incoming) ...[
                          Autocomplete<String>(
                            optionsBuilder: (TextEditingValue textEditingValue) {
                              if (textEditingValue.text == '') {
                                return const Iterable<String>.empty();
                              }
                              return offices.where((String option) {
                                return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
                              });
                            },
                            onSelected: (String selection) {
                              fromToController.text = selection;
                            },
                            fieldViewBuilder: (BuildContext context, TextEditingController fieldTextEditingController, FocusNode fieldFocusNode, VoidCallback onFieldSubmitted) {
                              fieldTextEditingController.text = fromToController.text;
                              return TextField(
                                controller: fieldTextEditingController,
                                focusNode: fieldFocusNode,
                                decoration: InputDecoration(
                                  labelText: "From (Office/Agency/Person)",
                                  hintText: "Start typing to see suggestions",
                                  border: OutlineInputBorder(),
                                  filled: true,
                                  fillColor: Theme.of(context).colorScheme.surface,
                                ),
                                onChanged: (value) {
                                  fromToController.text = value;
                                },
                              );
                            },
                          ),
                        ] else ...[
                          Autocomplete<String>(
                            optionsBuilder: (TextEditingValue textEditingValue) {
                              if (textEditingValue.text == '') {
                                return const Iterable<String>.empty();
                              }
                              return offices.where((String option) {
                                return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
                              });
                            },
                            onSelected: (String selection) {
                              fromToController.text = selection;
                            },
                            fieldViewBuilder: (BuildContext context, TextEditingController fieldTextEditingController, FocusNode fieldFocusNode, VoidCallback onFieldSubmitted) {
                              fieldTextEditingController.text = fromToController.text;
                              return TextField(
                                controller: fieldTextEditingController,
                                focusNode: fieldFocusNode,
                                decoration: InputDecoration(
                                  labelText: "Recipient (Office/Agency/Person)",
                                  hintText: "Start typing to see suggestions",
                                  border: OutlineInputBorder(),
                                  filled: true,
                                  fillColor: Theme.of(context).colorScheme.surface,
                                ),
                                onChanged: (value) {
                                  fromToController.text = value;
                                },
                              );
                            },
                          ),
                        ],
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: selectedMode,
                          decoration: InputDecoration(
                            labelText: widget.incoming ? "Mode of Receipt" : "Mode of Release",
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface,
                          ),
                          items: modeOptions.map((mode) => DropdownMenuItem(value: mode, child: Text(mode))).toList(),
                          onChanged: (value) => setState(() => selectedMode = value),
                        ),
                      ],
                    ),
                  ),
                ),
                Card(
                  elevation: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Assignment & Attachment",
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Autocomplete<String>(
                          optionsBuilder: (TextEditingValue textEditingValue) {
                            if (textEditingValue.text == '') {
                              return const Iterable<String>.empty();
                            }
                            return cpdcoStaff.where((String option) {
                              return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
                            });
                          },
                          onSelected: (String selection) {
                            assignedToController.text = selection;
                          },
                          fieldViewBuilder: (BuildContext context, TextEditingController fieldTextEditingController, FocusNode fieldFocusNode, VoidCallback onFieldSubmitted) {
                            fieldTextEditingController.text = assignedToController.text;
                            return TextField(
                              controller: fieldTextEditingController,
                              focusNode: fieldFocusNode,
                              decoration: InputDecoration(
                                labelText: "Assigned / Addressed to",
                                hintText: "Start typing to see suggestions",
                                border: OutlineInputBorder(),
                                filled: true,
                                fillColor: Theme.of(context).colorScheme.surface,
                              ),
                              onChanged: (value) {
                                assignedToController.text = value;
                              },
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: selectedStatus,
                          decoration: InputDecoration(
                            labelText: "Status",
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface,
                          ),
                          items: statusOptions.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                          onChanged: (value) => setState(() => selectedStatus = value),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: () async {
                            FilePickerResult? result = await FilePicker.platform.pickFiles(
                              type: FileType.custom,
                              allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
                            );
                            if (result != null) {
                              setState(() => selectedFilePath = result.files.single.path);
                            }
                          },
                          icon: const Icon(Icons.attach_file),
                          label: Text(selectedFilePath != null ? "File Selected: ${selectedFilePath!.split('/').last}" : "Upload ${widget.incoming ? 'Incoming' : 'Outgoing'} Document (Image/PDF)"),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: remarksController,
                          decoration: InputDecoration(
                            labelText: "Remarks",
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface,
                          ),
                          maxLines: 3,
                        ),
                      ],
                    ),
                  ),
                ),
                Card(
                  elevation: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Processing Information",
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Autocomplete<String>(
                          optionsBuilder: (TextEditingValue textEditingValue) {
                            if (textEditingValue.text == '') {
                              return const Iterable<String>.empty();
                            }
                            return cpdcoStaff.where((String option) {
                              return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
                            });
                          },
                          onSelected: (String selection) {
                            personController.text = selection;
                          },
                          fieldViewBuilder: (BuildContext context, TextEditingController fieldTextEditingController, FocusNode fieldFocusNode, VoidCallback onFieldSubmitted) {
                            fieldTextEditingController.text = personController.text;
                            return TextField(
                              controller: fieldTextEditingController,
                              focusNode: fieldFocusNode,
                              decoration: InputDecoration(
                                labelText: widget.incoming ? "Received by" : "Released / Delivered by",
                                hintText: "Start typing to see suggestions",
                                border: OutlineInputBorder(),
                                filled: true,
                                fillColor: Theme.of(context).colorScheme.surface,
                              ),
                              onChanged: (value) {
                                personController.text = value;
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    if (selectedType != null && selectedMode != null) {
                      final doc = Document(
                        code: codeController.text,
                        title: titleController.text,
                        type: selectedType!,
                        fromOrTo: fromToController.text,
                        mode: selectedMode!,
                        assignedTo: assignedToController.text,
                        filePath: selectedFilePath,
                        remarks: remarksController.text,
                        person: personController.text,
                        incoming: widget.incoming,
                        status: selectedStatus ?? (widget.incoming ? 'Received' : 'Pending'),
                      );
                      Navigator.pop(context, doc); // Return the document
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                  child: const Text("Save Document", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
