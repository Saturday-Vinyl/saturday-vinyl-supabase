import 'package:flutter_test/flutter_test.dart';
import 'package:saturday_app/config/rfid_config.dart';

void main() {
  group('RfidConfig', () {
    group('EPC Identifier Configuration', () {
      test('epcPrefixBytes is SV in ASCII', () {
        expect(RfidConfig.epcPrefixBytes, [0x53, 0x56]);
        // Verify it spells "SV"
        expect(String.fromCharCodes(RfidConfig.epcPrefixBytes), 'SV');
      });

      test('epcPrefixHex matches bytes', () {
        expect(RfidConfig.epcPrefixHex, '5356');
        // Verify consistency
        final fromBytes = RfidConfig.epcPrefixBytes
            .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
            .join();
        expect(fromBytes, RfidConfig.epcPrefixHex.toUpperCase());
      });

      test('epcLengthBytes is 12 (96 bits)', () {
        expect(RfidConfig.epcLengthBytes, 12);
        expect(RfidConfig.epcLengthBytes * 8, 96); // 96 bits
      });

      test('epcLengthHex is 24 (12 bytes * 2)', () {
        expect(RfidConfig.epcLengthHex, 24);
        expect(RfidConfig.epcLengthHex, RfidConfig.epcLengthBytes * 2);
      });

      test('epcRandomLengthBytes is EPC length minus prefix', () {
        expect(RfidConfig.epcRandomLengthBytes, 10);
        expect(
          RfidConfig.epcRandomLengthBytes,
          RfidConfig.epcLengthBytes - RfidConfig.epcPrefixBytes.length,
        );
      });
    });

    group('Serial Communication Defaults', () {
      test('defaultBaudRate is 115200', () {
        expect(RfidConfig.defaultBaudRate, 115200);
      });

      test('availableBaudRates contains common rates', () {
        expect(RfidConfig.availableBaudRates, contains(9600));
        expect(RfidConfig.availableBaudRates, contains(115200));
        expect(RfidConfig.availableBaudRates.length, 5);
      });

      test('serial config is 8N1', () {
        expect(RfidConfig.dataBits, 8);
        expect(RfidConfig.stopBits, 1);
        expect(RfidConfig.parity, 0); // No parity
      });
    });

    group('RF Power Configuration', () {
      test('defaultRfPower is 20 dBm', () {
        expect(RfidConfig.defaultRfPower, 20);
      });

      test('power range is 0-30 dBm', () {
        expect(RfidConfig.minRfPower, 0);
        expect(RfidConfig.maxRfPower, 30);
      });

      test('default is within range', () {
        expect(RfidConfig.defaultRfPower, greaterThanOrEqualTo(RfidConfig.minRfPower));
        expect(RfidConfig.defaultRfPower, lessThanOrEqualTo(RfidConfig.maxRfPower));
      });
    });

    group('Timing Configuration', () {
      test('pollingIntervalMs is reasonable', () {
        expect(RfidConfig.pollingIntervalMs, 150);
        expect(RfidConfig.pollingIntervalMs, greaterThan(50));
        expect(RfidConfig.pollingIntervalMs, lessThan(500));
      });

      test('noTagTimeoutMs is 2 seconds', () {
        expect(RfidConfig.noTagTimeoutMs, 2000);
      });

      test('moduleEnableDelayMs is 100ms', () {
        expect(RfidConfig.moduleEnableDelayMs, 100);
      });

      test('commandTimeoutMs is 1 second', () {
        expect(RfidConfig.commandTimeoutMs, 1000);
      });
    });

    group('Frame Format', () {
      test('frameHeader is 0xBB', () {
        expect(RfidConfig.frameHeader, 0xBB);
      });

      test('frameEnd is 0x7E', () {
        expect(RfidConfig.frameEnd, 0x7E);
      });

      test('frame types are defined', () {
        expect(RfidConfig.frameTypeCommand, 0x00);
        expect(RfidConfig.frameTypeResponse, 0x01);
        expect(RfidConfig.frameTypeNotice, 0x02);
      });
    });

    group('UHF Commands', () {
      test('polling commands are defined', () {
        expect(RfidConfig.cmdSinglePoll, 0x22);
        expect(RfidConfig.cmdMultiplePoll, 0x27);
        expect(RfidConfig.cmdStopMultiplePoll, 0x28);
      });

      test('data commands are defined', () {
        expect(RfidConfig.cmdReadData, 0x39);
        expect(RfidConfig.cmdWriteEpc, 0x49);
        expect(RfidConfig.cmdLockTag, 0x82);
      });

      test('power commands are defined', () {
        expect(RfidConfig.cmdSetRfPower, 0xB6);
        expect(RfidConfig.cmdGetRfPower, 0xB7);
      });
    });

    group('Response Codes', () {
      test('success code is 0x10', () {
        expect(RfidConfig.respSuccess, 0x10);
      });

      test('error codes are defined', () {
        expect(RfidConfig.respInvalidCommand, 0x11);
        expect(RfidConfig.respInvalidParameter, 0x12);
        expect(RfidConfig.respMemoryOverrun, 0x13);
        expect(RfidConfig.respMemoryLocked, 0x14);
        expect(RfidConfig.respTagNotFound, 0x15);
        expect(RfidConfig.respReadFailed, 0x16);
        expect(RfidConfig.respWriteFailed, 0x17);
        expect(RfidConfig.respLockFailed, 0x18);
      });

      test('getErrorMessage returns correct messages', () {
        expect(RfidConfig.getErrorMessage(RfidConfig.respSuccess), 'Success');
        expect(RfidConfig.getErrorMessage(RfidConfig.respInvalidCommand), 'Invalid command');
        expect(RfidConfig.getErrorMessage(RfidConfig.respTagNotFound), 'Tag not found');
        expect(RfidConfig.getErrorMessage(RfidConfig.respWriteFailed), 'Write operation failed');
        expect(RfidConfig.getErrorMessage(RfidConfig.respLockFailed), 'Lock operation failed');
      });

      test('getErrorMessage handles unknown codes', () {
        final message = RfidConfig.getErrorMessage(0xFF);
        expect(message, contains('Unknown error'));
        expect(message, contains('FF'));
      });
    });

    group('Memory Bank Constants', () {
      test('memory banks are defined', () {
        expect(RfidConfig.memBankReserved, 0x00);
        expect(RfidConfig.memBankEpc, 0x01);
        expect(RfidConfig.memBankTid, 0x02);
        expect(RfidConfig.memBankUser, 0x03);
      });

      test('EPC write parameters are correct', () {
        expect(RfidConfig.epcWriteStartAddr, 0x02); // Skip PC bytes
        expect(RfidConfig.epcWriteWordCount, 0x06); // 6 words = 12 bytes
        // Verify word count matches EPC length
        expect(RfidConfig.epcWriteWordCount * 2, RfidConfig.epcLengthBytes);
      });
    });

    group('Access Password', () {
      test('defaultAccessPassword is all zeros', () {
        expect(RfidConfig.defaultAccessPassword, [0x00, 0x00, 0x00, 0x00]);
        expect(RfidConfig.defaultAccessPassword.length, 4); // 32 bits
      });
    });
  });
}
