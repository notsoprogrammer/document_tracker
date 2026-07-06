import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/google_drive_service.dart';
import '../services/image_download_service.dart';
import '../services/pdf_export_service.dart';
import '../config/supabase_config.dart';
import '../utils/snackbar_utils.dart';

class ScrollableImageViewer extends StatefulWidget {
  final List<String> imageUrls;
  final List<String>? fileNames;
  final int initialIndex;
  final String? documentName;

  const ScrollableImageViewer({
    super.key,
    required this.imageUrls,
    this.fileNames,
    this.initialIndex = 0,
    this.documentName,
  });

  static void show(
    BuildContext context, {
    required List<String> imageUrls,
    List<String>? fileNames,
    int initialIndex = 0,
    String? documentName,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ScrollableImageViewer(
          imageUrls: imageUrls,
          fileNames: fileNames,
          initialIndex: initialIndex,
          documentName: documentName,
        ),
      ),
    );
  }

  @override
  State<ScrollableImageViewer> createState() => _ScrollableImageViewerState();
}

class _ScrollableImageViewerState extends State<ScrollableImageViewer> {
  late final ScrollController _scrollController;
  bool _exportingPdf = false;
  bool _pdfSuccess = false;
  int _rebuildKey = 0;
  late List<String> _proxyUrls;

  @override
  void initState() {
    super.initState();
    _proxyUrls = widget.imageUrls.map(_proxyUrl).toList();
    _scrollController = ScrollController();
    if (widget.initialIndex > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          final cardHeight = MediaQuery.of(context).size.height * 0.65 + 24.0;
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

  Future<void> _onRefresh() async {
    for (final url in _proxyUrls) {
      await CachedNetworkImage.evictFromCache(url);
    }
    if (mounted) setState(() => _rebuildKey++);
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

  String get _pdfFileName {
    if (widget.documentName != null && widget.documentName!.isNotEmpty) {
      return widget.documentName!;
    }
    if (widget.fileNames != null && widget.fileNames!.isNotEmpty) {
      final base = widget.fileNames!.first.replaceAll(RegExp(r'\.[^.]+$'), '');
      if (base.isNotEmpty) return base;
    }
    return 'images_${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<void> _exportPdf() async {
    setState(() { _exportingPdf = true; _pdfSuccess = false; });
    try {
      await PdfExportService.exportImagesToPdf(
        imageUrls: widget.imageUrls,
        fileName: _pdfFileName,
      );
      if (mounted) {
        setState(() { _exportingPdf = false; _pdfSuccess = true; });
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) setState(() => _pdfSuccess = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _exportingPdf = false);
        SnackbarUtils.showErrorSnackBar(
          context,
          e.toString().replaceAll('Exception: ', ''),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${widget.imageUrls.length} image${widget.imageUrls.length != 1 ? 's' : ''}',
          style: const TextStyle(fontSize: 14, color: Colors.white),
        ),
        actions: [
          if (_exportingPdf)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
            )
          else if (_pdfSuccess)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check, color: Colors.green, size: 18),
                  SizedBox(width: 4),
                  Text('PDF ready', style: TextStyle(color: Colors.green, fontSize: 12)),
                ],
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              tooltip: 'Download all as PDF',
              onPressed: _exportPdf,
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        color: Colors.white,
        backgroundColor: Colors.grey[900],
        child: ListView.separated(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(vertical: 12),
          itemCount: widget.imageUrls.length,
          separatorBuilder: (_, _) =>
              const Divider(color: Colors.white24, height: 24),
          itemBuilder: (context, index) {
            return _ImageListCard(
              key: ValueKey('${_proxyUrls[index]}_$_rebuildKey'),
              imageUrl: widget.imageUrls[index],
              proxyUrl: _proxyUrls[index],
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => _ImageZoomPage(
                    imageUrls: widget.imageUrls,
                    proxyUrls: _proxyUrls,
                    fileNames: widget.fileNames,
                    initialIndex: index,
                  ),
                ),
              ),
            );
          },
        ),
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
  final Map<int, int> _retryKeys = {};

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
              key: ValueKey('${widget.proxyUrls[index]}_${_retryKeys[index] ?? 0}'),
              imageUrl: widget.proxyUrls[index],
              httpHeaders: {
                'Authorization': 'Bearer ${SupabaseConfig.supabaseAnonKey}'
              },
              fit: BoxFit.contain,
              placeholder: (_, _) => const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
              errorWidget: (_, _, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.broken_image_outlined, color: Colors.white38, size: 56),
                    const SizedBox(height: 8),
                    const Text(
                      'Failed to load image',
                      style: TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: () async {
                        await CachedNetworkImage.evictFromCache(widget.proxyUrls[index]);
                        if (mounted) {
                          setState(() => _retryKeys[index] = (_retryKeys[index] ?? 0) + 1);
                        }
                      },
                      icon: const Icon(Icons.refresh, color: Colors.white70, size: 18),
                      label: const Text('Tap to retry', style: TextStyle(color: Colors.white70)),
                    ),
                  ],
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

class _ImageListCard extends StatefulWidget {
  final String imageUrl;
  final String proxyUrl;
  final VoidCallback onTap;

  const _ImageListCard({
    super.key,
    required this.imageUrl,
    required this.proxyUrl,
    required this.onTap,
  });

  @override
  State<_ImageListCard> createState() => _ImageListCardState();
}

class _ImageListCardState extends State<_ImageListCard> {
  int _retryKey = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.65,
        child: CachedNetworkImage(
          key: ValueKey('${widget.proxyUrl}_$_retryKey'),
          imageUrl: widget.proxyUrl,
          httpHeaders: {
            'Authorization': 'Bearer ${SupabaseConfig.supabaseAnonKey}'
          },
          fit: BoxFit.contain,
          placeholder: (_, _) => const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
          errorWidget: (_, _, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.broken_image_outlined, color: Colors.white38, size: 48),
                const SizedBox(height: 8),
                const Text(
                  'Failed to load image',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () async {
                    await CachedNetworkImage.evictFromCache(widget.proxyUrl);
                    if (mounted) setState(() => _retryKey++);
                  },
                  icon: const Icon(Icons.refresh, color: Colors.white70, size: 18),
                  label: const Text('Tap to retry', style: TextStyle(color: Colors.white70)),
                ),
              ],
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
