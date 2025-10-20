import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ask_psu/user/firestore_error_handler.dart';

/// Wrapper around FirebaseFirestore to handle internal assertion failures gracefully
class FirestoreClientWrapper {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static bool _isHealthy = true;
  static DateTime? _lastErrorTime;

  /// Get a safe Firestore instance
  static FirebaseFirestore get instance {
    if (!_isHealthy && _lastErrorTime != null) {
      final timeSinceError = DateTime.now().difference(_lastErrorTime!);
      // If it's been more than 30 seconds since the last error, try to recover
      if (timeSinceError.inSeconds > 30) {
        _isHealthy = true;
        print('🔄 Firestore client marked as healthy again');
      }
    }
    return _firestore;
  }

  /// Mark Firestore as unhealthy due to internal assertion failures
  static void markUnhealthy() {
    _isHealthy = false;
    _lastErrorTime = DateTime.now();
    print(
        '⚠️ Firestore client marked as unhealthy due to internal assertion failures');
  }

  /// Check if Firestore is currently healthy
  static bool get isHealthy => _isHealthy;

  /// Safe collection access with error handling
  static CollectionReference safeCollection(String path) {
    try {
      return instance.collection(path);
    } catch (e) {
      FirestoreErrorHandler.handleError(e, 'safeCollection($path)');
      markUnhealthy();
      rethrow;
    }
  }

  /// Safe document access with error handling
  static DocumentReference safeDocument(String path) {
    try {
      return instance.doc(path);
    } catch (e) {
      FirestoreErrorHandler.handleError(e, 'safeDocument($path)');
      markUnhealthy();
      rethrow;
    }
  }

  /// Safe query execution with retry logic
  static Future<QuerySnapshot> safeGet(Query query, {Duration? timeout}) async {
    int attempts = 0;
    const maxAttempts = 3;

    while (attempts < maxAttempts) {
      try {
        final future = query.get();
        if (timeout != null) {
          return await future.timeout(timeout);
        }
        return await future;
      } catch (e) {
        attempts++;
        FirestoreErrorHandler.handleError(e, 'safeGet (attempt $attempts)');

        if (FirestoreErrorHandler.isInternalAssertionError(e)) {
          markUnhealthy();
          if (attempts >= maxAttempts) {
            print('❌ Max attempts reached for Firestore query, giving up');
            rethrow;
          }
          // Wait before retrying
          await Future.delayed(Duration(seconds: attempts * 2));
        } else {
          rethrow;
        }
      }
    }

    throw Exception(
        'Failed to execute Firestore query after $maxAttempts attempts');
  }

  /// Safe document write with retry logic
  static Future<void> safeSet(DocumentReference doc, Map<String, dynamic> data,
      {SetOptions? options}) async {
    int attempts = 0;
    const maxAttempts = 3;

    while (attempts < maxAttempts) {
      try {
        if (options != null) {
          return await doc.set(data, options);
        } else {
          return await doc.set(data);
        }
      } catch (e) {
        attempts++;
        FirestoreErrorHandler.handleError(e, 'safeSet (attempt $attempts)');

        if (FirestoreErrorHandler.isInternalAssertionError(e)) {
          markUnhealthy();
          if (attempts >= maxAttempts) {
            print('❌ Max attempts reached for Firestore write, giving up');
            rethrow;
          }
          // Wait before retrying
          await Future.delayed(Duration(seconds: attempts * 2));
        } else {
          rethrow;
        }
      }
    }

    throw Exception('Failed to write to Firestore after $maxAttempts attempts');
  }
}
