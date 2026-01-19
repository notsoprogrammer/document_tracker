import 'package:flutter/material.dart';
import 'dart:async';
import '../services/enhanced_sync_service.dart';

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

  StreamSubscription<SyncStatus>? _syncSubscription;
  SyncStatus _currentStatus = SyncStatus.idle;

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

    // Initialize sync service and listen to status changes
    _initializeSyncService();
  }

  Future<void> _initializeSyncService() async {
    final syncService = EnhancedSyncService();
    await syncService.initialize();

    _syncSubscription = syncService.syncStatusStream.listen((status) {
      if (mounted) {
        setState(() {
          _currentStatus = status;
        });

        if (status.isActive) {
          _animationController.forward();
        } else if (!status.isActive && status.message.isNotEmpty) {
          // Show completion/error message briefly, then hide
          _animationController.forward();
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) {
              _animationController.reverse();
            }
          });
        } else {
          // Hide banner when idle
          _animationController.reverse();
        }
      }
    });
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Main content
        widget.child,

        // Sync banner overlay
        if (_currentStatus.isActive || (_currentStatus.message.isNotEmpty && !_currentStatus.isActive))
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
    final progressText = _currentStatus.progress != null && _currentStatus.total != null
        ? ' (${_currentStatus.progress! + 1}/${_currentStatus.total})'
        : '';

    return Material(
      elevation: 4,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _currentStatus.color,
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
              if (_currentStatus.isActive) ...[
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  '${_currentStatus.message}$progressText',
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
