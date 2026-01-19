import 'package:flutter/material.dart';
import 'dart:async';
import '../services/connectivity_service.dart';

/// A widget that displays connectivity status banners
/// Shows a persistent red banner when offline and a temporary green banner when back online
class ConnectivityBanner extends StatefulWidget {
  final Widget child;

  const ConnectivityBanner({
    super.key,
    required this.child,
  });

  @override
  State<ConnectivityBanner> createState() => _ConnectivityBannerState();
}

class _ConnectivityBannerState extends State<ConnectivityBanner>
    with SingleTickerProviderStateMixin {
  final ConnectivityService _connectivityService = ConnectivityService();
  StreamSubscription<bool>? _connectivitySubscription;
  bool _isOnline = true;
  bool _showOnlineBanner = false;
  Timer? _onlineBannerTimer;
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;

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

    _initializeConnectivity();
  }

  Future<void> _initializeConnectivity() async {
    // Get initial connectivity status
    _isOnline = await _connectivityService.isOnline;
    
    if (!_isOnline) {
      _animationController.forward();
    }

    // Listen to connectivity changes
    _connectivitySubscription = _connectivityService.onOnlineStatusChanged.listen((isOnline) {
      if (mounted) {
        setState(() {
          final wasOffline = !_isOnline;
          _isOnline = isOnline;

          if (!isOnline) {
            // Device went offline - show persistent offline banner
            _showOnlineBanner = false;
            _onlineBannerTimer?.cancel();
            _animationController.forward();
          } else if (wasOffline && isOnline) {
            // Device came back online - show temporary online banner
            _showOnlineBanner = true;
            _animationController.forward();
            
            // Auto-dismiss the online banner after 3 seconds
            _onlineBannerTimer?.cancel();
            _onlineBannerTimer = Timer(const Duration(seconds: 3), () {
              if (mounted) {
                setState(() {
                  _showOnlineBanner = false;
                  _animationController.reverse();
                });
              }
            });
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _onlineBannerTimer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Main content
        widget.child,
        
        // Connectivity banner overlay
        if (!_isOnline || _showOnlineBanner)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SlideTransition(
              position: _slideAnimation,
              child: _buildBanner(),
            ),
          ),
      ],
    );
  }

  Widget _buildBanner() {
    final isOffline = !_isOnline;
    final backgroundColor = isOffline ? Colors.red.shade700 : Colors.green.shade700;
    final icon = isOffline ? Icons.wifi_off : Icons.wifi;
    final message = isOffline ? 'No Internet Connection' : 'Back Online';

    return Material(
      elevation: 4,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: backgroundColor,
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
              Icon(
                icon,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (!isOffline) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
