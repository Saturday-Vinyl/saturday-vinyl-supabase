import 'package:logger/logger.dart';

/// Compact single-line log printer for cleaner console output
class CompactPrinter extends LogPrinter {
  static final _levelEmojis = {
    Level.trace: '🔍',
    Level.debug: '🐛',
    Level.info: '💡',
    Level.warning: '⚠️',
    Level.error: '❌',
    Level.fatal: '💀',
  };

  static final _levelLabels = {
    Level.trace: 'TRACE',
    Level.debug: 'DEBUG',
    Level.info: 'INFO',
    Level.warning: 'WARN',
    Level.error: 'ERROR',
    Level.fatal: 'FATAL',
  };

  @override
  List<String> log(LogEvent event) {
    final emoji = _levelEmojis[event.level] ?? '📝';
    final label = _levelLabels[event.level] ?? 'LOG';
    final time = _formatTime(event.time);
    final message = event.message;

    final lines = <String>[];

    // Main log line - compact single line
    lines.add('$emoji $time [$label] $message');

    // Only show error/stacktrace for warnings and above
    if (event.error != null && event.level.index >= Level.warning.index) {
      lines.add('   Error: ${event.error}');
    }
    if (event.stackTrace != null && event.level.index >= Level.error.index) {
      // Show only first 3 stack frames for errors
      final frames = event.stackTrace.toString().split('\n').take(3);
      for (final frame in frames) {
        if (frame.trim().isNotEmpty) {
          lines.add('   $frame');
        }
      }
    }

    return lines;
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}.'
        '${time.millisecond.toString().padLeft(3, '0')}';
  }
}

/// Application logger wrapper
/// Provides consistent logging throughout the app
class AppLogger {
  AppLogger._(); // Private constructor

  static final Logger _logger = Logger(
    printer: CompactPrinter(),
    level: Level.debug, // Set minimum level (trace < debug < info < warning < error < fatal)
  );

  /// Log debug message
  /// Use for detailed information during development
  static void debug(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger.d(message, error: error, stackTrace: stackTrace);
  }

  /// Log info message
  /// Use for general informational messages
  static void info(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger.i(message, error: error, stackTrace: stackTrace);
  }

  /// Log warning message
  /// Use for potentially harmful situations
  static void warning(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger.w(message, error: error, stackTrace: stackTrace);
  }

  /// Log error message
  /// Use for error events that might still allow the app to continue
  static void error(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger.e(message, error: error, stackTrace: stackTrace);
  }

  /// Log fatal error message
  /// Use for very severe error events that will presumably lead the app to abort
  static void fatal(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger.f(message, error: error, stackTrace: stackTrace);
  }

  /// Log with custom level
  static void log(Level level, dynamic message,
      [dynamic error, StackTrace? stackTrace]) {
    _logger.log(level, message, error: error, stackTrace: stackTrace);
  }

  /// Close the logger
  /// Call this when the app is shutting down
  static void close() {
    _logger.close();
  }
}
