import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Global connectivity watcher (singleton).
class ConnectionHandler {
  // Singleton instance
  static final ConnectionHandler instance = ConnectionHandler._internal();

  final _controller = StreamController<ConnectivityResult>.broadcast();
  late final StreamSubscription<List<ConnectivityResult>> _subscription;
  bool _isOnline = true;

  // Private constructor
  ConnectionHandler._internal() {
    // Listen to changes (now emits a List<ConnectivityResult>)
    _subscription = Connectivity().onConnectivityChanged.listen((results) {
      // Normalize: pick first if available, otherwise none
      final result =
          results.isNotEmpty ? results.first : ConnectivityResult.none;

      final wasOnline = _isOnline;
      _isOnline = result != ConnectivityResult.none;

      // Manage Firestore network state
      _manageFirestoreNetworkState(_isOnline);

      _controller.add(result);

      // Log connectivity changes
      if (wasOnline != _isOnline) {
        print('🌐 Connection changed: ${_isOnline ? "ONLINE" : "OFFLINE"}');
      }
    });

    // Emit initial state
    Connectivity().checkConnectivity().then((results) {
      final result =
          results.isNotEmpty ? results.first : ConnectivityResult.none;

      _isOnline = result != ConnectivityResult.none;
      _manageFirestoreNetworkState(_isOnline);
      _controller.add(result);

      print('🌐 Initial connection state: ${_isOnline ? "ONLINE" : "OFFLINE"}');
    });
  }

  /// Manage Firestore network state based on connectivity
  void _manageFirestoreNetworkState(bool isOnline) {
    try {
      // TEMPORARILY DISABLE NETWORK STATE MANAGEMENT TO PREVENT INTERNAL ASSERTION FAILURES
      // The frequent enable/disable calls are causing Firestore internal state issues
      print(
          '🌐 Connection state changed to: ${isOnline ? "ONLINE" : "OFFLINE"} (Firestore network management disabled)');

      // Comment out the problematic network management that's causing internal assertion failures
      // if (_lastNetworkStateChange != null &&
      //     DateTime.now().difference(_lastNetworkStateChange!) <
      //         const Duration(seconds: 5)) {
      //   return; // Skip if called too recently
      // }

      // _lastNetworkStateChange = DateTime.now();

      // if (isOnline) {
      //   // Enable network when online
      //   FirebaseFirestore.instance.enableNetwork();
      //   print('✅ Firestore network enabled');
      // } else {
      //   // Disable network when offline to prevent reconnection attempts
      //   FirebaseFirestore.instance.disableNetwork();
      //   print('❌ Firestore network disabled - using offline cache only');
      // }
    } catch (e) {
      print('⚠️ Error managing Firestore network state: $e');
    }
  }

  // DateTime? _lastNetworkStateChange; // Temporarily unused due to disabled network management

  /// Raw connectivity stream
  Stream<ConnectivityResult> get connectivityStream => _controller.stream;

  /// Convenience boolean stream (true = online, false = offline)
  Stream<bool> get connectionStream =>
      _controller.stream.map((r) => r != ConnectivityResult.none);

  /// Get current online status
  bool get isOnline => _isOnline;

  void dispose() {
    _subscription.cancel();
    _controller.close();
  }
}
