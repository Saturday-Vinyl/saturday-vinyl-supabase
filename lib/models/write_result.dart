import 'package:equatable/equatable.dart';
import 'package:saturday_app/config/rfid_config.dart';

/// Result of a tag write operation
class WriteResult extends Equatable {
  /// Whether the write operation succeeded
  final bool success;

  /// Error code from the UHF module (if failed)
  final int? errorCode;

  /// Human-readable error message
  final String? errorMessage;

  /// The EPC that was written (if successful)
  final List<int>? writtenEpc;

  /// Time taken for the write operation
  final Duration? duration;

  const WriteResult({
    required this.success,
    this.errorCode,
    this.errorMessage,
    this.writtenEpc,
    this.duration,
  });

  /// Create a successful write result
  factory WriteResult.successful({
    required List<int> epc,
    Duration? duration,
  }) {
    return WriteResult(
      success: true,
      writtenEpc: epc,
      duration: duration,
    );
  }

  /// Create a failed write result from an error code
  factory WriteResult.failed(int errorCode, {Duration? duration}) {
    return WriteResult(
      success: false,
      errorCode: errorCode,
      errorMessage: RfidConfig.getErrorMessage(errorCode),
      duration: duration,
    );
  }

  /// Create a failed write result from an exception
  factory WriteResult.error(String message, {Duration? duration}) {
    return WriteResult(
      success: false,
      errorMessage: message,
      duration: duration,
    );
  }

  /// Create a timeout result
  factory WriteResult.timeout({Duration? duration}) {
    return WriteResult(
      success: false,
      errorMessage: 'Write operation timed out',
      duration: duration,
    );
  }

  /// Get EPC as hex string (if available)
  String? get writtenEpcHex => writtenEpc
      ?.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join();

  @override
  List<Object?> get props =>
      [success, errorCode, errorMessage, writtenEpc, duration];

  @override
  String toString() {
    if (success) {
      return 'WriteResult.success(epc: $writtenEpcHex)';
    } else {
      return 'WriteResult.failed(code: $errorCode, message: $errorMessage)';
    }
  }
}
