import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../constants/document_types.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _searchQuery = '';
  String _appVersion = '1.2.1';

  @override
  void initState() {
    super.initState();
    _getVersion();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("About"),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.fromARGB(255, 228, 239, 252),
                Color.fromARGB(255, 13, 134, 205),
              ],
            ),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFFFDF6EC),
              const Color(0xFFE3F2FD),
              const Color(0xFFE8F5E9),
            ],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 600;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // App Name and Description
                  Card(
                    elevation: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.info_outline, color: Colors.blue),
                              const SizedBox(width: 8),
                              Text(
                                "FileTrack Hub",
                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            "FileTrack Hub is a comprehensive document tracking and management system designed for the City Planning and Development Coordinator's Office. The app enables efficient tracking, classification, and uploading of documents to Google Drive, ensuring organized and accessible record-keeping.",
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Code Format Explanation
                  Card(
                    elevation: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.code, color: Colors.green),
                              const SizedBox(width: 8),
                              Text(
                                "Document Code Formats",
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildCodeFormatItem(
                            "CF-<TypeCode>-mmddyyyy-hhmmss",
                            "Core Functions",
                            "Documents related to core planning and development functions",
                          ),
                          const SizedBox(height: 8),
                          _buildCodeFormatItem(
                            "StF-<TypeCode>-mmddyyyy-hhmmss",
                            "Strategic Functions",
                            "Documents related to strategic planning and policy functions",
                          ),
                          const SizedBox(height: 8),
                          _buildCodeFormatItem(
                            "SuF-<TypeCode>-mmddyyyy-hhmmss",
                            "Support Functions",
                            "Documents related to administrative and support functions",
                          ),
                          const SizedBox(height: 8),
                          _buildCodeFormatItem(
                            "DOC-<TypeCode>-mmddyyyy-hhmmss",
                            "Other/Unclassified",
                            "General documents and other classifications",
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Type Abbreviations
                  Card(
                    elevation: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.list, color: Colors.orange),
                              const SizedBox(width: 8),
                              Text(
                                "Document Type Abbreviations",
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            onChanged: (value) {
                              setState(() {
                                _searchQuery = value;
                              });
                            },
                            decoration: InputDecoration(
                              labelText: 'Search abbreviations...',
                              prefixIcon: const Icon(Icons.search),
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            "The following table shows the abbreviations used for different document types:",
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 12),
                          _buildAbbreviationsTable(context, isWide),
                        ],
                      ),
                    ),
                  ),

                  // Contact/Support Info
                  Card(
                    elevation: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.contact_support, color: Colors.purple),
                              const SizedBox(width: 8),
                              Text(
                                "Support & Contact",
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            "For technical support or questions about the FileTrack Hub application, please contact the City Planning and Development Coordinator's Office IT support team.",
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "Version: $_appVersion",
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.system_update),
                            label: const Text("Update App"),
                            onPressed: _updateApp,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCodeFormatItem(String format, String category, String description) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            format,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Colors.blue,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            category,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            description,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAbbreviationsTable(BuildContext context, bool isWide) {
    final sortedEntries = typeMapping.entries.where((entry) =>
      entry.key.toLowerCase().contains(_searchQuery.toLowerCase()) ||
      entry.value.toLowerCase().contains(_searchQuery.toLowerCase())
    ).toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    if (isWide) {
      // Table layout for wide screens
      return Table(
        border: TableBorder.all(color: Colors.grey.shade300),
        columnWidths: const {
          0: FlexColumnWidth(3),
          1: FlexColumnWidth(1),
        },
        children: [
          TableRow(
            decoration: BoxDecoration(color: Colors.grey.shade100),
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  'Document Type',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  'Code',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          ...sortedEntries.map((entry) => TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(entry.key),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  entry.value,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          )),
        ],
      );
    } else {
      // List layout for narrow screens
      return Column(
        children: sortedEntries.map((entry) => Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    entry.key,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    entry.value,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                      color: Colors.blue,
                    ),
                  ),
                ),
              ],
            ),
          ),
        )).toList(),
      );
    }
  }

  Future<void> _getVersion() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      _appVersion = info.version;
    });
  }

  void _updateApp() async {
    const url = "https://drive.google.com/uc?export=download&id=1WfT-M5Knp4VgkHkUYBWXXk0zqM8DIQX6";
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Update App"),
          content: const Text("You will be redirected to download the latest APK version. Please install it manually after download."),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                if (await canLaunchUrl(Uri.parse(url))) {
                  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                } else {
                  // Fallback to view link if direct download fails
                  const fallbackUrl = "https://drive.google.com/file/d/1WfT-M5Knp4VgkHkUYBWXXk0zqM8DIQX6/view?usp=drive_link";
                  if (await canLaunchUrl(Uri.parse(fallbackUrl))) {
                    await launchUrl(Uri.parse(fallbackUrl), mode: LaunchMode.externalApplication);
                  }
                }
              },
              child: const Text("Download"),
            ),
          ],
        );
      },
    );
  }
}
