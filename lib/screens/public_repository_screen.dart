import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/repository_link.dart';
import '../services/sqlite_database_service_mobile.dart';
import '../services/supabase_service.dart';
import '../services/auth_service.dart';
import '../utils/date_time_utils.dart';

class PublicRepositoryScreen extends StatefulWidget {
  const PublicRepositoryScreen({super.key});

  @override
  State<PublicRepositoryScreen> createState() => _PublicRepositoryScreenState();
}

class _PublicRepositoryScreenState extends State<PublicRepositoryScreen> {
  final _sqlite = SQLiteDatabaseService();
  final _supabase = SupabaseService();

  List<RepositoryLink> _links = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLinks();
  }

  Future<void> _loadLinks() async {
    setState(() => _isLoading = true);
    try {
      final remote = await _supabase.fetchRepositoryLinks();
      if (remote.isNotEmpty || true) {
        if (mounted) {
          setState(() {
            _links = remote;
            _isLoading = false;
          });
        }
        return;
      }
    } catch (_) {}

    final local = await _sqlite.fetchRepositoryLinks();
    if (mounted) {
      setState(() {
        _links = local;
        _isLoading = false;
      });
    }
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open link')),
      );
    }
  }

  void _showLinkDialog({RepositoryLink? existing}) {
    final isEdit = existing != null;
    final titleController = TextEditingController(text: existing?.title ?? '');
    final linkController = TextEditingController(text: existing?.driveLink ?? '');
    final descController = TextEditingController(text: existing?.description ?? '');
    final formKey = GlobalKey<FormState>();
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          title: Text(isEdit ? 'Edit Repository Link' : 'Add Repository Link'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: titleController,
                      inputFormatters: [_WordLimitFormatter(15)],
                      maxLines: null,
                      minLines: 1,
                      decoration: const InputDecoration(
                        labelText: 'Title *',
                        border: OutlineInputBorder(),
                      ),
                      buildCounter: (context, {required currentLength, required isFocused, maxLength}) {
                        final words = titleController.text.trim().isEmpty
                            ? 0
                            : titleController.text.trim().split(RegExp(r'\s+')).length;
                        return Text(
                          '$words / 15 words',
                          style: TextStyle(
                            fontSize: 12,
                            color: words >= 15 ? Colors.orange[700] : Colors.grey,
                          ),
                        );
                      },
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Title is required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: linkController,
                      decoration: const InputDecoration(
                        labelText: 'Drive Link *',
                        border: OutlineInputBorder(),
                        hintText: 'https://drive.google.com/...',
                      ),
                      keyboardType: TextInputType.url,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Link is required';
                        if (Uri.tryParse(v.trim()) == null) return 'Enter a valid URL';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: descController,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDialogState(() => isSaving = true);

                      if (isEdit) {
                        final updates = {
                          'title': titleController.text.trim(),
                          'drive_link': linkController.text.trim(),
                          'description': descController.text.trim(),
                        };
                        try {
                          await _supabase.updateRepositoryLink(existing.id!, updates);
                          await _sqlite.updateRepositoryLink(existing.id!, updates);
                        } catch (_) {
                          await _sqlite.updateRepositoryLink(existing.id!, updates);
                        }
                      } else {
                        final username = await AuthService.getUsername() ?? 'Unknown';
                        final now = getPhilippineTime();
                        final link = RepositoryLink(
                          title: titleController.text.trim(),
                          driveLink: linkController.text.trim(),
                          description: descController.text.trim(),
                          addedBy: username,
                          addedAt: now,
                          needsSync: true,
                        );
                        try {
                          final saved = await _supabase.createRepositoryLink(link);
                          await _sqlite.createRepositoryLink(saved.copyWith(needsSync: false));
                        } catch (_) {
                          await _sqlite.createRepositoryLink(link);
                        }
                      }

                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      if (mounted) _loadLinks();
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(isEdit ? 'Update' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(RepositoryLink link) async {
    final inputController = TextEditingController();
    bool? result;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final canConfirm = inputController.text.trim().toLowerCase() == 'y';
          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.delete_forever, color: Colors.red[700]),
                const SizedBox(width: 8),
                const Text('Confirm Deletion'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Are you sure you want to delete "${link.title}"?',
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: inputController,
                  decoration: const InputDecoration(
                    labelText: 'Type "y" to confirm, "n" to cancel',
                    border: OutlineInputBorder(),
                    helperText: 'This action cannot be undone',
                  ),
                  maxLength: 1,
                  autofocus: true,
                  onChanged: (_) => setDialogState(() {}),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: canConfirm
                    ? () {
                        result = true;
                        Navigator.of(ctx).pop();
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[700],
                  foregroundColor: Colors.white,
                ),
                child: const Text('Confirm Delete'),
              ),
            ],
          );
        },
      ),
    );

    if (result != true || link.id == null) return;

    final username = await AuthService.getUsername() ?? 'Unknown';

    try {
      await _supabase.deleteRepositoryLink(link.id!);
      await _sqlite.deleteRepositoryLink(link.id!);
      await _supabase.logDeletedRecord(username, 'REPO-${link.id}', link.title);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"${link.title}" deleted successfully'),
            backgroundColor: Colors.green[700],
            duration: const Duration(seconds: 3),
          ),
        );
        _loadLinks();
      }
    } catch (_) {
      await _sqlite.deleteRepositoryLink(link.id!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"${link.title}" removed locally. Will sync when online.'),
            backgroundColor: Colors.orange[700],
            duration: const Duration(seconds: 3),
          ),
        );
        _loadLinks();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Public Repository'),
        backgroundColor: const Color(0xFF0D86CD),
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showLinkDialog(),
        backgroundColor: const Color(0xFF0D86CD),
        foregroundColor: Colors.white,
        tooltip: 'Add Link',
        child: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _links.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.folder_open, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text(
                        'No links yet',
                        style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Tap + to add a drive link',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadLinks,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    itemCount: _links.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _LinkCard(
                      link: _links[i],
                      onOpen: () => _openLink(_links[i].driveLink),
                      onEdit: () => _showLinkDialog(existing: _links[i]),
                      onDelete: () => _confirmDelete(_links[i]),
                    ),
                  ),
                ),
    );
  }
}

class _LinkCard extends StatelessWidget {
  const _LinkCard({
    required this.link,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  final RepositoryLink link;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('MMM dd, yyyy  hh:mm a').format(link.addedAt.toLocal());

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.folder_shared, color: Color(0xFF0D86CD), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    link.title,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20, color: Color(0xFF0D86CD)),
                  tooltip: 'Edit',
                  onPressed: onEdit,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.delete_forever, size: 20, color: Colors.red[700]),
                  tooltip: 'Delete',
                  onPressed: onDelete,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            if (link.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                link.description,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
            ],
            const SizedBox(height: 10),
            InkWell(
              onTap: onOpen,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFFE3F2FD),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.link, size: 16, color: Color(0xFF0D86CD)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        link.driveLink,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF0D86CD),
                          decoration: TextDecoration.underline,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.open_in_new, size: 14, color: Color(0xFF0D86CD)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.person_outline, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  link.addedBy,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(width: 12),
                const Icon(Icons.access_time, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    dateStr,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WordLimitFormatter extends TextInputFormatter {
  final int maxWords;
  _WordLimitFormatter(this.maxWords);

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final words = newValue.text.trim().isEmpty
        ? 0
        : newValue.text.trim().split(RegExp(r'\s+')).length;
    return words > maxWords ? oldValue : newValue;
  }
}
