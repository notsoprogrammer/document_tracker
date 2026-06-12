import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

class ScrollableLocalImageViewer extends StatefulWidget {
  final List<String> initialPaths;
  final Map<String, List<int>>? webFileBytes;
  final void Function(String path) onDelete;

  const ScrollableLocalImageViewer({
    super.key,
    required this.initialPaths,
    this.webFileBytes,
    required this.onDelete,
  });

  static void show(
    BuildContext context, {
    required List<String> imagePaths,
    Map<String, List<int>>? webFileBytes,
    required void Function(String path) onDelete,
  }) {
    if (imagePaths.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          width: double.infinity,
          height: MediaQuery.of(context).size.height * 0.85,
          child: ScrollableLocalImageViewer(
            initialPaths: imagePaths,
            webFileBytes: webFileBytes,
            onDelete: onDelete,
          ),
        ),
      ),
    );
  }

  @override
  State<ScrollableLocalImageViewer> createState() =>
      _ScrollableLocalImageViewerState();
}

class _ScrollableLocalImageViewerState
    extends State<ScrollableLocalImageViewer> {
  late List<String> _paths;

  @override
  void initState() {
    super.initState();
    _paths = List.from(widget.initialPaths);
  }

  void _deleteAt(int index) {
    final path = _paths[index];
    widget.onDelete(path);
    setState(() {
      _paths.removeAt(index);
    });
    if (_paths.isEmpty) {
      Navigator.pop(context);
    }
  }

  Widget _buildImage(String path) {
    if (kIsWeb) {
      final bytes = widget.webFileBytes?[path];
      if (bytes != null) {
        return Image.memory(
          Uint8List.fromList(bytes),
          fit: BoxFit.contain,
          errorBuilder: (_, url, err) =>
              const Center(child: Text('Failed to load image')),
        );
      }
      return const Center(child: Text('Preview unavailable'));
    }
    return Image.file(
      File(path),
      fit: BoxFit.contain,
      errorBuilder: (_, url, err) =>
          const Center(child: Text('Failed to load image')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_paths.length} file${_paths.length != 1 ? 's' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            itemCount: _paths.length,
            separatorBuilder: (_, i) => const Divider(height: 32, thickness: 1),
            itemBuilder: (context, index) {
              final name = _paths[index].split('/').last.split('\\').last;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.6,
                    child: InteractiveViewer(
                      clipBehavior: Clip.hardEdge,
                      child: Center(child: _buildImage(_paths[index])),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      label: const Text(
                        'Remove',
                        style: TextStyle(color: Colors.red),
                      ),
                      onPressed: () => _deleteAt(index),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
