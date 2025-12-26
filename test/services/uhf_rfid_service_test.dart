import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:saturday_app/config/rfid_config.dart';
import 'package:saturday_app/models/serial_connection_state.dart';
import 'package:saturday_app/services/serial_port_service.dart';
import 'package:saturday_app/services/uhf_rfid_service.dart';

@GenerateMocks([SerialPortService])
import 'uhf_rfid_service_test.mocks.dart';

void main() {
  late MockSerialPortService mockSerialPort;
  late UhfRfidService service;
  late StreamController<List<int>> dataController;
  late StreamController<SerialConnectionState> stateController;

  setUp(() {
    mockSerialPort = MockSerialPortService();
    dataController = StreamController<List<int>>.broadcast();
    stateController = StreamController<SerialConnectionState>.broadcast();

    // Set up default mock behavior
    when(mockSerialPort.isConnected).thenReturn(false);
    when(mockSerialPort.isModuleEnabled).thenReturn(false);
    when(mockSerialPort.dataStream).thenAnswer((_) => dataController.stream);
    when(mockSerialPort.stateStream).thenAnswer((_) => stateController.stream);
    when(mockSerialPort.state).thenReturn(SerialConnectionState.initial);
    when(mockSerialPort.disconnect()).thenAnswer((_) async {});

    service = UhfRfidService(mockSerialPort);
  });

  tearDown(() async {
    await service.disconnect();
    service.dispose();
    await dataController.close();
    await stateController.close();
  });

  /// Helper to send a response after a short delay
  void sendResponseAfterDelay(List<int> response) {
    Future.delayed(const Duration(milliseconds: 10), () {
      if (!dataController.isClosed) {
        dataController.add(response);
      }
    });
  }

  /// Build a valid response frame
  List<int> buildResponseFrame(int command, int responseCode,
      [List<int> data = const []]) {
    final params = [responseCode, ...data];
    final frame = [
      0xBB, // Header
      0x01, // Response type
      command,
      (params.length >> 8) & 0xFF, // PL MSB
      params.length & 0xFF, // PL LSB
      ...params,
      0x00, // Checksum placeholder
      0x7E, // End
    ];

    // Calculate checksum
    var checksum = 0x01 + command;
    checksum += (params.length >> 8) & 0xFF;
    checksum += params.length & 0xFF;
    for (final p in params) {
      checksum += p;
    }
    frame[frame.length - 2] = checksum & 0xFF;

    return frame;
  }

  /// Helper to set up a connected service
  Future<void> setupConnectedService() async {
    when(mockSerialPort.connect(any, baudRate: anyNamed('baudRate')))
        .thenAnswer((_) async => true);
    when(mockSerialPort.isConnected).thenReturn(true);
    when(mockSerialPort.write(any)).thenAnswer((_) async => true);
    await service.connect('/dev/ttyUSB0');
  }

  group('UhfRfidService', () {
    group('connection management', () {
      test('connect calls serial port service', () async {
        when(mockSerialPort.connect('/dev/ttyUSB0', baudRate: 115200))
            .thenAnswer((_) async => true);
        when(mockSerialPort.isConnected).thenReturn(true);

        final result = await service.connect('/dev/ttyUSB0');

        expect(result, true);
        verify(mockSerialPort.connect('/dev/ttyUSB0', baudRate: 115200))
            .called(1);
      });

      test('connect with custom baud rate', () async {
        when(mockSerialPort.connect('/dev/ttyUSB0', baudRate: 9600))
            .thenAnswer((_) async => true);
        when(mockSerialPort.isConnected).thenReturn(true);

        final result = await service.connect('/dev/ttyUSB0', baudRate: 9600);

        expect(result, true);
        verify(mockSerialPort.connect('/dev/ttyUSB0', baudRate: 9600)).called(1);
      });

      test('connect returns false on failure', () async {
        when(mockSerialPort.connect(any, baudRate: anyNamed('baudRate')))
            .thenAnswer((_) async => false);

        final result = await service.connect('/dev/ttyUSB0');

        expect(result, false);
      });

      test('disconnect calls serial port disconnect', () async {
        await service.disconnect();

        verify(mockSerialPort.disconnect()).called(1);
      });

      test('isConnected delegates to serial port', () {
        when(mockSerialPort.isConnected).thenReturn(true);
        expect(service.isConnected, true);

        when(mockSerialPort.isConnected).thenReturn(false);
        expect(service.isConnected, false);
      });

      test('isModuleEnabled delegates to serial port', () {
        when(mockSerialPort.isModuleEnabled).thenReturn(true);
        expect(service.isModuleEnabled, true);

        when(mockSerialPort.isModuleEnabled).thenReturn(false);
        expect(service.isModuleEnabled, false);
      });

      test('connectionStateStream returns serial port stream', () {
        expect(service.connectionStateStream, stateController.stream);
      });
    });

    group('configuration', () {
      test('setRfPower fails when not connected', () async {
        when(mockSerialPort.isConnected).thenReturn(false);

        final result = await service.setRfPower(20);

        expect(result, false);
        verifyNever(mockSerialPort.write(any));
      });

      test('setRfPower rejects invalid power levels', () async {
        when(mockSerialPort.isConnected).thenReturn(true);

        expect(await service.setRfPower(-1), false);
        expect(await service.setRfPower(31), false);

        verifyNever(mockSerialPort.write(any));
      });

      test('setRfPower sends correct command and returns true on success',
          () async {
        await setupConnectedService();
        when(mockSerialPort.write(any)).thenAnswer((_) async {
          // Send response after a short delay (simulates async serial response)
          sendResponseAfterDelay(
            buildResponseFrame(RfidConfig.cmdSetRfPower, RfidConfig.respSuccess),
          );
          return true;
        });

        final result = await service.setRfPower(20);

        expect(result, true);
        verify(mockSerialPort.write(argThat(contains(RfidConfig.cmdSetRfPower))))
            .called(1);
      });

      test('getRfPower fails when not connected', () async {
        when(mockSerialPort.isConnected).thenReturn(false);

        final result = await service.getRfPower();

        expect(result, null);
      });

      test('getRfPower returns power level on success', () async {
        await setupConnectedService();
        when(mockSerialPort.write(any)).thenAnswer((_) async {
          // Response includes success code + power level
          sendResponseAfterDelay(
            buildResponseFrame(
                RfidConfig.cmdGetRfPower, RfidConfig.respSuccess, [20]),
          );
          return true;
        });

        final result = await service.getRfPower();

        expect(result, 20);
      });

      test('setAccessPassword validates length', () {
        expect(
          () => service.setAccessPassword([0x00, 0x00]),
          throwsArgumentError,
        );
      });

      test('setAccessPassword stores password', () {
        service.setAccessPassword([0x12, 0x34, 0x56, 0x78]);
        expect(service.accessPassword, [0x12, 0x34, 0x56, 0x78]);
      });
    });

    group('tag polling', () {
      test('startPolling fails when not connected', () async {
        when(mockSerialPort.isConnected).thenReturn(false);

        final result = await service.startPolling();

        expect(result, false);
        expect(service.isPolling, false);
      });

      test('startPolling sends multi poll command', () async {
        await setupConnectedService();

        final result = await service.startPolling();

        expect(result, true);
        expect(service.isPolling, true);
        verify(mockSerialPort.write(
          argThat(contains(RfidConfig.cmdMultiplePoll)),
        )).called(1);
      });

      test('startPolling returns true if already polling', () async {
        await setupConnectedService();

        await service.startPolling();
        final result = await service.startPolling();

        expect(result, true);
        // Should only send command once (plus connect call)
        verify(mockSerialPort.write(argThat(contains(RfidConfig.cmdMultiplePoll)))).called(1);
      });

      test('stopPolling sends stop command', () async {
        await setupConnectedService();
        when(mockSerialPort.write(any)).thenAnswer((invocation) async {
          final data = invocation.positionalArguments[0] as List<int>;
          // Check if this is a stop command
          if (data.contains(RfidConfig.cmdStopMultiplePoll)) {
            sendResponseAfterDelay(
              buildResponseFrame(
                  RfidConfig.cmdStopMultiplePoll, RfidConfig.respSuccess),
            );
          }
          return true;
        });

        await service.startPolling();
        final result = await service.stopPolling();

        expect(result, true);
        expect(service.isPolling, false);
      });

      test('pollStream emits tag results from notice frames', () async {
        await setupConnectedService();

        // Start collecting poll results
        final results = <dynamic>[];
        final subscription = service.pollStream.listen(results.add);

        await service.startPolling();

        // Simulate tag notice frame
        dataController.add(_buildTagNoticeFrame([
          0x53,
          0x56,
          0x01,
          0x02,
          0x03,
          0x04,
          0x05,
          0x06,
          0x07,
          0x08,
          0x09,
          0x0A
        ]));

        // Allow stream to process
        await Future.delayed(const Duration(milliseconds: 50));

        expect(results.length, 1);
        expect(results.first.epcHex, '53560102030405060708090A');
        expect(results.first.isSaturdayTag, true);

        await subscription.cancel();
      });

      test('singlePoll returns empty list when not connected', () async {
        when(mockSerialPort.isConnected).thenReturn(false);

        final result = await service.singlePoll();

        expect(result, isEmpty);
      });
    });

    group('tag operations', () {
      test('writeEpc fails when not connected', () async {
        when(mockSerialPort.isConnected).thenReturn(false);

        final result = await service.writeEpc(List.filled(12, 0x00));

        expect(result.success, false);
        expect(result.errorMessage, contains('Not connected'));
      });

      test('writeEpc validates EPC length', () async {
        when(mockSerialPort.isConnected).thenReturn(true);

        final result = await service.writeEpc([0x53, 0x56]); // Too short

        expect(result.success, false);
        expect(result.errorMessage, contains('12 bytes'));
      });

      test('writeEpc sends correct command and returns success', () async {
        await setupConnectedService();
        when(mockSerialPort.write(any)).thenAnswer((_) async {
          sendResponseAfterDelay(
            buildResponseFrame(RfidConfig.cmdWriteEpc, RfidConfig.respSuccess),
          );
          return true;
        });

        final epc = [
          0x53,
          0x56,
          0x01,
          0x02,
          0x03,
          0x04,
          0x05,
          0x06,
          0x07,
          0x08,
          0x09,
          0x0A
        ];
        final result = await service.writeEpc(epc);

        expect(result.success, true);
        expect(result.writtenEpc, epc);
        verify(mockSerialPort.write(argThat(contains(RfidConfig.cmdWriteEpc))))
            .called(1);
      });

      test('writeEpc returns failure on error response', () async {
        await setupConnectedService();
        when(mockSerialPort.write(any)).thenAnswer((_) async {
          sendResponseAfterDelay(
            buildResponseFrame(
                RfidConfig.cmdWriteEpc, RfidConfig.respWriteFailed),
          );
          return true;
        });

        final result = await service.writeEpc(List.filled(12, 0x00));

        expect(result.success, false);
        expect(result.errorCode, RfidConfig.respWriteFailed);
      });

      test('lockTag fails when not connected', () async {
        when(mockSerialPort.isConnected).thenReturn(false);

        final result = await service.lockTag([0x00, 0x00, 0x00, 0x00]);

        expect(result.success, false);
        expect(result.errorMessage, contains('Not connected'));
      });

      test('lockTag validates password length', () async {
        when(mockSerialPort.isConnected).thenReturn(true);

        final result = await service.lockTag([0x00, 0x00]); // Too short

        expect(result.success, false);
        expect(result.errorMessage, contains('4 bytes'));
      });

      test('lockTag sends correct command and returns success', () async {
        await setupConnectedService();
        when(mockSerialPort.write(any)).thenAnswer((_) async {
          sendResponseAfterDelay(
            buildResponseFrame(RfidConfig.cmdLockTag, RfidConfig.respSuccess),
          );
          return true;
        });

        final result = await service.lockTag([0x12, 0x34, 0x56, 0x78]);

        expect(result.success, true);
        verify(mockSerialPort.write(argThat(contains(RfidConfig.cmdLockTag))))
            .called(1);
      });
    });

    group('frame buffer handling', () {
      test('handles partial frame reads', () async {
        await setupConnectedService();

        final results = <dynamic>[];
        final subscription = service.pollStream.listen(results.add);

        await service.startPolling();

        // Build complete frame
        final fullFrame = _buildTagNoticeFrame([
          0x53,
          0x56,
          0x01,
          0x02,
          0x03,
          0x04,
          0x05,
          0x06,
          0x07,
          0x08,
          0x09,
          0x0A
        ]);

        // Send first half
        dataController.add(fullFrame.sublist(0, 10));
        await Future.delayed(const Duration(milliseconds: 10));

        // No result yet
        expect(results, isEmpty);

        // Send second half
        dataController.add(fullFrame.sublist(10));
        await Future.delayed(const Duration(milliseconds: 50));

        // Now we should have a result
        expect(results.length, 1);

        await subscription.cancel();
      });

      test('handles multiple frames in single read', () async {
        await setupConnectedService();

        final results = <dynamic>[];
        final subscription = service.pollStream.listen(results.add);

        await service.startPolling();

        // Create two complete frames
        final frame1 = _buildTagNoticeFrame([
          0x53,
          0x56,
          0x01,
          0x02,
          0x03,
          0x04,
          0x05,
          0x06,
          0x07,
          0x08,
          0x09,
          0x0A
        ]);
        final frame2 = _buildTagNoticeFrame([
          0x53,
          0x56,
          0xAA,
          0xBB,
          0xCC,
          0xDD,
          0xEE,
          0xFF,
          0x11,
          0x22,
          0x33,
          0x44
        ]);

        // Send both frames at once
        dataController.add([...frame1, ...frame2]);
        await Future.delayed(const Duration(milliseconds: 50));

        expect(results.length, 2);
        expect(results[0].epcHex, '53560102030405060708090A');
        expect(results[1].epcHex, '5356AABBCCDDEEFF11223344');

        await subscription.cancel();
      });
    });

    group('verifyEpc', () {
      test('returns false when not connected', () async {
        when(mockSerialPort.isConnected).thenReturn(false);

        final result = await service.verifyEpc(
            [0x53, 0x56, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A]);

        expect(result, false);
      });

      test('returns true when matching tag found', () async {
        await setupConnectedService();

        final expectedEpc = [
          0x53,
          0x56,
          0x01,
          0x02,
          0x03,
          0x04,
          0x05,
          0x06,
          0x07,
          0x08,
          0x09,
          0x0A
        ];

        // Start verification in background
        final verification = service.verifyEpc(
          expectedEpc,
          timeout: const Duration(seconds: 1),
        );

        // Simulate tag being found after a short delay
        await Future.delayed(const Duration(milliseconds: 50));
        dataController.add(_buildTagNoticeFrame(expectedEpc));

        final result = await verification;

        expect(result, true);
      });

      test('returns false on timeout', () async {
        await setupConnectedService();

        final result = await service.verifyEpc(
          [
            0x53,
            0x56,
            0x01,
            0x02,
            0x03,
            0x04,
            0x05,
            0x06,
            0x07,
            0x08,
            0x09,
            0x0A
          ],
          timeout: const Duration(milliseconds: 100),
        );

        expect(result, false);
      });
    });
  });
}

/// Helper to build a valid tag notice frame for testing
List<int> _buildTagNoticeFrame(List<int> epc) {
  final payloadLength = epc.length + 3; // RSSI + PC(2 bytes) + EPC
  final frame = [
    0xBB, // Header
    0x02, // Notice type
    RfidConfig.cmdMultiplePoll, // Command
    (payloadLength >> 8) & 0xFF, // PL MSB
    payloadLength & 0xFF, // PL LSB
    0xC8, // RSSI
    0x30, 0x00, // PC
    ...epc,
    0x00, // Checksum placeholder
    0x7E, // End
  ];

  // Calculate checksum
  var checksum = 0;
  for (var i = 1; i < frame.length - 2; i++) {
    checksum += frame[i];
  }
  frame[frame.length - 2] = checksum & 0xFF;

  return frame;
}
