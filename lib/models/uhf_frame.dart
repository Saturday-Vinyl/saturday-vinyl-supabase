import 'package:equatable/equatable.dart';
import 'package:saturday_app/config/rfid_config.dart';

/// Frame type for UHF module communication
enum UhfFrameType {
  /// Command frame (host → module)
  command(0x00),

  /// Response frame (module → host)
  response(0x01),

  /// Notice frame (async notification from module)
  notice(0x02);

  const UhfFrameType(this.value);
  final int value;

  static UhfFrameType? fromValue(int value) {
    for (final type in values) {
      if (type.value == value) return type;
    }
    return null;
  }
}

/// Represents a parsed UHF module frame
///
/// Frame format:
/// [Header 0xBB] [Type] [Command] [PL MSB] [PL LSB] [Parameters...] [Checksum] [End 0x7E]
class UhfFrame extends Equatable {
  /// Frame type (command, response, notice)
  final UhfFrameType type;

  /// Command/response code
  final int command;

  /// Parameter bytes (variable length)
  final List<int> parameters;

  /// Whether the frame checksum was valid when parsed
  final bool isChecksumValid;

  /// Raw bytes of the frame (for debugging)
  final List<int>? rawBytes;

  const UhfFrame({
    required this.type,
    required this.command,
    required this.parameters,
    this.isChecksumValid = true,
    this.rawBytes,
  });

  /// Check if this is a response frame
  bool get isResponse => type == UhfFrameType.response;

  /// Check if this is a notice frame (async notification)
  bool get isNotice => type == UhfFrameType.notice;

  /// Check if this is a command frame
  bool get isCommand => type == UhfFrameType.command;

  /// Check if this is an error response frame (command = 0xFF)
  bool get isErrorFrame => isResponse && command == 0xFF;

  /// Check if this frame indicates success (for response frames)
  ///
  /// Success detection depends on the command type:
  /// - WriteEpc (0x49), LockTag (0x82): Success if response echoes the command code
  ///   (not 0xFF error frame). These commands return tag data, not a status code.
  /// - Other commands: Success if first param is 0x00 (respSuccess)
  ///
  /// Note: For error frames, command=0xFF and params contain error details
  bool get isSuccess {
    if (!isResponse || isErrorFrame) return false;

    // Commands that return tag data on success (no status code in params)
    // For these, receiving response with same command code = success
    if (command == RfidConfig.cmdWriteEpc || command == RfidConfig.cmdLockTag) {
      return true; // Not an error frame, so it's success
    }

    // For other commands, check the status code in first parameter
    return parameters.isNotEmpty && parameters.first == RfidConfig.respSuccess;
  }

  /// Get the response/error code (first parameter byte for response frames)
  ///
  /// Note: For WriteEpc and LockTag commands, this returns null because their
  /// success responses contain tag data, not a status code. Error responses
  /// (command=0xFF) still have error codes in parameters.
  int? get responseCode {
    if (!isResponse || parameters.isEmpty) return null;

    // For error frames, first param is the error code
    if (isErrorFrame) return parameters.first;

    // WriteEpc and LockTag return tag data on success, not a status code
    if (command == RfidConfig.cmdWriteEpc || command == RfidConfig.cmdLockTag) {
      return null; // No status code for these commands on success
    }

    return parameters.first;
  }

  /// Get parameters excluding the response code (for response frames)
  List<int> get dataParameters => isResponse && parameters.length > 1 ? parameters.sublist(1) : parameters;

  /// Get payload length (number of parameter bytes)
  int get payloadLength => parameters.length;

  /// Get the expected checksum for this frame
  int get expectedChecksum {
    var sum = type.value + command;
    sum += (parameters.length >> 8) & 0xFF; // PL MSB
    sum += parameters.length & 0xFF; // PL LSB
    for (final param in parameters) {
      sum += param;
    }
    return sum & 0xFF; // Take lowest byte
  }

  /// Format frame as hex string for debugging
  String toHexString() {
    if (rawBytes != null) {
      return rawBytes!.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
    }
    // Reconstruct frame bytes
    final bytes = <int>[
      RfidConfig.frameHeader,
      type.value,
      command,
      (parameters.length >> 8) & 0xFF,
      parameters.length & 0xFF,
      ...parameters,
      expectedChecksum,
      RfidConfig.frameEnd,
    ];
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
  }

  /// Get command name for debugging
  String get commandName {
    switch (command) {
      case RfidConfig.cmdGetFirmwareVersion:
        return 'GetFirmwareVersion';
      case RfidConfig.cmdSinglePoll:
        return 'SinglePoll';
      case RfidConfig.cmdMultiplePoll:
        return 'MultiplePoll';
      case RfidConfig.cmdStopMultiplePoll:
        return 'StopMultiplePoll';
      case RfidConfig.cmdReadData:
        return 'ReadData';
      case RfidConfig.cmdWriteEpc:
        return 'WriteEpc';
      case RfidConfig.cmdLockTag:
        return 'LockTag';
      case RfidConfig.cmdSetRfPower:
        return 'SetRfPower';
      case RfidConfig.cmdGetRfPower:
        return 'GetRfPower';
      default:
        return '0x${command.toRadixString(16).padLeft(2, '0').toUpperCase()}';
    }
  }

  @override
  List<Object?> get props => [type, command, parameters, isChecksumValid];

  @override
  String toString() {
    return 'UhfFrame(type: ${type.name}, cmd: $commandName, params: ${parameters.length} bytes, valid: $isChecksumValid)';
  }
}

/// Result of parsing tag poll data from a notice frame
class TagPollData extends Equatable {
  /// Received Signal Strength Indicator
  final int rssi;

  /// Protocol Control bits
  final int pc;

  /// EPC identifier bytes
  final List<int> epcBytes;

  const TagPollData({
    required this.rssi,
    required this.pc,
    required this.epcBytes,
  });

  /// Get EPC as hex string (uppercase, no separator)
  String get epcHex => epcBytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join();

  /// Get EPC formatted with dashes for readability
  String get formattedEpc {
    final hex = epcHex;
    if (hex.length != 24) return hex;
    return '${hex.substring(0, 4)}-${hex.substring(4, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 24)}';
  }

  /// Check if this is a Saturday Vinyl tag
  ///
  /// A valid Saturday tag must:
  /// 1. Start with "SV" / 0x5356 prefix
  /// 2. Be exactly 96-bit / 12 bytes / 24 hex chars
  bool get isSaturdayTag =>
      epcBytes.length == RfidConfig.epcLengthBytes &&
      epcHex.toUpperCase().startsWith(RfidConfig.epcPrefixHex.toUpperCase());

  /// EPC length in bytes
  int get epcLength => epcBytes.length;

  @override
  List<Object?> get props => [rssi, pc, epcBytes];

  @override
  String toString() => 'TagPollData(rssi: $rssi, epc: $formattedEpc)';
}
