import 'dart:async';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:image/image.dart' as img;

import '../../utils/app_logger.dart';
import 'niimbot_packet.dart';

/// Request codes for Niimbot printer commands.
class NiimbotRequestCode {
  static const int getInfo = 0x40;
  static const int getRfid = 0x1A;
  static const int heartbeat = 0xDC;
  static const int setLabelType = 0x23;
  static const int setLabelDensity = 0x21;
  static const int startPrint = 0x01;
  static const int endPrint = 0xF3;
  static const int startPagePrint = 0x03;
  static const int endPagePrint = 0xE3;
  static const int allowPrintClear = 0x20;
  static const int setDimension = 0x13;
  static const int setQuantity = 0x15;
  static const int getPrintStatus = 0xA3;
  static const int imageData = 0x85;
}

/// Info keys for querying printer information.
class NiimbotInfoKey {
  static const int density = 1;
  static const int printSpeed = 2;
  static const int labelType = 3;
  static const int languageType = 6;
  static const int autoShutdownTime = 7;
  static const int deviceType = 8;
  static const int softVersion = 9;
  static const int battery = 10;
  static const int deviceSerial = 11;
  static const int hardVersion = 12;
}

/// Service for communicating with Niimbot label printers via USB serial.
class NiimbotPrinter {
  SerialPort? _port;
  final List<int> _packetBuffer = [];

  /// Get a list of available serial ports.
  static List<String> getAvailablePorts() {
    return SerialPort.availablePorts;
  }

  /// Check if the printer is currently connected.
  bool get isConnected => _port?.isOpen ?? false;

  /// Connect to the printer at the specified port.
  Future<bool> connect(String portPath) async {
    try {
      AppLogger.info('Connecting to Niimbot printer at $portPath');

      _port = SerialPort(portPath);

      if (!_port!.openReadWrite()) {
        AppLogger.error(
            'Failed to open serial port: ${SerialPort.lastError?.message}');
        return false;
      }

      // Configure serial port: 115200 baud, 8N1
      // Must be done after opening the port
      final config = SerialPortConfig();
      config.baudRate = 115200;
      config.bits = 8;
      config.parity = SerialPortParity.none;
      config.stopBits = 1;
      config.setFlowControl(SerialPortFlowControl.none);
      _port!.config = config;

      // Log the actual config that was set
      final actualConfig = _port!.config;
      AppLogger.info(
          'Serial port config: baud=${actualConfig.baudRate}, bits=${actualConfig.bits}, parity=${actualConfig.parity}, stopBits=${actualConfig.stopBits}');

      _packetBuffer.clear();

      // Give the printer time to initialize after connection
      await Future.delayed(const Duration(milliseconds: 200));

      // Drain any stale data
      try {
        _port!.flush();
      } catch (_) {
        // Ignore flush errors
      }

      AppLogger.info('Connected to Niimbot printer');
      return true;
    } catch (e) {
      AppLogger.error('Error connecting to Niimbot printer', e);
      return false;
    }
  }

  /// Disconnect from the printer.
  void disconnect() {
    if (_port?.isOpen ?? false) {
      _port!.close();
      AppLogger.info('Disconnected from Niimbot printer');
    }
    _port = null;
    _packetBuffer.clear();
  }

  /// Print an image to the printer.
  ///
  /// [imageData] - PNG image data
  /// [density] - Print density (1-5, default 3)
  /// [labelWidthPx] - Label width in pixels (default 240 for ~30mm at 203dpi)
  Future<bool> printImage(Uint8List imageData,
      {int density = 3, int labelWidthPx = 240}) async {
    if (!isConnected) {
      AppLogger.error('Printer not connected');
      return false;
    }

    try {
      AppLogger.info('Starting print job');

      // Decode the image
      var image = img.decodeImage(imageData);
      if (image == null) {
        AppLogger.error('Failed to decode image');
        return false;
      }

      AppLogger.info('Original image size: ${image.width}x${image.height}');

      // Flatten transparency to white background before any processing
      // This ensures transparent pixels become white, not black
      image = _flattenTransparency(image);

      // Resize image to fit label width while maintaining aspect ratio
      if (image.width > labelWidthPx || image.height > labelWidthPx) {
        final scale = labelWidthPx / math.max(image.width, image.height);
        final newWidth = (image.width * scale).round();
        final newHeight = (image.height * scale).round();
        AppLogger.info('Resizing image to ${newWidth}x$newHeight');
        image = img.copyResize(image,
            width: newWidth, height: newHeight, interpolation: img.Interpolation.average);
      }

      AppLogger.info('Final image size: ${image.width}x${image.height}');

      // Set label density
      if (!await setLabelDensity(density)) {
        AppLogger.warning('Failed to set density, continuing anyway');
      }

      // Set label type (1 = gap label)
      if (!await setLabelType(1)) {
        AppLogger.warning('Failed to set label type, continuing anyway');
      }

      // Start print job
      if (!await startPrint()) {
        AppLogger.error('Failed to start print');
        return false;
      }

      // Start page
      if (!await startPagePrint()) {
        AppLogger.error('Failed to start page');
        return false;
      }

      // Set dimensions (height, width)
      if (!await setDimension(image.height, image.width)) {
        AppLogger.error('Failed to set dimensions');
        return false;
      }

      // Send image data row by row
      final encodedRows = _encodeImage(image);
      for (final packet in encodedRows) {
        _sendPacket(packet);
        // Small delay between rows to prevent buffer overflow
        await Future.delayed(const Duration(microseconds: 500));
      }

      // End page
      if (!await endPagePrint()) {
        AppLogger.error('Failed to end page');
        return false;
      }

      // Wait a bit for printing to complete
      await Future.delayed(const Duration(milliseconds: 300));

      // End print job with retry
      for (int i = 0; i < 10; i++) {
        if (await endPrint()) {
          AppLogger.info('Print job completed');
          return true;
        }
        await Future.delayed(const Duration(milliseconds: 100));
      }

      AppLogger.warning('Print may have completed but end_print timed out');
      return true;
    } catch (e) {
      AppLogger.error('Error during print', e);
      return false;
    }
  }

  /// Flatten transparency to white background.
  ///
  /// PNG images with transparent backgrounds need to be composited onto
  /// a white background, otherwise transparent pixels appear black.
  img.Image _flattenTransparency(img.Image image) {
    // Create a white background image
    final result = img.Image(width: image.width, height: image.height);
    img.fill(result, color: img.ColorRgba8(255, 255, 255, 255));

    // Composite the original image onto the white background
    img.compositeImage(result, image);

    return result;
  }

  /// Encode an image for the Niimbot protocol.
  ///
  /// The image is converted to 1-bit black and white, inverted,
  /// and sent row by row.
  List<NiimbotPacket> _encodeImage(img.Image image) {
    final packets = <NiimbotPacket>[];

    // Convert to grayscale
    final grayscale = img.grayscale(image);

    // Debug: Log some sample pixel values
    if (grayscale.height > 0 && grayscale.width > 0) {
      final samplePixel = grayscale.getPixel(0, 0);
      AppLogger.info(
          'Sample pixel at (0,0): luminance=${samplePixel.luminance}, r=${samplePixel.r}, g=${samplePixel.g}, b=${samplePixel.b}');
      // Check center pixel too
      final centerX = grayscale.width ~/ 2;
      final centerY = grayscale.height ~/ 2;
      final centerPixel = grayscale.getPixel(centerX, centerY);
      AppLogger.info(
          'Sample pixel at center ($centerX,$centerY): luminance=${centerPixel.luminance}');
    }

    for (int y = 0; y < grayscale.height; y++) {
      // Build row data as 1-bit per pixel
      final rowBytes = (grayscale.width + 7) ~/ 8;
      final lineData = Uint8List(rowBytes);

      for (int x = 0; x < grayscale.width; x++) {
        final pixel = grayscale.getPixel(x, y);
        // Get luminance - pixel.luminance returns normalized 0.0-1.0
        // In Python: ImageOps.invert() then convert to 1-bit
        // After inversion, originally BLACK pixels become WHITE (high value)
        // Those high-value pixels become bit=1
        // So we set bit=1 for pixels that are DARK in the original (luminance < 0.5)
        final luminance = pixel.luminance; // 0.0 to 1.0
        final isBlack = luminance < 0.5; // Dark pixels in original become 1

        if (isBlack) {
          final byteIndex = x ~/ 8;
          final bitIndex = 7 - (x % 8); // MSB first
          lineData[byteIndex] |= (1 << bitIndex);
        }
      }

      // Build header: row number (2 bytes big-endian) + counts (3 bytes) + flag (1 byte)
      // The counts appear to always be zero based on the Python implementation
      final header = Uint8List(6);
      header[0] = (y >> 8) & 0xFF;
      header[1] = y & 0xFF;
      header[2] = 0; // count1
      header[3] = 0; // count2
      header[4] = 0; // count3
      header[5] = 1; // flag

      // Combine header and line data
      final packetData = Uint8List(header.length + lineData.length);
      packetData.setRange(0, header.length, header);
      packetData.setRange(header.length, packetData.length, lineData);

      // Debug: Log first few rows
      if (y < 3) {
        final lineHex =
            lineData.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');
        AppLogger.info('Row $y line data: $lineHex');
      }

      packets.add(NiimbotPacket(NiimbotRequestCode.imageData, packetData));
    }

    return packets;
  }

  /// Send a packet and wait for response.
  Future<NiimbotPacket?> _transceive(int requestCode, Uint8List data,
      {int responseOffset = 1}) async {
    final expectedResponse = responseOffset + requestCode;
    final packet = NiimbotPacket(requestCode, data);

    _sendPacket(packet);

    // Wait for response with timeout (similar to Python's 0.5s timeout per read)
    // Total timeout: 6 attempts * 100ms = 600ms
    for (int attempt = 0; attempt < 6; attempt++) {
      // Wait a bit before checking for response - this is key!
      // The printer needs time to process and respond
      await Future.delayed(const Duration(milliseconds: 100));

      final packets = await _receivePacketsWithWait();
      for (final p in packets) {
        if (p.type == 219) {
          // Error response
          throw Exception('Printer returned error');
        } else if (p.type == 0) {
          // Not implemented
          throw Exception('Command not implemented by printer');
        } else if (p.type == expectedResponse) {
          return p;
        }
      }
    }

    return null;
  }

  /// Receive packets with a small wait for data to arrive.
  Future<List<NiimbotPacket>> _receivePacketsWithWait() async {
    final packets = <NiimbotPacket>[];

    if (_port == null || !_port!.isOpen) {
      return packets;
    }

    // Poll for data with waits - total ~500ms like Python's timeout
    for (int i = 0; i < 10; i++) {
      final bytesAvailable = _port!.bytesAvailable;
      if (i == 0 || bytesAvailable > 0) {
        AppLogger.debug('Poll $i: bytesAvailable=$bytesAvailable');
      }
      if (bytesAvailable > 0) {
        final data = _port!.read(math.min(bytesAvailable, 1024));
        AppLogger.debug('Read ${data.length} bytes from serial port');
        _packetBuffer.addAll(data);
        // Keep reading if more data might be coming
        await Future.delayed(const Duration(milliseconds: 10));
        continue;
      }
      // No data yet, wait a bit
      await Future.delayed(const Duration(milliseconds: 50));
    }

    // Parse complete packets from buffer
    while (_packetBuffer.length > 4) {
      // Check for header
      if (_packetBuffer[0] != 0x55 || _packetBuffer[1] != 0x55) {
        // Skip invalid byte
        _packetBuffer.removeAt(0);
        continue;
      }

      final packetLength = _packetBuffer[3] + 7;
      if (_packetBuffer.length >= packetLength) {
        try {
          final packetBytes = Uint8List.fromList(
              _packetBuffer.sublist(0, packetLength));
          final packet = NiimbotPacket.fromBytes(packetBytes);
          _logBuffer('recv', packetBytes);
          packets.add(packet);
        } catch (e) {
          AppLogger.warning('Failed to parse packet: $e');
        }
        _packetBuffer.removeRange(0, packetLength);
      } else {
        break;
      }
    }

    return packets;
  }

  /// Send a packet to the printer.
  void _sendPacket(NiimbotPacket packet) {
    if (_port == null || !_port!.isOpen) {
      throw Exception('Port not open');
    }

    final bytes = packet.toBytes();
    _logBuffer('send', bytes);
    final written = _port!.write(bytes);
    AppLogger.debug('Wrote $written bytes to serial port');

    // Wait for write to complete
    try {
      _port!.drain();
    } catch (_) {
      // Ignore drain errors
    }
  }

  /// Log buffer contents for debugging.
  void _logBuffer(String prefix, Uint8List buffer) {
    final hex = buffer.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');
    AppLogger.debug('$prefix: $hex');
  }

  // === Printer Commands ===

  /// Set the print density (1-5).
  Future<bool> setLabelDensity(int density) async {
    assert(density >= 1 && density <= 5);
    final packet = await _transceive(
      NiimbotRequestCode.setLabelDensity,
      Uint8List.fromList([density]),
      responseOffset: 16,
    );
    if (packet == null) {
      AppLogger.warning('No response to setLabelDensity');
      return true; // Continue anyway like the Python implementation
    }
    return packet.data.isNotEmpty && packet.data[0] != 0;
  }

  /// Set the label type (1 = gap, 2 = black mark, 3 = continuous).
  Future<bool> setLabelType(int type) async {
    assert(type >= 1 && type <= 3);
    final packet = await _transceive(
      NiimbotRequestCode.setLabelType,
      Uint8List.fromList([type]),
      responseOffset: 16,
    );
    if (packet == null) return false;
    return packet.data.isNotEmpty && packet.data[0] != 0;
  }

  /// Start a print job.
  Future<bool> startPrint() async {
    final packet = await _transceive(
      NiimbotRequestCode.startPrint,
      Uint8List.fromList([1]),
    );
    if (packet == null) return false;
    return packet.data.isNotEmpty && packet.data[0] != 0;
  }

  /// End a print job.
  Future<bool> endPrint() async {
    final packet = await _transceive(
      NiimbotRequestCode.endPrint,
      Uint8List.fromList([1]),
    );
    if (packet == null) return false;
    return packet.data.isNotEmpty && packet.data[0] != 0;
  }

  /// Start a page within a print job.
  Future<bool> startPagePrint() async {
    final packet = await _transceive(
      NiimbotRequestCode.startPagePrint,
      Uint8List.fromList([1]),
    );
    if (packet == null) return false;
    return packet.data.isNotEmpty && packet.data[0] != 0;
  }

  /// End a page within a print job.
  Future<bool> endPagePrint() async {
    final packet = await _transceive(
      NiimbotRequestCode.endPagePrint,
      Uint8List.fromList([1]),
    );
    if (packet == null) return false;
    return packet.data.isNotEmpty && packet.data[0] != 0;
  }

  /// Set the label dimensions.
  Future<bool> setDimension(int height, int width) async {
    final data = Uint8List(4);
    // Big-endian encoding
    data[0] = (height >> 8) & 0xFF;
    data[1] = height & 0xFF;
    data[2] = (width >> 8) & 0xFF;
    data[3] = width & 0xFF;

    final packet = await _transceive(
      NiimbotRequestCode.setDimension,
      data,
    );
    if (packet == null) return false;
    return packet.data.isNotEmpty && packet.data[0] != 0;
  }

  /// Get printer information.
  Future<int?> getInfo(int key) async {
    final packet = await _transceive(
      NiimbotRequestCode.getInfo,
      Uint8List.fromList([key]),
      responseOffset: key,
    );
    if (packet == null || packet.data.isEmpty) return null;

    // Convert data to integer (big-endian)
    int value = 0;
    for (final b in packet.data) {
      value = (value << 8) | b;
    }
    return value;
  }

  /// Get battery level.
  Future<int?> getBatteryLevel() async {
    return getInfo(NiimbotInfoKey.battery);
  }

  /// Send a heartbeat to check printer status.
  Future<Map<String, int?>?> heartbeat() async {
    final packet = await _transceive(
      NiimbotRequestCode.heartbeat,
      Uint8List.fromList([1]),
    );
    if (packet == null) return null;

    // Parse heartbeat response based on data length
    int? closingState;
    int? powerLevel;
    int? paperState;
    int? rfidReadState;

    switch (packet.data.length) {
      case 20:
        paperState = packet.data[18];
        rfidReadState = packet.data[19];
        break;
      case 13:
        closingState = packet.data[9];
        powerLevel = packet.data[10];
        paperState = packet.data[11];
        rfidReadState = packet.data[12];
        break;
      case 19:
        closingState = packet.data[15];
        powerLevel = packet.data[16];
        paperState = packet.data[17];
        rfidReadState = packet.data[18];
        break;
      case 10:
        closingState = packet.data[8];
        powerLevel = packet.data[9];
        rfidReadState = packet.data[8];
        break;
      case 9:
        closingState = packet.data[8];
        break;
    }

    return {
      'closingState': closingState,
      'powerLevel': powerLevel,
      'paperState': paperState,
      'rfidReadState': rfidReadState,
    };
  }
}
