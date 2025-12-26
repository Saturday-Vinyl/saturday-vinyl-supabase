import 'package:flutter_test/flutter_test.dart';
import 'package:saturday_app/config/rfid_config.dart';
import 'package:saturday_app/models/uhf_frame.dart';
import 'package:saturday_app/services/uhf_frame_codec.dart';

void main() {
  group('UhfFrameCodec', () {
    group('buildCommand', () {
      test('builds command with no parameters', () {
        final frame = UhfFrameCodec.buildCommand(RfidConfig.cmdSinglePoll);

        expect(frame[0], RfidConfig.frameHeader); // Header
        expect(frame[1], RfidConfig.frameTypeCommand); // Type
        expect(frame[2], RfidConfig.cmdSinglePoll); // Command
        expect(frame[3], 0x00); // PL MSB
        expect(frame[4], 0x00); // PL LSB
        expect(frame[frame.length - 1], RfidConfig.frameEnd); // End

        // Checksum = Type + Command + PL = 0x00 + 0x22 + 0x00 + 0x00 = 0x22
        expect(frame[5], 0x22);
      });

      test('builds command with parameters', () {
        final params = [0x01, 0x02, 0x03];
        final frame = UhfFrameCodec.buildCommand(0x27, params);

        expect(frame[0], RfidConfig.frameHeader);
        expect(frame[1], RfidConfig.frameTypeCommand);
        expect(frame[2], 0x27);
        expect(frame[3], 0x00); // PL MSB
        expect(frame[4], 0x03); // PL LSB (3 bytes)
        expect(frame[5], 0x01); // param 1
        expect(frame[6], 0x02); // param 2
        expect(frame[7], 0x03); // param 3
        expect(frame[frame.length - 1], RfidConfig.frameEnd);

        // Checksum = Type + Command + PL + params = 0x00 + 0x27 + 0x00 + 0x03 + 0x01 + 0x02 + 0x03 = 0x30
        expect(frame[8], 0x30);
      });

      test('handles large parameter length correctly', () {
        final params = List.generate(300, (i) => i & 0xFF);
        final frame = UhfFrameCodec.buildCommand(0x50, params);

        // 300 = 0x012C
        expect(frame[3], 0x01); // PL MSB
        expect(frame[4], 0x2C); // PL LSB
        expect(frame.length, 7 + 300); // Header + Type + Cmd + PL(2) + Params + Checksum + End
      });
    });

    group('buildSinglePoll', () {
      test('builds correct single poll command', () {
        final frame = UhfFrameCodec.buildSinglePoll();

        expect(frame, [
          0xBB, // Header
          0x00, // Type (command)
          0x22, // Command (single poll)
          0x00, // PL MSB
          0x00, // PL LSB
          0x22, // Checksum
          0x7E, // End
        ]);
      });
    });

    group('buildMultiplePoll', () {
      test('builds continuous poll command (count=0)', () {
        final frame = UhfFrameCodec.buildMultiplePoll();

        expect(frame[2], RfidConfig.cmdMultiplePoll);
        expect(frame[3], 0x00); // PL MSB
        expect(frame[4], 0x02); // PL LSB (2 bytes for count)
        expect(frame[5], 0x00); // count MSB
        expect(frame[6], 0x00); // count LSB
      });

      test('builds limited poll command', () {
        final frame = UhfFrameCodec.buildMultiplePoll(count: 10);

        expect(frame[5], 0x00); // count MSB
        expect(frame[6], 0x0A); // count LSB (10)
      });

      test('handles large count correctly', () {
        final frame = UhfFrameCodec.buildMultiplePoll(count: 1000);

        // 1000 = 0x03E8
        expect(frame[5], 0x03); // count MSB
        expect(frame[6], 0xE8); // count LSB
      });
    });

    group('buildStopMultiplePoll', () {
      test('builds correct stop command', () {
        final frame = UhfFrameCodec.buildStopMultiplePoll();

        expect(frame[2], RfidConfig.cmdStopMultiplePoll);
        expect(frame[3], 0x00); // PL MSB
        expect(frame[4], 0x00); // PL LSB (no params)
      });
    });

    group('buildWriteEpc', () {
      test('builds correct write EPC command', () {
        final password = [0x00, 0x00, 0x00, 0x00];
        final epc = [0x53, 0x56, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A];

        final frame = UhfFrameCodec.buildWriteEpc(password, epc);

        expect(frame[2], RfidConfig.cmdWriteEpc);
        expect(frame[5], 0x00); // password byte 1
        expect(frame[6], 0x00); // password byte 2
        expect(frame[7], 0x00); // password byte 3
        expect(frame[8], 0x00); // password byte 4
        expect(frame[9], RfidConfig.memBankEpc); // memory bank
        expect(frame[10], RfidConfig.epcWriteStartAddr); // start address
        expect(frame[11], 6); // word count (12 bytes / 2)
        expect(frame.sublist(12, 24), epc); // EPC data
      });

      test('throws on invalid password length', () {
        final password = [0x00, 0x00]; // Only 2 bytes
        final epc = List.filled(12, 0x00);

        expect(
          () => UhfFrameCodec.buildWriteEpc(password, epc),
          throwsArgumentError,
        );
      });

      test('throws on invalid EPC length', () {
        final password = [0x00, 0x00, 0x00, 0x00];
        final epc = [0x53, 0x56]; // Only 2 bytes

        expect(
          () => UhfFrameCodec.buildWriteEpc(password, epc),
          throwsArgumentError,
        );
      });
    });

    group('buildLockTag', () {
      test('builds correct lock command', () {
        final password = [0x00, 0x00, 0x00, 0x00];
        final lockPayload = [0x01, 0x02, 0x03];

        final frame = UhfFrameCodec.buildLockTag(password, lockPayload);

        expect(frame[2], RfidConfig.cmdLockTag);
        expect(frame.sublist(5, 9), password);
        expect(frame.sublist(9, 12), lockPayload);
      });

      test('throws on invalid password length', () {
        expect(
          () => UhfFrameCodec.buildLockTag([0x00], [0x01, 0x02, 0x03]),
          throwsArgumentError,
        );
      });

      test('throws on invalid lock payload length', () {
        expect(
          () => UhfFrameCodec.buildLockTag([0x00, 0x00, 0x00, 0x00], [0x01]),
          throwsArgumentError,
        );
      });
    });

    group('buildSetRfPower', () {
      test('builds correct set power command', () {
        final frame = UhfFrameCodec.buildSetRfPower(20);

        expect(frame[2], RfidConfig.cmdSetRfPower);
        expect(frame[5], 20); // power value
      });

      test('throws on power below minimum', () {
        expect(
          () => UhfFrameCodec.buildSetRfPower(-1),
          throwsArgumentError,
        );
      });

      test('throws on power above maximum', () {
        expect(
          () => UhfFrameCodec.buildSetRfPower(31),
          throwsArgumentError,
        );
      });

      test('accepts minimum power', () {
        final frame = UhfFrameCodec.buildSetRfPower(RfidConfig.minRfPower);
        expect(frame[5], RfidConfig.minRfPower);
      });

      test('accepts maximum power', () {
        final frame = UhfFrameCodec.buildSetRfPower(RfidConfig.maxRfPower);
        expect(frame[5], RfidConfig.maxRfPower);
      });
    });

    group('buildGetRfPower', () {
      test('builds correct get power command', () {
        final frame = UhfFrameCodec.buildGetRfPower();

        expect(frame[2], RfidConfig.cmdGetRfPower);
        expect(frame[3], 0x00); // PL MSB
        expect(frame[4], 0x00); // PL LSB
      });
    });

    group('parseFrame', () {
      test('parses valid response frame', () {
        // Success response to single poll
        final bytes = [
          0xBB, // Header
          0x01, // Type (response)
          0x22, // Command
          0x00, // PL MSB
          0x01, // PL LSB
          0x10, // Parameter (success code)
          0x34, // Checksum
          0x7E, // End
        ];

        final frame = UhfFrameCodec.parseFrame(bytes);

        expect(frame, isNotNull);
        expect(frame!.type, UhfFrameType.response);
        expect(frame.command, RfidConfig.cmdSinglePoll);
        expect(frame.parameters, [0x10]);
        expect(frame.isChecksumValid, true);
        expect(frame.isSuccess, true);
      });

      test('parses valid notice frame with tag data', () {
        // Tag poll notice
        final bytes = [
          0xBB, // Header
          0x02, // Type (notice)
          0x27, // Command (multiple poll)
          0x00, // PL MSB
          0x0F, // PL LSB (15 bytes: 1 RSSI + 2 PC + 12 EPC)
          0xC8, // RSSI
          0x30, // PC MSB
          0x00, // PC LSB
          0x53, 0x56, // EPC: "SV" prefix
          0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, // EPC data
          0x6C, // Checksum (calculated)
          0x7E, // End
        ];

        // Recalculate correct checksum
        var checksum = 0x02 + 0x27 + 0x00 + 0x0F; // Type + Cmd + PL
        checksum += 0xC8 + 0x30 + 0x00; // RSSI + PC
        checksum += 0x53 + 0x56 + 0x01 + 0x02 + 0x03 + 0x04 + 0x05 + 0x06 + 0x07 + 0x08 + 0x09 + 0x0A;
        bytes[bytes.length - 2] = checksum & 0xFF;

        final frame = UhfFrameCodec.parseFrame(bytes);

        expect(frame, isNotNull);
        expect(frame!.type, UhfFrameType.notice);
        expect(frame.command, RfidConfig.cmdMultiplePoll);
        expect(frame.isChecksumValid, true);
        expect(frame.parameters.length, 15);
      });

      test('returns null for frame too short', () {
        final bytes = [0xBB, 0x01, 0x22, 0x00];
        expect(UhfFrameCodec.parseFrame(bytes), isNull);
      });

      test('returns null for invalid header', () {
        final bytes = [0xAA, 0x01, 0x22, 0x00, 0x00, 0x23, 0x7E];
        expect(UhfFrameCodec.parseFrame(bytes), isNull);
      });

      test('returns null for invalid end marker', () {
        final bytes = [0xBB, 0x01, 0x22, 0x00, 0x00, 0x23, 0xFF];
        expect(UhfFrameCodec.parseFrame(bytes), isNull);
      });

      test('returns null for unknown frame type', () {
        final bytes = [0xBB, 0x99, 0x22, 0x00, 0x00, 0xBB, 0x7E];
        expect(UhfFrameCodec.parseFrame(bytes), isNull);
      });

      test('returns null for length mismatch', () {
        final bytes = [0xBB, 0x01, 0x22, 0x00, 0x05, 0x10, 0x36, 0x7E]; // Claims 5 params but only has 1
        expect(UhfFrameCodec.parseFrame(bytes), isNull);
      });

      test('detects invalid checksum', () {
        final bytes = [0xBB, 0x01, 0x22, 0x00, 0x01, 0x10, 0xFF, 0x7E]; // Wrong checksum

        final frame = UhfFrameCodec.parseFrame(bytes);

        expect(frame, isNotNull);
        expect(frame!.isChecksumValid, false);
      });

      test('preserves raw bytes', () {
        final bytes = [0xBB, 0x01, 0x22, 0x00, 0x00, 0x23, 0x7E];

        final frame = UhfFrameCodec.parseFrame(bytes);

        expect(frame!.rawBytes, bytes);
      });
    });

    group('validateChecksum', () {
      test('validates correct checksum', () {
        final bytes = [0xBB, 0x01, 0x22, 0x00, 0x01, 0x10, 0x34, 0x7E];
        expect(UhfFrameCodec.validateChecksum(bytes), true);
      });

      test('rejects incorrect checksum', () {
        final bytes = [0xBB, 0x01, 0x22, 0x00, 0x01, 0x10, 0xFF, 0x7E];
        expect(UhfFrameCodec.validateChecksum(bytes), false);
      });

      test('returns false for frame too short', () {
        final bytes = [0xBB, 0x01, 0x22];
        expect(UhfFrameCodec.validateChecksum(bytes), false);
      });
    });

    group('findFrameEnd', () {
      test('finds complete frame end', () {
        final bytes = [0xBB, 0x01, 0x22, 0x00, 0x00, 0x23, 0x7E];
        expect(UhfFrameCodec.findFrameEnd(bytes), 6);
      });

      test('finds frame end with parameters', () {
        final bytes = [0xBB, 0x01, 0x22, 0x00, 0x02, 0x10, 0x20, 0x55, 0x7E];
        expect(UhfFrameCodec.findFrameEnd(bytes), 8);
      });

      test('returns -1 for incomplete frame', () {
        final bytes = [0xBB, 0x01, 0x22, 0x00, 0x05, 0x10]; // Claims 5 params but incomplete
        expect(UhfFrameCodec.findFrameEnd(bytes), -1);
      });

      test('returns -1 for missing header', () {
        final bytes = [0x01, 0x22, 0x00, 0x00, 0x23, 0x7E];
        expect(UhfFrameCodec.findFrameEnd(bytes), -1);
      });

      test('returns -1 for frame too short', () {
        final bytes = [0xBB, 0x01];
        expect(UhfFrameCodec.findFrameEnd(bytes), -1);
      });

      test('handles frame with garbage before header', () {
        final bytes = [0xFF, 0xFF, 0xBB, 0x01, 0x22, 0x00, 0x00, 0x23, 0x7E];
        expect(UhfFrameCodec.findFrameEnd(bytes), 8);
      });
    });

    group('extractFrame', () {
      test('extracts complete frame', () {
        final bytes = [0xBB, 0x01, 0x22, 0x00, 0x00, 0x23, 0x7E, 0xFF, 0xFF];

        final result = UhfFrameCodec.extractFrame(bytes);

        expect(result, isNotNull);
        expect(result!.frame, [0xBB, 0x01, 0x22, 0x00, 0x00, 0x23, 0x7E]);
        expect(result.remaining, [0xFF, 0xFF]);
      });

      test('extracts frame with garbage before', () {
        final bytes = [0xFF, 0x00, 0xBB, 0x01, 0x22, 0x00, 0x00, 0x23, 0x7E];

        final result = UhfFrameCodec.extractFrame(bytes);

        expect(result, isNotNull);
        expect(result!.frame, [0xBB, 0x01, 0x22, 0x00, 0x00, 0x23, 0x7E]);
        expect(result.remaining, isEmpty);
      });

      test('returns null for incomplete frame', () {
        final bytes = [0xBB, 0x01, 0x22, 0x00, 0x05]; // Incomplete
        expect(UhfFrameCodec.extractFrame(bytes), isNull);
      });

      test('returns empty remaining when frame is exact', () {
        final bytes = [0xBB, 0x01, 0x22, 0x00, 0x00, 0x23, 0x7E];

        final result = UhfFrameCodec.extractFrame(bytes);

        expect(result!.remaining, isEmpty);
      });
    });

    group('parseTagPollData', () {
      test('parses tag poll data from notice frame', () {
        final frame = UhfFrame(
          type: UhfFrameType.notice,
          command: RfidConfig.cmdMultiplePoll,
          parameters: [
            0xC8, // RSSI
            0x30, 0x00, // PC
            0x53, 0x56, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, // EPC
          ],
        );

        final tagData = UhfFrameCodec.parseTagPollData(frame);

        expect(tagData, isNotNull);
        expect(tagData!.rssi, 0xC8);
        expect(tagData.pc, 0x3000);
        expect(tagData.epcBytes, [0x53, 0x56, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A]);
        expect(tagData.epcHex, '53560102030405060708090A');
        expect(tagData.isSaturdayTag, true);
      });

      test('returns null for non-notice frame', () {
        final frame = UhfFrame(
          type: UhfFrameType.response,
          command: RfidConfig.cmdMultiplePoll,
          parameters: [0x10],
        );

        expect(UhfFrameCodec.parseTagPollData(frame), isNull);
      });

      test('returns null for wrong command', () {
        final frame = UhfFrame(
          type: UhfFrameType.notice,
          command: RfidConfig.cmdSinglePoll,
          parameters: [0xC8, 0x30, 0x00, 0x53, 0x56],
        );

        expect(UhfFrameCodec.parseTagPollData(frame), isNull);
      });

      test('returns null for insufficient data', () {
        final frame = UhfFrame(
          type: UhfFrameType.notice,
          command: RfidConfig.cmdMultiplePoll,
          parameters: [0xC8, 0x30], // Only 2 bytes, need at least 4
        );

        expect(UhfFrameCodec.parseTagPollData(frame), isNull);
      });

      test('identifies non-Saturday tag', () {
        final frame = UhfFrame(
          type: UhfFrameType.notice,
          command: RfidConfig.cmdMultiplePoll,
          parameters: [
            0xC8, // RSSI
            0x30, 0x00, // PC
            0xAA, 0xBB, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, // Non-SV EPC
          ],
        );

        final tagData = UhfFrameCodec.parseTagPollData(frame);

        expect(tagData, isNotNull);
        expect(tagData!.isSaturdayTag, false);
      });
    });

    group('getResponseMessage', () {
      test('returns success message for success response', () {
        final frame = UhfFrame(
          type: UhfFrameType.response,
          command: RfidConfig.cmdSinglePoll,
          parameters: [RfidConfig.respSuccess],
        );

        expect(UhfFrameCodec.getResponseMessage(frame), 'Success');
      });

      test('returns error message for error response', () {
        final frame = UhfFrame(
          type: UhfFrameType.response,
          command: RfidConfig.cmdSinglePoll,
          parameters: [RfidConfig.respTagNotFound],
        );

        expect(UhfFrameCodec.getResponseMessage(frame), 'Tag not found');
      });

      test('returns not a response for non-response frame', () {
        final frame = UhfFrame(
          type: UhfFrameType.notice,
          command: RfidConfig.cmdMultiplePoll,
          parameters: [0xC8],
        );

        expect(UhfFrameCodec.getResponseMessage(frame), 'Not a response frame');
      });

      test('returns no response code for empty params', () {
        final frame = UhfFrame(
          type: UhfFrameType.response,
          command: RfidConfig.cmdSinglePoll,
          parameters: [],
        );

        expect(UhfFrameCodec.getResponseMessage(frame), 'No response code');
      });
    });

    group('round trip encoding/decoding', () {
      test('single poll round trips correctly', () {
        final command = UhfFrameCodec.buildSinglePoll();
        final parsed = UhfFrameCodec.parseFrame(command);

        expect(parsed, isNotNull);
        expect(parsed!.type, UhfFrameType.command);
        expect(parsed.command, RfidConfig.cmdSinglePoll);
        expect(parsed.parameters, isEmpty);
        expect(parsed.isChecksumValid, true);
      });

      test('multiple poll round trips correctly', () {
        final command = UhfFrameCodec.buildMultiplePoll(count: 100);
        final parsed = UhfFrameCodec.parseFrame(command);

        expect(parsed, isNotNull);
        expect(parsed!.command, RfidConfig.cmdMultiplePoll);
        expect(parsed.parameters, [0x00, 0x64]); // 100 in big-endian
        expect(parsed.isChecksumValid, true);
      });

      test('set power round trips correctly', () {
        final command = UhfFrameCodec.buildSetRfPower(25);
        final parsed = UhfFrameCodec.parseFrame(command);

        expect(parsed, isNotNull);
        expect(parsed!.command, RfidConfig.cmdSetRfPower);
        expect(parsed.parameters, [25]);
        expect(parsed.isChecksumValid, true);
      });

      test('write EPC round trips correctly', () {
        final password = [0x12, 0x34, 0x56, 0x78];
        final epc = [0x53, 0x56, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x11, 0x22, 0x33, 0x44];

        final command = UhfFrameCodec.buildWriteEpc(password, epc);
        final parsed = UhfFrameCodec.parseFrame(command);

        expect(parsed, isNotNull);
        expect(parsed!.command, RfidConfig.cmdWriteEpc);
        expect(parsed.isChecksumValid, true);

        // Verify password in parameters
        expect(parsed.parameters.sublist(0, 4), password);
        // Verify EPC in parameters (after password + memBank + startAddr + wordCount)
        expect(parsed.parameters.sublist(7), epc);
      });
    });
  });

  group('UhfFrame', () {
    group('convenience getters', () {
      test('isResponse returns true for response type', () {
        const frame = UhfFrame(
          type: UhfFrameType.response,
          command: 0x22,
          parameters: [0x10],
        );
        expect(frame.isResponse, true);
        expect(frame.isNotice, false);
        expect(frame.isCommand, false);
      });

      test('isNotice returns true for notice type', () {
        const frame = UhfFrame(
          type: UhfFrameType.notice,
          command: 0x27,
          parameters: [0xC8],
        );
        expect(frame.isNotice, true);
        expect(frame.isResponse, false);
        expect(frame.isCommand, false);
      });

      test('isCommand returns true for command type', () {
        const frame = UhfFrame(
          type: UhfFrameType.command,
          command: 0x22,
          parameters: [],
        );
        expect(frame.isCommand, true);
        expect(frame.isResponse, false);
        expect(frame.isNotice, false);
      });

      test('isSuccess returns true for success response', () {
        const frame = UhfFrame(
          type: UhfFrameType.response,
          command: 0x22,
          parameters: [RfidConfig.respSuccess],
        );
        expect(frame.isSuccess, true);
      });

      test('isSuccess returns false for error response', () {
        const frame = UhfFrame(
          type: UhfFrameType.response,
          command: 0x22,
          parameters: [RfidConfig.respTagNotFound],
        );
        expect(frame.isSuccess, false);
      });

      test('isSuccess returns false for non-response', () {
        const frame = UhfFrame(
          type: UhfFrameType.notice,
          command: 0x27,
          parameters: [RfidConfig.respSuccess],
        );
        expect(frame.isSuccess, false);
      });

      test('responseCode returns first parameter for response', () {
        const frame = UhfFrame(
          type: UhfFrameType.response,
          command: 0x22,
          parameters: [0x10, 0x20, 0x30],
        );
        expect(frame.responseCode, 0x10);
      });

      test('responseCode returns null for non-response', () {
        const frame = UhfFrame(
          type: UhfFrameType.notice,
          command: 0x27,
          parameters: [0x10],
        );
        expect(frame.responseCode, null);
      });

      test('dataParameters excludes response code', () {
        const frame = UhfFrame(
          type: UhfFrameType.response,
          command: 0x22,
          parameters: [0x10, 0x20, 0x30],
        );
        expect(frame.dataParameters, [0x20, 0x30]);
      });

      test('dataParameters returns all params for non-response', () {
        const frame = UhfFrame(
          type: UhfFrameType.notice,
          command: 0x27,
          parameters: [0x10, 0x20, 0x30],
        );
        expect(frame.dataParameters, [0x10, 0x20, 0x30]);
      });
    });

    group('toHexString', () {
      test('uses raw bytes when available', () {
        final bytes = [0xBB, 0x01, 0x22, 0x00, 0x00, 0x23, 0x7E];
        final frame = UhfFrame(
          type: UhfFrameType.response,
          command: 0x22,
          parameters: [],
          rawBytes: bytes,
        );

        expect(frame.toHexString(), 'BB 01 22 00 00 23 7E');
      });

      test('reconstructs frame when no raw bytes', () {
        const frame = UhfFrame(
          type: UhfFrameType.command,
          command: 0x22,
          parameters: [],
        );

        expect(frame.toHexString(), 'BB 00 22 00 00 22 7E');
      });
    });

    group('commandName', () {
      test('returns name for known commands', () {
        const frame = UhfFrame(
          type: UhfFrameType.command,
          command: RfidConfig.cmdMultiplePoll,
          parameters: [],
        );

        expect(frame.commandName, 'MultiplePoll');
      });

      test('returns hex for unknown commands', () {
        const frame = UhfFrame(
          type: UhfFrameType.command,
          command: 0xFF,
          parameters: [],
        );

        expect(frame.commandName, '0xFF');
      });
    });

    group('equality', () {
      test('equal frames are equal', () {
        const frame1 = UhfFrame(
          type: UhfFrameType.response,
          command: 0x22,
          parameters: [0x10],
        );
        const frame2 = UhfFrame(
          type: UhfFrameType.response,
          command: 0x22,
          parameters: [0x10],
        );

        expect(frame1, equals(frame2));
        expect(frame1.hashCode, equals(frame2.hashCode));
      });

      test('different type makes frames unequal', () {
        const frame1 = UhfFrame(
          type: UhfFrameType.response,
          command: 0x22,
          parameters: [0x10],
        );
        const frame2 = UhfFrame(
          type: UhfFrameType.notice,
          command: 0x22,
          parameters: [0x10],
        );

        expect(frame1, isNot(equals(frame2)));
      });
    });
  });

  group('TagPollData', () {
    test('epcHex formats bytes as uppercase hex', () {
      const tagData = TagPollData(
        rssi: 200,
        pc: 0x3000,
        epcBytes: [0x53, 0x56, 0xab, 0xcd],
      );

      expect(tagData.epcHex, '5356ABCD');
    });

    test('formattedEpc formats 96-bit EPC with dashes', () {
      const tagData = TagPollData(
        rssi: 200,
        pc: 0x3000,
        epcBytes: [0x53, 0x56, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A],
      );

      expect(tagData.formattedEpc, '5356-0102-0304-0506-0708-090A');
    });

    test('formattedEpc returns raw hex for non-96-bit EPC', () {
      const tagData = TagPollData(
        rssi: 200,
        pc: 0x3000,
        epcBytes: [0x53, 0x56, 0x01, 0x02],
      );

      expect(tagData.formattedEpc, '53560102');
    });

    test('isSaturdayTag returns true for SV prefix', () {
      const tagData = TagPollData(
        rssi: 200,
        pc: 0x3000,
        epcBytes: [0x53, 0x56, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A],
      );

      expect(tagData.isSaturdayTag, true);
    });

    test('isSaturdayTag returns false for non-SV prefix', () {
      const tagData = TagPollData(
        rssi: 200,
        pc: 0x3000,
        epcBytes: [0xAA, 0xBB, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A],
      );

      expect(tagData.isSaturdayTag, false);
    });

    test('equality works correctly', () {
      const tag1 = TagPollData(
        rssi: 200,
        pc: 0x3000,
        epcBytes: [0x53, 0x56],
      );
      const tag2 = TagPollData(
        rssi: 200,
        pc: 0x3000,
        epcBytes: [0x53, 0x56],
      );

      expect(tag1, equals(tag2));
    });
  });
}
