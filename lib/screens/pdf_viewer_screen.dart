import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

class PdfViewerScreen extends StatefulWidget {
  final String fileId;
  final String fileName;

  const PdfViewerScreen({
    super.key,
    required this.fileId,
    required this.fileName,
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) => setState(() => _isLoading = false),
        onWebResourceError: (_) => setState(() => _isLoading = false),
        onNavigationRequest: (NavigationRequest request) {
          final url = request.url;
          final uri = Uri.tryParse(url);
          // Redirect Drive actions (download, print, open in Drive) to external browser
          if (url.contains('drive.google.com') &&
              !url.contains('/preview') &&
              !url.contains('/viewer')) {
            if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
            return NavigationDecision.prevent;
          }
          // Open any other external link in browser instead of inside the WebView
          if (uri != null &&
              uri.hasScheme &&
              !url.contains('google.com') &&
              !url.startsWith('blob:') &&
              !url.startsWith('data:')) {
            launchUrl(uri, mode: LaunchMode.externalApplication);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ))
      ..loadRequest(Uri.parse(
          'https://drive.google.com/file/d/${widget.fileId}/preview'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.fileName,
          overflow: TextOverflow.ellipsis,
          maxLines: 2,
          style: const TextStyle(fontSize: 13),
        ),
        toolbarHeight: 56,
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
