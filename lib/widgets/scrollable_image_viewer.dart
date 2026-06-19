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
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ScrollableImageViewer(
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
          final cardHeight = MediaQuery.of(context).size.height * 0.55 + 80.0;
          final offset = (widget.initialIndex * cardHeight)
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
      return fileId != null
          ? GoogleDriveService.generateProxyUrl(fileId)
          : imageUrl;
    }
    return GoogleDriveService.generateProxyUrl(imageUrl);
  }

  @override
  Widget build(BuildContext context) {
    final proxyUrls = widget.imageUrls.map(_proxyUrl).toList();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${widget.imageUrls.length} image${widget.imageUrls.length != 1 ? 's' : ''}',
          style: const TextStyle(fontSize: 14, color: Colors.white),
        ),
      ),
      body: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 12),
        itemCount: widget.imageUrls.length,
        separatorBuilder: (_, _) =>
            const Divider(color: Colors.white24, height: 24),
        itemBuilder: (context, index) {
          return _ImageListCard(
            imageUrl: widget.imageUrls[index],
            proxyUrl: proxyUrls[index],
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => _ImageZoomPage(
                  imageUrls: widget.imageUrls,
                  proxyUrls: proxyUrls,
                  fileNames: widget.fileNames,
                  initialIndex: index,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Full-screen zoom page — PageView so user can swipe between images
// ---------------------------------------------------------------------------

class _ImageZoomPage extends StatefulWidget {
  final List<String> imageUrls;
  final List<String> proxyUrls;
  final List<String>? fileNames;
  final int initialIndex;

  const _ImageZoomPage({
    required this.imageUrls,
    required this.proxyUrls,
    this.fileNames,
    required this.initialIndex,
  });

  @override
  State<_ImageZoomPage> createState() => _ImageZoomPageState();
}

class _ImageZoomPageState extends State<_ImageZoomPage> {
  late int _currentIndex;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String _nameFor(int i) {
    if (widget.fileNames != null && i < widget.fileNames!.length) {
      return widget.fileNames![i];
    }
    return 'Image ${i + 1}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${_nameFor(_currentIndex)}  ${_currentIndex + 1}/${widget.imageUrls.length}',
          style: const TextStyle(fontSize: 13, color: Colors.white),
          overflow: TextOverflow.ellipsis,
          maxLines: 2,
        ),
        actions: [
          _DownloadButton(imageUrl: widget.imageUrls[_currentIndex]),
          const SizedBox(width: 8),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.imageUrls.length,
        onPageChanged: (i) => setState(() => _currentIndex = i),
        itemBuilder: (context, index) => InteractiveViewer(
          minScale: 0.5,
          maxScale: 6.0,
          child: Center(
            child: CachedNetworkImage(
              imageUrl: widget.proxyUrls[index],
              httpHeaders: {
                'Authorization': 'Bearer ${SupabaseConfig.supabaseAnonKey}'
              },
              fit: BoxFit.contain,
              placeholder: (_, _) => const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
              errorWidget: (_, _, _) => const Center(
                child: Text(
                  'Failed to load image',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Scroll-list card — thumbnail + tap hint + download
// ---------------------------------------------------------------------------

class _ImageListCard extends StatelessWidget {
  final String imageUrl;
  final String proxyUrl;
  final VoidCallback onTap;

  const _ImageListCard({
    required this.imageUrl,
    required this.proxyUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.65,
        child: CachedNetworkImage(
          imageUrl: proxyUrl,
          httpHeaders: {
            'Authorization': 'Bearer ${SupabaseConfig.supabaseAnonKey}'
          },
          fit: BoxFit.contain,
          placeholder: (_, _) => const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
          errorWidget: (_, _, _) => const Center(
            child: Text(
              'Failed to load image',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Download button (shared)
// ---------------------------------------------------------------------------

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
        if (mounted) setState(() => _success = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _downloading = false);
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
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        ),
      );
    }
    if (_success) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check, color: Colors.green, size: 18),
            SizedBox(width: 4),
            Text('Saved', style: TextStyle(color: Colors.green, fontSize: 12)),
          ],
        ),
      );
    }
    return IconButton(
      icon: const Icon(Icons.download_outlined, color: Colors.white70),
      tooltip: 'Download',
      onPressed: _download,
    );
  }
}
