/// Configuration constants for UHF RFID module communication
class RfidConfig {
  RfidConfig._(); // Private constructor to prevent instantiation

  // ============================================================================
  // EPC Identifier Configuration
  // ============================================================================

  /// Saturday Vinyl EPC prefix bytes: "SV" in ASCII = 0x53, 0x56
  static const List<int> epcPrefixBytes = [0x53, 0x56];

  /// Saturday Vinyl EPC prefix as hex string
  static const String epcPrefixHex = '5356';

  /// Total EPC length in bytes (96 bits = 12 bytes)
  static const int epcLengthBytes = 12;

  /// Total EPC length in hex characters (12 bytes = 24 hex chars)
  static const int epcLengthHex = 24;

  /// Random portion length in bytes (EPC length - prefix length)
  static const int epcRandomLengthBytes = 10;

  // ============================================================================
  // Serial Communication Defaults
  // ============================================================================

  /// Default baud rate for UHF module communication
  /// Note: This module uses 115200 baud (confirmed from working C code)
  static const int defaultBaudRate = 115200;

  /// Available baud rates for configuration
  static const List<int> availableBaudRates = [
    9600,
    19200,
    38400,
    57600,
    115200,
  ];

  /// Serial port configuration: data bits
  static const int dataBits = 8;

  /// Serial port configuration: stop bits
  static const int stopBits = 1;

  /// Serial port configuration: parity (0 = none)
  static const int parity = 0;

  // ============================================================================
  // RF Power Configuration
  // ============================================================================

  /// Default RF power level in dBm
  static const int defaultRfPower = 20;

  /// Minimum RF power level in dBm
  static const int minRfPower = 0;

  /// Maximum RF power level in dBm
  static const int maxRfPower = 30;

  // ============================================================================
  // Timing Configuration
  // ============================================================================

  /// Polling interval in milliseconds (how often to poll for tags)
  static const int pollingIntervalMs = 150;

  /// Timeout for no tags detected before stopping bulk write (milliseconds)
  static const int noTagTimeoutMs = 2000;

  /// Delay after enabling module via DTR before sending commands (milliseconds)
  /// Note: UHF modules need time to initialize RF circuitry after power-on
  static const int moduleEnableDelayMs = 300;

  /// Command response timeout (milliseconds)
  static const int commandTimeoutMs = 1000;

  /// Write verification delay (milliseconds)
  static const int writeVerifyDelayMs = 50;

  // ============================================================================
  // UHF Module Frame Format
  // ============================================================================

  /// Frame header byte (command)
  static const int frameHeader = 0xBB;

  /// Alternative frame header byte (some modules use 0xBF for responses)
  static const int frameHeaderAlt = 0xBF;

  /// Frame end byte
  static const int frameEnd = 0x7E;

  /// Frame type: Command (host to module)
  static const int frameTypeCommand = 0x00;

  /// Frame type: Response (module to host)
  static const int frameTypeResponse = 0x01;

  /// Frame type: Notice (async notification from module)
  static const int frameTypeNotice = 0x02;

  // ============================================================================
  // UHF Module Commands
  // ============================================================================

  /// Get hardware/firmware version command
  static const int cmdGetFirmwareVersion = 0x03;

  /// Single inventory/poll command
  static const int cmdSinglePoll = 0x22;

  /// Multiple inventory/poll command (continuous)
  static const int cmdMultiplePoll = 0x27;

  /// Stop multiple polling command
  static const int cmdStopMultiplePoll = 0x28;

  /// Read tag data command
  static const int cmdReadData = 0x39;

  /// Write EPC data command
  static const int cmdWriteEpc = 0x49;

  /// Lock tag command
  static const int cmdLockTag = 0x82;

  /// Set RF power command
  static const int cmdSetRfPower = 0xB6;

  /// Get RF power command
  static const int cmdGetRfPower = 0xB7;

  // ============================================================================
  // UHF Module Response Codes
  // ============================================================================

  /// Response: Success
  static const int respSuccess = 0x10;

  /// Response: Invalid command
  static const int respInvalidCommand = 0x11;

  /// Response: Invalid parameter
  static const int respInvalidParameter = 0x12;

  /// Response: Memory overrun
  static const int respMemoryOverrun = 0x13;

  /// Response: Memory locked
  static const int respMemoryLocked = 0x14;

  /// Response: Tag not found
  static const int respTagNotFound = 0x15;

  /// Response: Read failed
  static const int respReadFailed = 0x16;

  /// Response: Write failed
  static const int respWriteFailed = 0x17;

  /// Response: Lock failed
  static const int respLockFailed = 0x18;

  /// Get human-readable error message for response code
  static String getErrorMessage(int code) {
    switch (code) {
      case respSuccess:
        return 'Success';
      case respInvalidCommand:
        return 'Invalid command';
      case respInvalidParameter:
        return 'Invalid parameter';
      case respMemoryOverrun:
        return 'Memory overrun';
      case respMemoryLocked:
        return 'Memory is locked';
      case respTagNotFound:
        return 'Tag not found';
      case respReadFailed:
        return 'Read operation failed';
      case respWriteFailed:
        return 'Write operation failed';
      case respLockFailed:
        return 'Lock operation failed';
      default:
        return 'Unknown error (0x${code.toRadixString(16).padLeft(2, '0').toUpperCase()})';
    }
  }

  // ============================================================================
  // Memory Bank Constants
  // ============================================================================

  /// Memory bank: Reserved (kill/access passwords)
  static const int memBankReserved = 0x00;

  /// Memory bank: EPC
  static const int memBankEpc = 0x01;

  /// Memory bank: TID (factory read-only)
  static const int memBankTid = 0x02;

  /// Memory bank: User
  static const int memBankUser = 0x03;

  /// EPC write start address (word address, skipping PC bytes)
  static const int epcWriteStartAddr = 0x02;

  /// EPC write word count (6 words = 12 bytes = 96 bits)
  static const int epcWriteWordCount = 0x06;

  // ============================================================================
  // Access Password
  // ============================================================================

  /// Default access password (unlocked tags)
  static const List<int> defaultAccessPassword = [0x00, 0x00, 0x00, 0x00];
}
