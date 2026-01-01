import 'dart:typed_data';

/// Represents a packet in the Niimbot printer protocol.
///
/// Packet format:
/// - Header: 0x55 0x55
/// - Type: 1 byte (command type)
/// - Length: 1 byte (data length)
/// - Data: variable length
/// - Checksum: 1 byte (XOR of type, length, and all data bytes)
/// - Footer: 0xAA 0xAA
class NiimbotPacket {
  final int type;
  final Uint8List data;

  NiimbotPacket(this.type, this.data);

  /// Parse a packet from raw bytes.
  /// Throws [FormatException] if the packet is invalid.
  factory NiimbotPacket.fromBytes(Uint8List bytes) {
    if (bytes.length < 7) {
      throw FormatException('Packet too short: ${bytes.length} bytes');
    }

    // Check header
    if (bytes[0] != 0x55 || bytes[1] != 0x55) {
      throw FormatException(
          'Invalid header: ${bytes[0].toRadixString(16)} ${bytes[1].toRadixString(16)}');
    }

    // Check footer
    if (bytes[bytes.length - 2] != 0xAA || bytes[bytes.length - 1] != 0xAA) {
      throw const FormatException('Invalid footer');
    }

    final type = bytes[2];
    final length = bytes[3];
    final data = Uint8List.fromList(bytes.sublist(4, 4 + length));

    // Verify checksum
    int checksum = type ^ length;
    for (final b in data) {
      checksum ^= b;
    }

    if (checksum != bytes[bytes.length - 3]) {
      throw FormatException(
          'Invalid checksum: expected ${bytes[bytes.length - 3].toRadixString(16)}, got ${checksum.toRadixString(16)}');
    }

    return NiimbotPacket(type, data);
  }

  /// Convert the packet to raw bytes for transmission.
  Uint8List toBytes() {
    // Calculate checksum: XOR of type, length, and all data bytes
    int checksum = type ^ data.length;
    for (final b in data) {
      checksum ^= b;
    }

    // Build packet: header + type + length + data + checksum + footer
    final result = Uint8List(7 + data.length);
    result[0] = 0x55;
    result[1] = 0x55;
    result[2] = type;
    result[3] = data.length;
    result.setRange(4, 4 + data.length, data);
    result[4 + data.length] = checksum;
    result[5 + data.length] = 0xAA;
    result[6 + data.length] = 0xAA;

    return result;
  }

  @override
  String toString() {
    final dataHex = data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');
    return '<NiimbotPacket type=0x${type.toRadixString(16)} data=[$dataHex]>';
  }
}
