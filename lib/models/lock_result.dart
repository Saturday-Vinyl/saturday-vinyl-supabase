import 'package:equatable/equatable.dart';
import 'package:saturday_app/config/rfid_config.dart';

/// Result of a tag lock operation
class LockResult extends Equatable {
  /// Whether the lock operation succeeded
  final bool success;

  /// Error code from the UHF module (if failed)
  final int? errorCode;

  /// Human-readable error message
  final String? errorMessage;

  /// Time taken for the lock operation
  final Duration? duration;

  const LockResult({
    required this.success,
    this.errorCode,
    this.errorMessage,
    this.duration,
  });

  /// Create a successful lock result
  factory LockResult.successful({Duration? duration}) {
    return LockResult(
      success: true,
      duration: duration,
    );
  }

  /// Create a failed lock result from an error code
  factory LockResult.failed(int errorCode, {Duration? duration}) {
    return LockResult(
      success: false,
      errorCode: errorCode,
      errorMessage: RfidConfig.getErrorMessage(errorCode),
      duration: duration,
    );
  }

  /// Create a failed lock result from an exception
  factory LockResult.error(String message, {Duration? duration}) {
    return LockResult(
      success: false,
      errorMessage: message,
      duration: duration,
    );
  }

  /// Create a timeout result
  factory LockResult.timeout({Duration? duration}) {
    return LockResult(
      success: false,
      errorMessage: 'Lock operation timed out',
      duration: duration,
    );
  }

  @override
  List<Object?> get props => [success, errorCode, errorMessage, duration];

  @override
  String toString() {
    if (success) {
      return 'LockResult.success()';
    } else {
      return 'LockResult.failed(code: $errorCode, message: $errorMessage)';
    }
  }
}
