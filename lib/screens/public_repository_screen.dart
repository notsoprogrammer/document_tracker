import 'package:flutter/material.dart';
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
      // Fetch from Supabase first; fall back to local on error
      final remote = await _supabase.fetchRepositoryLinks();
      if (remote.isNotEmpty) {
        setState(() {
          _links = remote;
          _isLoading = false;
        });
        return;
      }
    } catch (_) {}

    // Fallback to local
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

  void _showAddDialog() {
    final titleController = TextEditingController();
    final linkController = TextEditingController();
    final descController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Repository Link'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'Title *',
                      border: OutlineInputBorder(),
                    ),
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
                        // Save to Supabase
                        final saved = await _supabase.createRepositoryLink(link);
                        // Save locally with needs_sync = false
                        await _sqlite.createRepositoryLink(saved.copyWith(needsSync: false));
                      } catch (_) {
                        // Offline — save locally with needs_sync flag
                        await _sqlite.createRepositoryLink(link);
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
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(RepositoryLink link) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Link'),
        content: Text('Remove "${link.title}" from the repository?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      if (link.id != null) {
        await _supabase.deleteRepositoryLink(link.id!);
        await _sqlite.deleteRepositoryLink(link.id!);
      }
    } catch (_) {
      if (link.id != null) {
        await _sqlite.deleteRepositoryLink(link.id!);
      }
    }

    if (mounted) _loadLinks();
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
        onPressed: _showAddDialog,
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
    required this.onDelete,
  });

  final RepositoryLink link;
  final VoidCallback onOpen;
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
                  icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
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
                Text(
                  dateStr,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
