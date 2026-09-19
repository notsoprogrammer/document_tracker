import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/supabase_config.dart';

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


        _onlineStatusController.add(isNowOnline);

        // If we just came back online, trigger reconnection callbacks
        if (!wasOnline && isNowOnline) {
          _triggerReconnectionCallbacks();
        }
      });

      _isInitialized = true;
    } catch (e) {
    }
  }

  /// Check if the connectivity results indicate online status
  bool _isOnline(List<ConnectivityResult> results) {
    return !results.contains(ConnectivityResult.none) && results.isNotEmpty;
  }

  // Cached reachability probe result — avoids a network round-trip on every
  // isOnline call while still catching captive portals / dead gateways.
  bool? _lastReachable;
  DateTime? _lastReachableCheck;
  static const Duration _reachabilityCacheTtl = Duration(seconds: 15);

  /// Get current online status.
  ///
  /// A network interface being up is NOT the same as having internet — office
  /// WiFi behind a captive portal or with a dead gateway reports "connected".
  /// Uploads that trust that hang until they time out and burn their retries,
  /// so we verify the backend is actually reachable.
  Future<bool> get isOnline async {
    if (!_isInitialized) await initialize();
    final results = await _connectivity.checkConnectivity();
    if (!_isOnline(results)) {
      _lastReachable = false;
      _lastReachableCheck = DateTime.now();
      return false;
    }
    return _isBackendReachable();
  }

  /// Interface-level check only — cheap, no network round-trip.
  /// Use when you only need to know whether a radio is up.
  Future<bool> get hasNetworkInterface async {
    if (!_isInitialized) await initialize();
    return _isOnline(await _connectivity.checkConnectivity());
  }

  Future<bool> _isBackendReachable() async {
    final cached = _lastReachable;
    final checkedAt = _lastReachableCheck;
    if (cached != null &&
        checkedAt != null &&
        DateTime.now().difference(checkedAt) < _reachabilityCacheTtl) {
      return cached;
    }

    bool reachable;
    try {
      final response = await http
          .get(Uri.parse('${SupabaseConfig.supabaseUrl}/auth/v1/health'),
              headers: {'apikey': SupabaseConfig.supabaseAnonKey})
          .timeout(const Duration(seconds: 5));
      // Any real HTTP response means we got through to Supabase. A captive
      // portal would time out or return its own redirect/error page.
      reachable = response.statusCode < 500;
    } catch (e) {
      reachable = false;
    }

    _lastReachable = reachable;
    _lastReachableCheck = DateTime.now();
    return reachable;
  }

  /// Stream of online status changes
  Stream<bool> get onOnlineStatusChanged => _onlineStatusController.stream;

  /// Get current online status (synchronous)
  bool get currentOnlineStatus => _lastOnlineStatus;

  /// Register a callback to be called when internet connection is restored
  void registerReconnectionCallback(Function() callback) {
    _reconnectionCallbacks.add(callback);
  }

  /// Unregister a reconnection callback
  void unregisterReconnectionCallback(Function() callback) {
    _reconnectionCallbacks.remove(callback);
  }

  /// Trigger all reconnection callbacks
  void _triggerReconnectionCallbacks() {
    for (final callback in _reconnectionCallbacks) {
      try {
        callback();
      } catch (e) {
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
  }

  /// Check if service is initialized
  bool get isInitialized => _isInitialized;
}
