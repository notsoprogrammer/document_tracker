import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/google_drive_service.dart';
import '../services/image_download_service.dart';
import '../config/supabase_config.dart';
import '../utils/snackbar_utils.dart';

class ScrollableImageViewer extends StatefulWidget {
  final List<String> imageUrls;
  final List<String>? fileNames;
  final int initialIndex;

  const ScrollableImageViewer({
    super.key,
    required this.imageUrls,
    this.fileNames,
    this.initialIndex = 0,
  });

  static void show(
    BuildContext context, {
    required List<String> imageUrls,
    List<String>? fileNames,
    int initialIndex = 0,
  }) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (_) => Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.all(14),
        child: ScrollableImageViewer(
          imageUrls: imageUrls,
          fileNames: fileNames,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  @override
  State<ScrollableImageViewer> createState() => _ScrollableImageViewerState();
}

class _ScrollableImageViewerState extends State<ScrollableImageViewer> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    if (widget.initialIndex > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          final itemHeight = MediaQuery.of(context).size.height * 0.6 + 120;
          final offset = (widget.initialIndex * itemHeight)
              .clamp(0.0, _scrollController.position.maxScrollExtent);
          _scrollController.jumpTo(offset);
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String _proxyUrl(String imageUrl) {
    if (imageUrl.contains('drive.google.com/uc?id=')) {
      final uri = Uri.parse(imageUrl);
      final fileId = uri.queryParameters['id'];
      return fileId != null ? GoogleDriveService.generateProxyUrl(fileId) : imageUrl;
    }
    return GoogleDriveService.generateProxyUrl(imageUrl);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${widget.imageUrls.length} file${widget.imageUrls.length != 1 ? 's' : ''}',
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
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
              itemCount: widget.imageUrls.length,
              separatorBuilder: (_, i) => const Divider(height: 32, thickness: 1),
              itemBuilder: (context, index) {
                final url = widget.imageUrls[index];
                final name = (widget.fileNames != null && index < widget.fileNames!.length)
                    ? widget.fileNames![index]
                    : 'Image ${index + 1}';
                return _NetworkImageCard(
                  imageUrl: url,
                  proxyUrl: _proxyUrl(url),
                  fileName: name,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NetworkImageCard extends StatelessWidget {
  final String imageUrl;
  final String proxyUrl;
  final String fileName;

  const _NetworkImageCard({
    required this.imageUrl,
    required this.proxyUrl,
    required this.fileName,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          fileName,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: InteractiveViewer(
            clipBehavior: Clip.hardEdge,
            child: Center(
              child: CachedNetworkImage(
                imageUrl: proxyUrl,
                httpHeaders: {
                  'Authorization': 'Bearer ${SupabaseConfig.supabaseAnonKey}'
                },
                fit: BoxFit.contain,
                placeholder: (_, url) => const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text(
                        'Please wait...',
                        style: TextStyle(color: Color(0xFF383838), fontSize: 16),
                      ),
                    ],
                  ),
                ),
                errorWidget: (_, url, err) =>
                    const Center(child: Text('Failed to load image')),
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: _DownloadButton(imageUrl: imageUrl),
        ),
      ],
    );
  }
}

class _DownloadButton extends StatefulWidget {
  final String imageUrl;

  const _DownloadButton({required this.imageUrl});

  @override
  State<_DownloadButton> createState() => _DownloadButtonState();
}

class _DownloadButtonState extends State<_DownloadButton> {
  bool _downloading = false;
  bool _success = false;

  Future<void> _download() async {
    setState(() {
      _downloading = true;
      _success = false;
    });
    try {
      await ImageDownloadService.downloadAndSave(widget.imageUrl);
      if (mounted) {
        setState(() {
          _downloading = false;
          _success = true;
        });
        await Future.delayed(const Duration(milliseconds: 1500));
        if (mounted) setState(() { _success = false; });
      }
    } catch (e) {
      if (mounted) {
        setState(() { _downloading = false; });
        SnackbarUtils.showErrorSnackBar(
          context,
          e.toString().replaceAll('Exception: ', ''),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_downloading) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_success) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check, color: Colors.green, size: 20),
            SizedBox(width: 4),
            Text('Saved', style: TextStyle(color: Colors.green, fontSize: 13)),
          ],
        ),
      );
    }
    return IconButton(
      icon: const Icon(Icons.download_outlined, color: Colors.black54),
      tooltip: 'Download',
      onPressed: _download,
    );
  }
}
