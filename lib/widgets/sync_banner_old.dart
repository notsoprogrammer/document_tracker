import 'package:flutter/material.dart';
import 'dart:async';
import '../services/auto_sync_service.dart';

/// A widget that displays sync status banners
/// Shows upload/sync progress and status at the top of screens
class SyncBanner extends StatefulWidget {
  final Widget child;

  const SyncBanner({
    super.key,
    required this.child,
  });

  @override
  State<SyncBanner> createState() => _SyncBannerState();
}

class _SyncBannerState extends State<SyncBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;

  bool _isSyncing = false;
  String _syncMessage = '';
  Color _bannerColor = Colors.blue;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();

    // Initialize animation controller
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));

    // Listen to sync status changes
    _initializeSyncListener();
  }

  void _initializeSyncListener() {
    // This would need to be implemented in AutoSyncService
    // For now, we'll use a placeholder approach
    // In a real implementation, AutoSyncService would have a stream
  }

  void _showSyncBanner(String message, Color color) {
    setState(() {
      _syncMessage = message;
      _bannerColor = color;
      _isSyncing = true;
    });
    _animationController.forward();
    _hideTimer?.cancel();
  }

  void _hideSyncBanner() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
        _animationController.reverse();
      }
    });
  }

  void _updateSyncProgress(String message) {
    setState(() {
      _syncMessage = message;
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Main content
        widget.child,

        // Sync banner overlay
        if (_isSyncing)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SlideTransition(
              position: _slideAnimation,
              child: _buildSyncBanner(),
            ),
          ),
      ],
    );
  }

  Widget _buildSyncBanner() {
    return Material(
      elevation: 4,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _bannerColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: SafeArea(
          bottom: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _syncMessage,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
