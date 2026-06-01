import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;
import 'package:flutter/material.dart';

import '../legacy/compatibility.dart' show LikeWriteException;

/// Utility class for consistent error handling
class AppError {
  /// Show error message with snackbar
  static void showError(BuildContext context, String message, {VoidCallback? onDismiss}) {
    if (!context.mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        action: SnackBarAction(
          label: 'Dismiss',
          textColor: Colors.white,
          onPressed: onDismiss ?? () {},
        ),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Show success message with snackbar
  static void showSuccess(BuildContext context, String message, {VoidCallback? onDismiss}) {
    if (!context.mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        action: SnackBarAction(
          label: 'Dismiss',
          textColor: Colors.white,
          onPressed: onDismiss ?? () {},
        ),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Show info message with snackbar
  static void showInfo(BuildContext context, String message, {VoidCallback? onDismiss}) {
    if (!context.mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.blue,
        action: SnackBarAction(
          label: 'Dismiss',
          textColor: Colors.white,
          onPressed: onDismiss ?? () {},
        ),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Show warning message with snackbar
  static void showWarning(BuildContext context, String message, {VoidCallback? onDismiss}) {
    if (!context.mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning_amber_outlined, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.orange,
        action: SnackBarAction(
          label: 'Dismiss',
          textColor: Colors.white,
          onPressed: onDismiss ?? () {},
        ),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Show error dialog
  static Future<void> showErrorDialog(
    BuildContext context, {
    required String title,
    required String message,
    String buttonText = 'OK',
    VoidCallback? onButtonPressed,
  }) {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.error, color: Colors.red),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onButtonPressed?.call();
            },
            child: Text(buttonText),
          ),
        ],
      ),
    );
  }

  /// Show success dialog
  static Future<void> showSuccessDialog(
    BuildContext context, {
    required String title,
    required String message,
    String buttonText = 'OK',
    VoidCallback? onButtonPressed,
  }) {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onButtonPressed?.call();
            },
            child: Text(buttonText),
          ),
        ],
      ),
    );
  }

  /// Show confirmation dialog
  static Future<bool> showConfirmationDialog(
    BuildContext context, {
    required String title,
    required String message,
    String confirmText = 'Confirm',
    String cancelText = 'Cancel',
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.help_outline, color: Colors.blue),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(cancelText),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Handle API errors consistently
  static String getErrorMessage(dynamic error) {
    if (error == null) return 'An unknown error occurred';
    
    if (error is String) {
      return error;
    }
    
    if (error.toString().contains('network')) {
      return 'Network error. Please check your internet connection.';
    }
    
    if (error.toString().contains('timeout')) {
      return 'Request timed out. Please try again.';
    }
    
    if (error.toString().contains('permission')) {
      return 'Permission denied. You don\'t have access to this feature.';
    }
    
    if (error.toString().contains('not found')) {
      return 'The requested resource was not found.';
    }
    
    if (error.toString().contains('unauthorized')) {
      return 'You are not authorized. Please login again.';
    }
    
    return error.toString();
  }

  /// User-facing text for Firestore failures (likes, profile fields, etc.).
  static String firebaseWriteMessage(Object e) {
    if (e is LikeWriteException) return e.message;
    if (e is FirebaseException) {
      switch (e.code) {
        case 'permission-denied':
          return 'Permission denied. Try signing in again.';
        case 'failed-precondition':
          return 'Database needs a quick sync. Try again in a few seconds.';
        case 'unavailable':
        case 'deadline-exceeded':
        case 'resource-exhausted':
          return 'Network or server busy. Please try again.';
        case 'aborted':
          return 'Request was interrupted. Please try again.';
        default:
          return e.message?.isNotEmpty == true
              ? e.message!
              : 'Something went wrong. Please try again.';
      }
    }
    return getErrorMessage(e);
  }

  /// Log error for debugging
  static void logError(String context, dynamic error, [StackTrace? stackTrace]) {
    debugPrint('🔴 Error in $context: $error');
    if (stackTrace != null) {
      debugPrint('🔴 Stack trace: $stackTrace');
    }
  }

  /// Handle async errors in try-catch blocks
  static Future<T?> handleAsyncError<T>(
    BuildContext context,
    Future<T> Function() operation, {
    String? errorMessage,
    bool showDialog = false,
  }) async {
    try {
      return await operation();
    } catch (error, stackTrace) {
      logError('Async Operation', error, stackTrace);
      
      final message = errorMessage ?? getErrorMessage(error);

      if (!context.mounted) return null;
      
      if (showDialog) {
        await showErrorDialog(
          context,
          title: 'Error',
          message: message,
        );
      } else {
        showError(context, message);
      }
      
      return null;
    }
  }
}
