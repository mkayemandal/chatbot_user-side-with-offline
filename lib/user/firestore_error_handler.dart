import 'package:logger/logger.dart';

/// Centralized error handler for Firestore operations
class FirestoreErrorHandler {
  static final Logger _logger = Logger();

  /// Handle Firestore errors gracefully
  static void handleError(dynamic error, String operation) {
    if (error.toString().contains('INTERNAL ASSERTION FAILED')) {
      _logger
          .w('Firestore internal assertion failed during $operation: $error');
      // Don't crash the app, just log the error
      return;
    }

    if (error.toString().contains('Unexpected state')) {
      _logger.w('Firestore unexpected state during $operation: $error');
      return;
    }

    // Log other errors normally
    _logger.e('Firestore error during $operation: $error');
  }

  /// Wrap Firestore operations with error handling
  static Future<T?> safeFirestoreOperation<T>(
    Future<T> Function() operation,
    String operationName, {
    T? fallbackValue,
  }) async {
    try {
      return await operation();
    } catch (error) {
      handleError(error, operationName);
      return fallbackValue;
    }
  }

  /// Check if error is a Firestore internal assertion failure
  static bool isInternalAssertionError(dynamic error) {
    return error.toString().contains('INTERNAL ASSERTION FAILED') ||
        error.toString().contains('Unexpected state');
  }
}
