import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _isInitialized = false;

  final StreamController<bool> _onlineStatusController = StreamController<bool>.broadcast();
  final List<Function()> _reconnectionCallbacks = [];
  bool _lastOnlineStatus = false;

  /// Initialize the connectivity service
  Future<void> initialize() async {
    if (_isInitialized) {
      // If already initialized, still emit current status for new listeners
      _onlineStatusController.add(_lastOnlineStatus);
      return;
    }

    try {
      // Check initial connectivity
      final results = await _connectivity.checkConnectivity();
      final isOnline = _isOnline(results);
      _lastOnlineStatus = isOnline;
      _onlineStatusController.add(isOnline);

      // Listen for connectivity changes
      _subscription = _connectivity.onConnectivityChanged.listen((List<ConnectivityResult> results) {
        final wasOnline = _lastOnlineStatus;
        final isNowOnline = _isOnline(results);
        _lastOnlineStatus = isNowOnline;

        debugPrint('Connectivity changed: ${results.map((r) => r.name).join(', ')} (online: $isNowOnline)');

        _onlineStatusController.add(isNowOnline);

        // If we just came back online, trigger reconnection callbacks
        if (!wasOnline && isNowOnline) {
          _triggerReconnectionCallbacks();
        }
      });

      _isInitialized = true;
      debugPrint('ConnectivityService initialized');
    } catch (e) {
      debugPrint('Error initializing ConnectivityService: $e');
    }
  }

  /// Check if the connectivity results indicate online status
  bool _isOnline(List<ConnectivityResult> results) {
    return !results.contains(ConnectivityResult.none) && results.isNotEmpty;
  }

  /// Get current online status
  Future<bool> get isOnline async {
    if (!_isInitialized) await initialize();
    final results = await _connectivity.checkConnectivity();
    return _isOnline(results);
  }

  /// Stream of online status changes
  Stream<bool> get onOnlineStatusChanged => _onlineStatusController.stream;

  /// Get current online status (synchronous)
  bool get currentOnlineStatus => _lastOnlineStatus;

  /// Register a callback to be called when internet connection is restored
  void registerReconnectionCallback(Function() callback) {
    _reconnectionCallbacks.add(callback);
    debugPrint('Registered reconnection callback (total: ${_reconnectionCallbacks.length})');
  }

  /// Unregister a reconnection callback
  void unregisterReconnectionCallback(Function() callback) {
    _reconnectionCallbacks.remove(callback);
    debugPrint('Unregistered reconnection callback (total: ${_reconnectionCallbacks.length})');
  }

  /// Trigger all reconnection callbacks
  void _triggerReconnectionCallbacks() {
    debugPrint('Triggering reconnection callbacks...');
    for (final callback in _reconnectionCallbacks) {
      try {
        callback();
      } catch (e) {
        debugPrint('Error in reconnection callback: $e');
      }
    }
  }

  /// Get connectivity status as a string
  Future<String> getConnectivityStatus() async {
    final results = await _connectivity.checkConnectivity();

    // Prioritize WiFi over mobile over others
    if (results.contains(ConnectivityResult.wifi)) {
      return 'WiFi';
    } else if (results.contains(ConnectivityResult.mobile)) {
      return 'Mobile';
    } else if (results.contains(ConnectivityResult.ethernet)) {
      return 'Ethernet';
    } else if (results.contains(ConnectivityResult.vpn)) {
      return 'VPN';
    } else if (results.contains(ConnectivityResult.none) || results.isEmpty) {
      return 'Offline';
    } else {
      return 'Unknown';
    }
  }

  /// Check if device is offline
  Future<bool> isOffline() async {
    return !(await isOnline);
  }

  /// Dispose the service
  void dispose() {
    _subscription?.cancel();
    _onlineStatusController.close();
    _reconnectionCallbacks.clear();
    _isInitialized = false;
    debugPrint('ConnectivityService disposed');
  }

  /// Check if service is initialized
  bool get isInitialized => _isInitialized;
}
