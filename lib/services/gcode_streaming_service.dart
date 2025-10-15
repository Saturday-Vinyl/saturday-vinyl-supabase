import 'dart:async';
import 'package:saturday_app/services/machine_connection_service.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// Streaming status
enum StreamingStatus {
  idle,
  streaming,
  paused,
  completed,
  error,
  cancelled,
}

/// gCode streaming progress
class StreamingProgress {
  final int totalLines;
  final int sentLines;
  final int completedLines;
  final StreamingStatus status;
  final String? currentLine;
  final String? error;

  StreamingProgress({
    required this.totalLines,
    required this.sentLines,
    required this.completedLines,
    required this.status,
    this.currentLine,
    this.error,
  });

  double get progressPercent =>
      totalLines > 0 ? (completedLines / totalLines) * 100 : 0;

  double get percentComplete => progressPercent;

  int get currentLineNumber => completedLines + 1;

  int get remainingLines => totalLines - completedLines;

  String get lastCommand => currentLine ?? '';

  @override
  String toString() =>
      'StreamingProgress($completedLines/$totalLines lines, $status)';
}

/// Result of streaming operation
class StreamingResult {
  final bool success;
  final String? message;
  final int? linesCompleted;

  StreamingResult({
    required this.success,
    this.message,
    this.linesCompleted,
  });
}

/// Service for streaming gCode to machines line-by-line
class GCodeStreamingService {
  final MachineConnectionService _connectionService;

  StreamingStatus _status = StreamingStatus.idle;
  List<String> _gcodeLines = [];
  int _sentLines = 0;
  int _completedLines = 0;
  int _pendingAcknowledgments = 0;
  String? _currentLine;
  String? _error;
  String? _errorDetails; // Store detailed error for re-logging
  bool _errorOccurred = false; // Flag to suppress ok logging after error

  final _progressController = StreamController<StreamingProgress>.broadcast();
  StreamSubscription<String>? _responseSubscription;

  Timer? _statusPollTimer;
  Timer? _progressThrottleTimer;
  bool _isPaused = false;
  bool _progressUpdatePending = false;

  /// Stream of streaming progress updates
  Stream<StreamingProgress> get progressStream => _progressController.stream;

  /// Current streaming status
  StreamingStatus get status => _status;

  /// Check if currently streaming
  bool get isStreaming => _status == StreamingStatus.streaming;

  /// Check if paused
  bool get isPaused => _isPaused;

  GCodeStreamingService(this._connectionService);

  /// Start streaming gCode to the machine
  ///
  /// [gcodeContent] - Complete gCode file content as string
  /// [maxPendingLines] - Maximum lines to send before waiting for acknowledgment
  Future<bool> startStreaming(
    String gcodeContent, {
    int maxPendingLines = 5,
  }) async {
    if (!_connectionService.isConnected) {
      AppLogger.error('Cannot start streaming: not connected to machine', null, null);
      return false;
    }

    if (_status == StreamingStatus.streaming) {
      AppLogger.warning('Already streaming gCode');
      return false;
    }

    try {
      AppLogger.info('Starting gCode streaming');

      // Parse and prepare gCode
      _gcodeLines = _prepareGCode(gcodeContent);
      _sentLines = 0;
      _completedLines = 0;
      _pendingAcknowledgments = 0;
      _currentLine = null;
      _error = null;
      _errorDetails = null;
      _errorOccurred = false;
      _isPaused = false;

      if (_gcodeLines.isEmpty) {
        AppLogger.warning('No valid gCode lines to stream');
        return false;
      }

      AppLogger.info('Prepared ${_gcodeLines.length} gCode lines for streaming');

      // Disable verbose logging for large gcode files (>1000 lines) to improve performance
      if (_gcodeLines.length > 1000) {
        _connectionService.setVerboseLogging(false);
        AppLogger.info('Disabled verbose logging for large gcode file (${_gcodeLines.length} lines)');
      }

      // Subscribe to machine responses
      _responseSubscription = _connectionService.responseStream.listen(
        (response) => _handleMachineResponse(response),
        onError: (error) {
          AppLogger.error('Error in response stream', error, null);
          _setError('Response stream error: $error');
        },
      );

      // Start streaming
      _updateStatus(StreamingStatus.streaming);
      _streamNextLines(maxPendingLines);

      // Start periodic status polling (reduced frequency to avoid overwhelming system)
      _statusPollTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _connectionService.requestStatus(),
      );

      // Start progress throttle timer (emit updates at most every 200ms)
      _progressThrottleTimer = Timer.periodic(
        const Duration(milliseconds: 200),
        (_) => _emitThrottledProgress(),
      );

      return true;
    } catch (error, stackTrace) {
      AppLogger.error('Error starting gCode streaming', error, stackTrace);
      _setError('Failed to start streaming: $error');
      return false;
    }
  }

  /// Pause streaming
  void pause() {
    if (_status == StreamingStatus.streaming) {
      _isPaused = true;
      _connectionService.feedHold();
      _updateStatus(StreamingStatus.paused);
      AppLogger.info('gCode streaming paused');
    }
  }

  /// Resume streaming
  void resume() {
    if (_status == StreamingStatus.paused) {
      _isPaused = false;
      _connectionService.cycleStart();
      _updateStatus(StreamingStatus.streaming);
      AppLogger.info('gCode streaming resumed');
    }
  }

  /// Stop streaming (alias for cancel)
  void stop() {
    cancel();
  }

  /// Stream gCode and wait for completion
  /// Returns a StreamingResult when streaming is complete
  Future<StreamingResult> streamGCode(String gcodeContent) async {
    final started = await startStreaming(gcodeContent);

    if (!started) {
      return StreamingResult(
        success: false,
        message: 'Failed to start streaming',
        linesCompleted: 0,
      );
    }

    // Wait for streaming to complete
    await for (final progress in progressStream) {
      if (progress.status == StreamingStatus.completed) {
        return StreamingResult(
          success: true,
          message: 'Streaming completed successfully',
          linesCompleted: progress.completedLines,
        );
      } else if (progress.status == StreamingStatus.error) {
        return StreamingResult(
          success: false,
          message: progress.error ?? 'Unknown error',
          linesCompleted: progress.completedLines,
        );
      } else if (progress.status == StreamingStatus.cancelled) {
        return StreamingResult(
          success: false,
          message: 'Streaming was cancelled',
          linesCompleted: progress.completedLines,
        );
      }
    }

    // Fallback (should not reach here)
    return StreamingResult(
      success: false,
      message: 'Streaming ended unexpectedly',
      linesCompleted: _completedLines,
    );
  }

  /// Cancel streaming
  Future<void> cancel() async {
    if (_status == StreamingStatus.streaming || _status == StreamingStatus.paused) {
      await _connectionService.emergencyStop();
      _updateStatus(StreamingStatus.cancelled);
      await _cleanup();
      AppLogger.info('gCode streaming cancelled');
    }
  }

  /// Emergency stop - immediately halt all motion
  Future<void> emergencyStop() async {
    await _connectionService.emergencyStop();
    _updateStatus(StreamingStatus.error);
    _setError('Emergency stop activated');
    await _cleanup();
    AppLogger.warning('Emergency stop executed');
  }

  /// Prepare gCode for streaming
  List<String> _prepareGCode(String content) {
    final lines = <String>[];

    for (var line in content.split('\n')) {
      // Trim whitespace
      line = line.trim();

      // Skip empty lines
      if (line.isEmpty) continue;

      // Remove comments
      final commentIndex = line.indexOf(';');
      if (commentIndex >= 0) {
        line = line.substring(0, commentIndex).trim();
      }

      // Skip lines that are only comments
      if (line.isEmpty) continue;

      // Convert to uppercase (grbl standard)
      line = line.toUpperCase();

      lines.add(line);
    }

    return lines;
  }

  /// Stream next batch of lines
  void _streamNextLines(int maxPendingLines) {
    if (_isPaused || _status != StreamingStatus.streaming) {
      return;
    }

    // Check connection status before streaming
    if (!_connectionService.isConnected) {
      _setError('Lost connection to machine');
      return;
    }

    // Send lines up to the max pending limit
    while (_sentLines < _gcodeLines.length &&
        _pendingAcknowledgments < maxPendingLines) {
      final line = _gcodeLines[_sentLines];
      final lineNumber = _sentLines; // Capture line number to avoid race condition
      _currentLine = line;

      // Send command with retry logic
      _sendCommandWithRetry(line, lineNumber, maxRetries: 3);

      _sentLines++;
      _pendingAcknowledgments++;
      _markProgressPending();

      // Only log every 100 lines to avoid overwhelming logs
      if (_sentLines % 100 == 0 || _sentLines == _gcodeLines.length) {
        AppLogger.debug('Sent $_sentLines/${_gcodeLines.length} lines');
      }
    }

    // Check if all lines have been sent
    if (_sentLines >= _gcodeLines.length && _pendingAcknowledgments == 0) {
      _complete();
    }
  }

  /// Send command with retry logic
  Future<void> _sendCommandWithRetry(
    String command,
    int lineNumber, {
    int maxRetries = 3,
    int retryCount = 0,
  }) async {
    final success = await _connectionService.sendCommand(command);

    if (!success) {
      if (retryCount < maxRetries) {
        // Log retry attempt (always log failures, even with verbose logging off)
        AppLogger.warning(
          'Failed to send line $lineNumber, retrying (${retryCount + 1}/$maxRetries): ${command.trim()}',
        );

        // Brief delay before retry
        await Future.delayed(Duration(milliseconds: 50 * (retryCount + 1)));

        // Check if still streaming before retry
        if (_status == StreamingStatus.streaming) {
          await _sendCommandWithRetry(
            command,
            lineNumber,
            maxRetries: maxRetries,
            retryCount: retryCount + 1,
          );
        }
      } else {
        // All retries exhausted - log detailed error and fail
        final errorMsg =
            'Failed to send line $lineNumber after $maxRetries attempts: ${command.trim()}';
        AppLogger.error(errorMsg, null, null);
        _setError(errorMsg);
      }
    }
  }

  /// Handle response from machine
  void _handleMachineResponse(String response) {
    final trimmed = response.trim();

    // Check for "ok" acknowledgment
    if (trimmed == 'ok' || trimmed.startsWith('ok')) {
      _pendingAcknowledgments--;
      _completedLines++;
      _markProgressPending();

      // Only log if no error has occurred (to prevent drowning out error messages)
      if (!_errorOccurred) {
        // Only log every 100 lines to avoid overwhelming logs
        if (_completedLines % 100 == 0 || _completedLines == _gcodeLines.length) {
          AppLogger.debug('Completed $_completedLines/${_gcodeLines.length} lines');
        }
      }

      // Send more lines if available (and no error has occurred)
      if (_status == StreamingStatus.streaming && !_isPaused && !_errorOccurred) {
        _streamNextLines(5); // Send up to 5 more lines
      }

      // Check for completion
      if (_completedLines >= _gcodeLines.length) {
        _complete();
      }
    }
    // Check for errors
    else if (trimmed.startsWith('error:')) {
      // Set flag to stop further command sending and suppress ok logging
      _errorOccurred = true;

      // Build detailed error message with context
      final lineNum = _completedLines + 1; // The line that just failed
      final failedCommand = _currentLine ?? 'unknown';
      final errorMsg = '''
╔════════════════════════════════════════════════════════════════
║ GRBL ERROR DURING STREAMING
╠════════════════════════════════════════════════════════════════
║ Machine Response: $trimmed
║ At Line: $lineNum of ${_gcodeLines.length}
║ Failed Command: $failedCommand
║ Progress: $_completedLines lines completed before error
╚════════════════════════════════════════════════════════════════''';

      // Store error details for re-logging after cleanup
      _errorDetails = errorMsg;

      // Log prominently (this will show in Flutter logs)
      AppLogger.error(errorMsg, null, null);

      // Also use print() to ensure it shows in console
      // ignore: avoid_print
      print('\n\n$errorMsg\n\n');

      // Set error for UI
      _setError('Machine error at line $lineNum: $trimmed');
    }
    // Check for alarm
    else if (trimmed.startsWith('ALARM:')) {
      // Set flag to stop further command sending and suppress ok logging
      _errorOccurred = true;

      // Build detailed alarm message with context
      final lineNum = _completedLines + 1;
      final failedCommand = _currentLine ?? 'unknown';
      final alarmMsg = '''
╔════════════════════════════════════════════════════════════════
║ GRBL ALARM DURING STREAMING
╠════════════════════════════════════════════════════════════════
║ Machine Response: $trimmed
║ At Line: $lineNum of ${_gcodeLines.length}
║ Last Command: $failedCommand
║ Progress: $_completedLines lines completed before alarm
╚════════════════════════════════════════════════════════════════''';

      // Store error details for re-logging after cleanup
      _errorDetails = alarmMsg;

      // Log prominently (this will show in Flutter logs)
      AppLogger.error(alarmMsg, null, null);

      // Also use print() to ensure it shows in console
      // ignore: avoid_print
      print('\n\n$alarmMsg\n\n');

      // Set error for UI
      _setError('Machine alarm at line $lineNum: $trimmed');
    }
  }

  /// Mark streaming as complete
  void _complete() {
    if (_status != StreamingStatus.completed) {
      _updateStatus(StreamingStatus.completed);
      _emitProgress();
      _cleanup();
      AppLogger.info('gCode streaming completed successfully');
    }
  }

  /// Set error state
  void _setError(String errorMessage) {
    _error = errorMessage;
    _updateStatus(StreamingStatus.error);
    _emitProgress();
    _cleanup();

    // Log error prominently with context
    final contextMsg = '''
╔════════════════════════════════════════════════════════════════
║ GCODE STREAMING FAILED
╠════════════════════════════════════════════════════════════════
║ Error: $errorMessage
║
║ Context:
║   Total Lines: ${_gcodeLines.length}
║   Sent: $_sentLines
║   Completed: $_completedLines
║   Pending: $_pendingAcknowledgments
║   Current Line: ${_currentLine ?? 'none'}
╚════════════════════════════════════════════════════════════════''';

    AppLogger.error(contextMsg, null, null);

    // Also use print() to ensure it shows in console
    // ignore: avoid_print
    print('\n\n$contextMsg\n\n');
  }

  /// Update status and emit progress
  void _updateStatus(StreamingStatus newStatus) {
    if (_status != newStatus) {
      _status = newStatus;
      _emitProgress();
    }
  }

  /// Mark that a progress update is pending (throttled)
  void _markProgressPending() {
    _progressUpdatePending = true;
  }

  /// Emit throttled progress update (called by timer)
  void _emitThrottledProgress() {
    if (_progressUpdatePending) {
      _emitProgress();
      _progressUpdatePending = false;
    }
  }

  /// Emit progress update immediately
  void _emitProgress() {
    final progress = StreamingProgress(
      totalLines: _gcodeLines.length,
      sentLines: _sentLines,
      completedLines: _completedLines,
      status: _status,
      currentLine: _currentLine,
      error: _error,
    );

    _progressController.add(progress);
  }

  /// Clean up resources
  Future<void> _cleanup() async {
    await _responseSubscription?.cancel();
    _responseSubscription = null;

    _statusPollTimer?.cancel();
    _statusPollTimer = null;

    _progressThrottleTimer?.cancel();
    _progressThrottleTimer = null;

    // Re-enable verbose logging after streaming
    _connectionService.setVerboseLogging(true);

    // Re-log error after all responses have been processed
    if (_errorDetails != null) {
      // Wait a brief moment to ensure all pending logs are flushed
      await Future.delayed(const Duration(milliseconds: 100));

      // Re-log the error so it appears at the end of the logs
      AppLogger.error('ERROR SUMMARY (re-logged after cleanup):\n$_errorDetails', null, null);
      // ignore: avoid_print
      print('\n\n═══════════════════════════════════════════════════════════════');
      // ignore: avoid_print
      print('ERROR SUMMARY (re-logged after cleanup):');
      // ignore: avoid_print
      print('$_errorDetails');
      // ignore: avoid_print
      print('═══════════════════════════════════════════════════════════════\n\n');
    }
  }

  /// Dispose of service
  void dispose() {
    _cleanup();
    _progressController.close();
  }
}
