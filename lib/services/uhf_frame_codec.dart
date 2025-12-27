import 'package:saturday_app/config/rfid_config.dart';
import 'package:saturday_app/models/uhf_frame.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// Codec for encoding and decoding UHF module communication frames
///
/// Frame format:
/// [Header 0xBB] [Type] [Command] [PL MSB] [PL LSB] [Parameters...] [Checksum] [End 0x7E]
///
/// Where:
/// - Header: Always 0xBB
/// - Type: 0x00 = Command, 0x01 = Response, 0x02 = Notice
/// - Command: The command/response code
/// - PL MSB/LSB: Parameter length as 16-bit big-endian
/// - Parameters: Variable length payload
/// - Checksum: Sum of Type + Command + PL + Parameters (lowest byte)
/// - End: Always 0x7E
class UhfFrameCodec {
  /// Minimum frame size: Header(1) + Type(1) + Command(1) + PL(2) + Checksum(1) + End(1) = 7
  static const int minFrameSize = 7;

  /// Build a command frame to send to the UHF module
  ///
  /// [command] - The command code (e.g., RfidConfig.cmdMultiplePoll)
  /// [parameters] - Optional parameter bytes
  ///
  /// Returns the complete frame bytes ready to send
  static List<int> buildCommand(int command, [List<int> parameters = const []]) {
    final frame = <int>[
      RfidConfig.frameHeader,
      RfidConfig.frameTypeCommand,
      command,
      (parameters.length >> 8) & 0xFF, // PL MSB
      parameters.length & 0xFF, // PL LSB
      ...parameters,
    ];

    // Calculate checksum: sum of Type + Command + PL + Parameters
    var checksum = RfidConfig.frameTypeCommand + command;
    checksum += (parameters.length >> 8) & 0xFF;
    checksum += parameters.length & 0xFF;
    for (final param in parameters) {
      checksum += param;
    }
    frame.add(checksum & 0xFF);
    frame.add(RfidConfig.frameEnd);

    return frame;
  }

  /// Build a Single Poll command
  ///
  /// Polls for a single tag in the RF field
  static List<int> buildSinglePoll() {
    return buildCommand(RfidConfig.cmdSinglePoll);
  }

  /// Build a Multiple Poll command
  ///
  /// [count] - Number of times to poll (0x0000 = continuous until stopped)
  static List<int> buildMultiplePoll({int count = 0}) {
    return buildCommand(RfidConfig.cmdMultiplePoll, [
      (count >> 8) & 0xFF,
      count & 0xFF,
    ]);
  }

  /// Build a Stop Multiple Poll command
  static List<int> buildStopMultiplePoll() {
    return buildCommand(RfidConfig.cmdStopMultiplePoll);
  }

  /// Build a Write EPC command
  ///
  /// [accessPassword] - 4-byte access password
  /// [epcBytes] - The EPC data to write (typically 12 bytes for 96-bit EPC)
  ///
  /// M100 protocol format for Write Tag Memory (0x49):
  /// - Access Password: 4 bytes (AP)
  /// - Memory Bank: 1 byte (0x01 = EPC, 0x02 = TID, 0x03 = User)
  /// - Start Address: 2 bytes (SA MSB, SA LSB) - EPC data starts at word 0x0002
  /// - Data Length: 2 bytes (DL MSB, DL LSB) - length in words
  /// - Data: variable length (DT - the EPC bytes)
  static List<int> buildWriteEpc(List<int> accessPassword, List<int> epcBytes) {
    if (accessPassword.length != 4) {
      throw ArgumentError('Access password must be 4 bytes');
    }
    if (epcBytes.length != RfidConfig.epcLengthBytes) {
      throw ArgumentError('EPC must be ${RfidConfig.epcLengthBytes} bytes');
    }

    final wordCount = epcBytes.length ~/ 2; // 12 bytes = 6 words
    final parameters = <int>[
      ...accessPassword,
      RfidConfig.memBankEpc,
      // Start Address (SA) as 2 bytes (MSB, LSB) - EPC data starts at word 2
      (RfidConfig.epcWriteStartAddr >> 8) & 0xFF, // SA MSB (0x00)
      RfidConfig.epcWriteStartAddr & 0xFF,        // SA LSB (0x02)
      // Data Length (DL) as 2 bytes (MSB, LSB) - length in words
      (wordCount >> 8) & 0xFF,                    // DL MSB (0x00)
      wordCount & 0xFF,                           // DL LSB (0x06)
      ...epcBytes,
    ];

    return buildCommand(RfidConfig.cmdWriteEpc, parameters);
  }

  /// Build a Lock Tag command
  ///
  /// [accessPassword] - 4-byte access password
  /// [lockPayload] - 3-byte lock configuration
  static List<int> buildLockTag(List<int> accessPassword, List<int> lockPayload) {
    if (accessPassword.length != 4) {
      throw ArgumentError('Access password must be 4 bytes');
    }
    if (lockPayload.length != 3) {
      throw ArgumentError('Lock payload must be 3 bytes');
    }

    final parameters = <int>[
      ...accessPassword,
      ...lockPayload,
    ];

    return buildCommand(RfidConfig.cmdLockTag, parameters);
  }

  /// Build a Set RF Power command
  ///
  /// [powerDbm] - Power level in dBm (0-30)
  static List<int> buildSetRfPower(int powerDbm) {
    if (powerDbm < RfidConfig.minRfPower || powerDbm > RfidConfig.maxRfPower) {
      throw ArgumentError(
          'Power must be between ${RfidConfig.minRfPower} and ${RfidConfig.maxRfPower} dBm');
    }
    return buildCommand(RfidConfig.cmdSetRfPower, [powerDbm]);
  }

  /// Build a Get RF Power command
  static List<int> buildGetRfPower() {
    return buildCommand(RfidConfig.cmdGetRfPower);
  }

  /// Build a Get Firmware Version command
  ///
  /// Per the UHF module protocol docs:
  /// BB 00 03 00 01 00 04 7E
  /// Parameter 0x00 = hardware version info
  static List<int> buildGetFirmwareVersion() {
    return buildCommand(RfidConfig.cmdGetFirmwareVersion, [0x00]);
  }

  /// Parse a frame from raw bytes
  ///
  /// Returns null if the frame is invalid or incomplete
  static UhfFrame? parseFrame(List<int> bytes) {
    if (bytes.length < minFrameSize) {
      AppLogger.debug('Frame too short: ${bytes.length} bytes');
      return null;
    }

    // Verify header (accept both 0xBB and 0xBF for compatibility)
    if (bytes[0] != RfidConfig.frameHeader && bytes[0] != RfidConfig.frameHeaderAlt) {
      AppLogger.debug(
          'Invalid header: 0x${bytes[0].toRadixString(16).padLeft(2, '0').toUpperCase()}');
      return null;
    }

    // Verify end marker (some modules may omit it)
    final hasEndMarker = bytes[bytes.length - 1] == RfidConfig.frameEnd;
    if (!hasEndMarker) {
      AppLogger.debug(
          'No end marker (0x7E), got: 0x${bytes[bytes.length - 1].toRadixString(16).padLeft(2, '0').toUpperCase()} - attempting to parse anyway');
    }

    // Parse frame type
    final frameType = UhfFrameType.fromValue(bytes[1]);
    if (frameType == null) {
      AppLogger.debug('Unknown frame type: 0x${bytes[1].toRadixString(16).padLeft(2, '0').toUpperCase()}');
      return null;
    }

    // Parse command
    final command = bytes[2];

    // Parse payload length (big-endian)
    final payloadLength = (bytes[3] << 8) | bytes[4];

    // Verify frame length matches payload
    final expectedLength = minFrameSize + payloadLength;
    if (bytes.length != expectedLength) {
      AppLogger.debug('Frame length mismatch: expected $expectedLength, got ${bytes.length}');
      return null;
    }

    // Extract parameters
    final parameters = payloadLength > 0 ? bytes.sublist(5, 5 + payloadLength) : <int>[];

    // Validate checksum
    final checksumIndex = bytes.length - 2;
    final receivedChecksum = bytes[checksumIndex];
    final isChecksumValid = validateChecksum(bytes);

    if (!isChecksumValid) {
      AppLogger.warning(
          'Checksum mismatch: received 0x${receivedChecksum.toRadixString(16).padLeft(2, '0').toUpperCase()}');
    }

    return UhfFrame(
      type: frameType,
      command: command,
      parameters: parameters,
      isChecksumValid: isChecksumValid,
      rawBytes: List.unmodifiable(bytes),
    );
  }

  /// Validate the checksum of a frame
  ///
  /// Checksum is the sum of Type + Command + PL + Parameters, lowest byte only
  static bool validateChecksum(List<int> bytes) {
    if (bytes.length < minFrameSize) return false;

    // Calculate expected checksum
    var checksum = bytes[1]; // Type
    checksum += bytes[2]; // Command
    checksum += bytes[3]; // PL MSB
    checksum += bytes[4]; // PL LSB

    final payloadLength = (bytes[3] << 8) | bytes[4];
    for (var i = 0; i < payloadLength; i++) {
      checksum += bytes[5 + i];
    }

    final expectedChecksum = checksum & 0xFF;
    final receivedChecksum = bytes[bytes.length - 2];

    return expectedChecksum == receivedChecksum;
  }

  /// Find frame boundaries in a byte stream
  ///
  /// Returns the index of the first complete frame's end, or -1 if no complete frame found.
  /// This is useful for extracting frames from a continuous byte stream.
  static int findFrameEnd(List<int> bytes) {
    if (bytes.length < minFrameSize) return -1;

    // Look for header (accept both 0xBB and 0xBF)
    var headerIndex = bytes.indexOf(RfidConfig.frameHeader);
    if (headerIndex == -1) {
      headerIndex = bytes.indexOf(RfidConfig.frameHeaderAlt);
    }
    if (headerIndex == -1) return -1;
    if (bytes.length - headerIndex < minFrameSize) return -1;

    // Get payload length
    final plMsb = bytes[headerIndex + 3];
    final plLsb = bytes[headerIndex + 4];
    final payloadLength = (plMsb << 8) | plLsb;

    // Calculate expected frame end (with 7E end marker)
    final expectedEndWithMarker = headerIndex + minFrameSize + payloadLength - 1;

    // First try: look for proper frame with 7E end marker
    if (expectedEndWithMarker < bytes.length &&
        bytes[expectedEndWithMarker] == RfidConfig.frameEnd) {
      return expectedEndWithMarker;
    }

    // Second try: accept frame without 7E end marker if we have enough bytes
    // Some modules send frames without the end marker
    final expectedEndWithoutMarker = headerIndex + minFrameSize + payloadLength - 2;
    if (expectedEndWithoutMarker < bytes.length) {
      // Check if next byte after this frame is a new header (BB) or end of buffer
      final nextByteIndex = expectedEndWithoutMarker + 1;
      if (nextByteIndex >= bytes.length ||
          bytes[nextByteIndex] == RfidConfig.frameHeader ||
          bytes[nextByteIndex] == RfidConfig.frameHeaderAlt) {
        AppLogger.debug('Accepting frame without 7E end marker (${expectedEndWithoutMarker - headerIndex + 1} bytes)');
        return expectedEndWithoutMarker;
      }
    }

    return -1;
  }

  /// Try to find any frame ending with 0x7E, even without proper header
  /// This is useful for debugging when receiving corrupted or partial frames
  static int findAnyFrameEnd(List<int> bytes) {
    // Look for end marker anywhere in buffer
    final endIndex = bytes.indexOf(RfidConfig.frameEnd);
    if (endIndex == -1 || endIndex < minFrameSize - 1) return -1;
    return endIndex;
  }

  /// Debug helper to analyze raw bytes that might be a corrupted frame
  static String analyzeRawBytes(List<int> bytes) {
    final buffer = StringBuffer();
    buffer.writeln('Raw bytes analysis (${bytes.length} bytes):');
    buffer.writeln('  Hex: ${bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ')}');
    buffer.writeln('  ASCII: ${String.fromCharCodes(bytes.map((b) => (b >= 0x20 && b <= 0x7E) ? b : 0x2E))}');

    // Check for frame markers
    final hasHeader = bytes.contains(RfidConfig.frameHeader) || bytes.contains(RfidConfig.frameHeaderAlt);
    final hasEnd = bytes.contains(RfidConfig.frameEnd);
    buffer.writeln('  Has header (BB/BF): $hasHeader');
    buffer.writeln('  Has end marker (7E): $hasEnd');

    // Try to interpret as frame even without end marker
    if (hasHeader && bytes.length >= 5) {
      final headerIdx = bytes.indexOf(RfidConfig.frameHeader);
      if (headerIdx >= 0 && bytes.length > headerIdx + 4) {
        final type = bytes[headerIdx + 1];
        final cmd = bytes[headerIdx + 2];
        final plMsb = bytes[headerIdx + 3];
        final plLsb = bytes[headerIdx + 4];
        final payloadLen = (plMsb << 8) | plLsb;
        buffer.writeln('  Frame type: 0x${type.toRadixString(16).padLeft(2, '0').toUpperCase()} (${type == 0 ? "Command" : type == 1 ? "Response" : type == 2 ? "Notice" : "Unknown"})');
        buffer.writeln('  Command: 0x${cmd.toRadixString(16).padLeft(2, '0').toUpperCase()}');
        buffer.writeln('  Payload length: $payloadLen bytes');

        if (bytes.length > headerIdx + 5) {
          final remainingBytes = bytes.sublist(headerIdx + 5);
          buffer.writeln('  Remaining data: ${remainingBytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ')}');
        }
      }
    }

    // If ends with 7E, try to interpret as frame
    if (hasEnd) {
      final endIdx = bytes.lastIndexOf(RfidConfig.frameEnd);
      if (endIdx >= 6) {
        buffer.writeln('  Possible frame ending at index $endIdx');
      }
    }

    return buffer.toString();
  }

  /// Extract a complete frame from a byte buffer
  ///
  /// Returns a tuple of (frame bytes, remaining bytes) or null if no complete frame found
  static ({List<int> frame, List<int> remaining})? extractFrame(List<int> bytes) {
    final frameEnd = findFrameEnd(bytes);
    if (frameEnd == -1) return null;

    // Find header (accept both 0xBB and 0xBF)
    var headerIndex = bytes.indexOf(RfidConfig.frameHeader);
    if (headerIndex == -1) {
      headerIndex = bytes.indexOf(RfidConfig.frameHeaderAlt);
    }
    final frame = bytes.sublist(headerIndex, frameEnd + 1);
    final remaining = bytes.sublist(frameEnd + 1);

    return (frame: frame, remaining: remaining);
  }

  /// Parse tag poll data from a notice frame
  ///
  /// Notice frames for tag polls contain:
  /// - RSSI (1 byte)
  /// - PC (2 bytes)
  /// - EPC (length determined by PC word, typically 12 bytes for 96-bit)
  /// - CRC-16 (2 bytes, optional - M100 may include this)
  ///
  /// Note: Tag poll notices can come from either SinglePoll (0x22) or MultiplePoll (0x27)
  static TagPollData? parseTagPollData(UhfFrame frame) {
    if (!frame.isNotice ||
        (frame.command != RfidConfig.cmdMultiplePoll &&
         frame.command != RfidConfig.cmdSinglePoll)) {
      return null;
    }

    final params = frame.parameters;
    if (params.length < 3) {
      AppLogger.warning('Tag poll data too short: ${params.length} bytes');
      return null;
    }

    final rssi = params[0];
    final pc = (params[1] << 8) | params[2];

    // Extract EPC length from PC word (bits 15-11 encode length in 16-bit words)
    final epcLengthWords = (pc >> 11) & 0x1F;
    final epcLengthBytes = epcLengthWords * 2;

    // Get EPC bytes using the length from PC (ignores trailing CRC-16 if present)
    final availableEpcBytes = params.length - 3;
    final actualEpcLength = epcLengthBytes > 0 && epcLengthBytes <= availableEpcBytes
        ? epcLengthBytes
        : availableEpcBytes;

    final epcBytes = params.sublist(3, 3 + actualEpcLength);

    if (epcBytes.isEmpty) {
      AppLogger.warning('Empty EPC in tag poll data');
      return null;
    }

    return TagPollData(
      rssi: rssi,
      pc: pc,
      epcBytes: epcBytes,
    );
  }

  /// Parse response code and get error message if applicable
  static String getResponseMessage(UhfFrame frame) {
    if (!frame.isResponse) {
      return 'Not a response frame';
    }

    final responseCode = frame.responseCode;
    if (responseCode == null) {
      return 'No response code';
    }

    return RfidConfig.getErrorMessage(responseCode);
  }
}
