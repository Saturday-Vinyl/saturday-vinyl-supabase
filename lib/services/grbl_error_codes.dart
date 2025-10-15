/// GRBL Error and Alarm Code Definitions
///
/// Based on GRBL v1.1 and grblHAL specifications
/// References:
/// - https://github.com/gnea/grbl/wiki/Grbl-v1.1-Interface
/// - https://github.com/grblHAL/core/wiki/Errors-and-Alarms

/// GRBL Error information
class GrblError {
  final int code;
  final String name;
  final String description;
  final String userMessage;

  const GrblError({
    required this.code,
    required this.name,
    required this.description,
    required this.userMessage,
  });
}

/// GRBL Alarm information
class GrblAlarm {
  final int code;
  final String name;
  final String description;
  final String userMessage;

  const GrblAlarm({
    required this.code,
    required this.name,
    required this.description,
    required this.userMessage,
  });
}

/// Standard GRBL error codes
class GrblErrorCodes {
  static const Map<int, GrblError> errors = {
    1: GrblError(
      code: 1,
      name: 'Expected command letter',
      description: 'G-code words consist of a letter and a value. Letter was not found.',
      userMessage: 'Invalid G-code format: missing command letter',
    ),
    2: GrblError(
      code: 2,
      name: 'Bad number format',
      description: 'Missing the expected G-code word value or numeric value format is not valid.',
      userMessage: 'Invalid number in G-code command',
    ),
    3: GrblError(
      code: 3,
      name: 'Invalid statement',
      description: 'Grbl \$ system command was not recognized or supported.',
      userMessage: 'Command not recognized by machine',
    ),
    4: GrblError(
      code: 4,
      name: 'Value less than 0',
      description: 'Negative value received for an expected positive value.',
      userMessage: 'Negative value not allowed for this command',
    ),
    5: GrblError(
      code: 5,
      name: 'Setting disabled',
      description: 'Homing cycle failure. Homing is not enabled in settings.',
      userMessage: 'Homing is disabled. Enable in machine settings.',
    ),
    6: GrblError(
      code: 6,
      name: 'Value less than 3 usec',
      description: 'Minimum step pulse time must be greater than 3usec.',
      userMessage: 'Step pulse time too small (must be greater than 3 microseconds)',
    ),
    7: GrblError(
      code: 7,
      name: 'EEPROM read fail',
      description: 'An EEPROM read failed. Auto-restoring affected EEPROM to default values.',
      userMessage: 'Machine settings read error. Restoring defaults.',
    ),
    8: GrblError(
      code: 8,
      name: 'Not idle',
      description: 'Grbl \$ command cannot be used unless Grbl is IDLE. Ensures smooth operation during a job.',
      userMessage: 'Command requires machine to be idle. Stop current operation first.',
    ),
    9: GrblError(
      code: 9,
      name: 'G-code lock',
      description: 'G-code commands are locked out during alarm or jog state.',
      userMessage: 'Machine is in alarm state. Reset or unlock before sending commands.',
    ),
    10: GrblError(
      code: 10,
      name: 'Homing not enabled',
      description: 'Soft limits cannot be enabled without homing also enabled.',
      userMessage: 'Enable homing before enabling soft limits',
    ),
    11: GrblError(
      code: 11,
      name: 'Line overflow',
      description: 'Max characters per line exceeded. Received command line was not executed.',
      userMessage: 'Command too long. Split into smaller commands.',
    ),
    12: GrblError(
      code: 12,
      name: 'Step rate exceeds 30kHz',
      description: 'Grbl \$ setting value cause the step rate to exceed the maximum supported.',
      userMessage: 'Machine cannot move this fast. Reduce speed or acceleration.',
    ),
    13: GrblError(
      code: 13,
      name: 'Check door',
      description: 'Safety door detected as opened and door state initiated.',
      userMessage: 'Safety door is open. Close door to continue.',
    ),
    14: GrblError(
      code: 14,
      name: 'Line length exceeded',
      description: 'Build info or startup line exceeded EEPROM line length limit. Line not stored.',
      userMessage: 'Configuration line too long to save',
    ),
    15: GrblError(
      code: 15,
      name: 'Travel exceeded',
      description: 'Jog target exceeds machine travel. Jog command has been ignored.',
      userMessage: 'Cannot jog beyond machine limits',
    ),
    16: GrblError(
      code: 16,
      name: 'Invalid jog command',
      description: 'Jog command has no = or contains prohibited g-code.',
      userMessage: 'Invalid jog command format',
    ),
    17: GrblError(
      code: 17,
      name: 'Setting disabled',
      description: 'Laser mode requires PWM output.',
      userMessage: 'Laser mode not available on this machine',
    ),
    20: GrblError(
      code: 20,
      name: 'Unsupported command',
      description: 'Unsupported or invalid g-code command found in block.',
      userMessage: 'G-code command not supported by this machine',
    ),
    21: GrblError(
      code: 21,
      name: 'Modal group violation',
      description: 'More than one g-code command from same modal group found in block.',
      userMessage: 'Cannot use multiple commands from same group in one line',
    ),
    22: GrblError(
      code: 22,
      name: 'Undefined feed rate',
      description: 'Feed rate has not yet been set or is undefined.',
      userMessage: 'Set feed rate (F parameter) before moving',
    ),
    23: GrblError(
      code: 23,
      name: 'Invalid gcode ID:23',
      description: 'G-code command in block requires an integer value.',
      userMessage: 'Command requires a whole number value',
    ),
    24: GrblError(
      code: 24,
      name: 'Invalid gcode ID:24',
      description: 'More than one g-code command that requires axis words found in block.',
      userMessage: 'Too many axis commands in one line',
    ),
    25: GrblError(
      code: 25,
      name: 'Invalid gcode ID:25',
      description: 'Repeated g-code word found in block.',
      userMessage: 'Duplicate command in G-code line',
    ),
    26: GrblError(
      code: 26,
      name: 'Invalid gcode ID:26',
      description: 'No axis words found in block for g-code command that requires them.',
      userMessage: 'Command requires axis coordinates (X, Y, or Z)',
    ),
    27: GrblError(
      code: 27,
      name: 'Invalid gcode ID:27',
      description: 'Line number value is invalid.',
      userMessage: 'Invalid line number in G-code',
    ),
    28: GrblError(
      code: 28,
      name: 'Invalid gcode ID:28',
      description: 'G-code command is missing a required value word.',
      userMessage: 'Command missing required parameter',
    ),
    29: GrblError(
      code: 29,
      name: 'Invalid gcode ID:29',
      description: 'Work coordinate system is not valid.',
      userMessage: 'Invalid work coordinate system (G54-G59)',
    ),
    30: GrblError(
      code: 30,
      name: 'Invalid gcode ID:30',
      description: 'G53 only allowed with G0 and G1 motion modes.',
      userMessage: 'G53 can only be used with G0 or G1 commands',
    ),
    31: GrblError(
      code: 31,
      name: 'Invalid gcode ID:31',
      description: 'Axis words found in block when no command uses them.',
      userMessage: 'Axis coordinates not valid for this command',
    ),
    32: GrblError(
      code: 32,
      name: 'Invalid gcode ID:32',
      description: 'G2 and G3 arcs require at least one in-plane axis word.',
      userMessage: 'Arc command requires axis coordinates',
    ),
    33: GrblError(
      code: 33,
      name: 'Invalid gcode ID:33',
      description: 'Motion command target is invalid.',
      userMessage: 'Invalid target position for move command',
    ),
    34: GrblError(
      code: 34,
      name: 'Invalid gcode ID:34',
      description: 'Arc radius value is invalid.',
      userMessage: 'Invalid arc radius (too small or zero)',
    ),
    35: GrblError(
      code: 35,
      name: 'Invalid gcode ID:35',
      description: 'G2 and G3 arcs require at least one in-plane offset word.',
      userMessage: 'Arc command requires I, J, or K offset',
    ),
    36: GrblError(
      code: 36,
      name: 'Invalid gcode ID:36',
      description: 'Unused value words found in block.',
      userMessage: 'Unused parameters in G-code line',
    ),
    37: GrblError(
      code: 37,
      name: 'Invalid gcode ID:37',
      description: 'G43.1 dynamic tool length offset is not assigned to configured tool length axis.',
      userMessage: 'Tool length offset axis not configured',
    ),
    38: GrblError(
      code: 38,
      name: 'Invalid gcode ID:38',
      description: 'Tool number greater than max supported value.',
      userMessage: 'Tool number exceeds maximum allowed',
    ),
    // grblHAL extended errors
    60: GrblError(
      code: 60,
      name: 'SD card mount failed',
      description: 'SD card failed to mount.',
      userMessage: 'SD card error: cannot read card',
    ),
    61: GrblError(
      code: 61,
      name: 'SD card file open/read failed',
      description: 'SD card file open/read failed.',
      userMessage: 'Cannot open or read file from SD card',
    ),
    62: GrblError(
      code: 62,
      name: 'SD card directory listing failed',
      description: 'SD card directory listing failed.',
      userMessage: 'Cannot list SD card directory',
    ),
    63: GrblError(
      code: 63,
      name: 'SD card directory not found',
      description: 'SD card directory not found.',
      userMessage: 'Directory not found on SD card',
    ),
    64: GrblError(
      code: 64,
      name: 'SD card file empty',
      description: 'SD card file empty.',
      userMessage: 'File on SD card is empty',
    ),
    70: GrblError(
      code: 70,
      name: 'Bluetooth initialisation failed',
      description: 'Bluetooth initialisation failed.',
      userMessage: 'Bluetooth setup error',
    ),
    71: GrblError(
      code: 71,
      name: 'WiFi initialisation failed',
      description: 'WiFi initialisation failed.',
      userMessage: 'WiFi setup error',
    ),
    72: GrblError(
      code: 72,
      name: 'Ethernet initialisation failed',
      description: 'Ethernet initialisation failed.',
      userMessage: 'Ethernet setup error',
    ),
    79: GrblError(
      code: 79,
      name: 'Expression evaluation failed',
      description: 'Expression evaluation failed or expression variable not found.',
      userMessage: 'Cannot evaluate expression or variable not found',
    ),
  };

  static const Map<int, GrblAlarm> alarms = {
    1: GrblAlarm(
      code: 1,
      name: 'Hard limit',
      description: 'Hard limit has been triggered. Machine position is likely lost due to sudden halt. Re-homing is highly recommended.',
      userMessage: 'HARD LIMIT triggered! Machine stopped. Re-home required.',
    ),
    2: GrblAlarm(
      code: 2,
      name: 'Soft limit',
      description: 'Soft limit alarm. G-code motion target exceeds machine travel. Machine position retained. Alarm may be safely unlocked.',
      userMessage: 'Soft limit exceeded. Movement would go beyond machine limits.',
    ),
    3: GrblAlarm(
      code: 3,
      name: 'Abort during cycle',
      description: 'Reset while in motion. Machine position is likely lost due to sudden halt. Re-homing is highly recommended.',
      userMessage: 'Emergency stop activated. Re-home required.',
    ),
    4: GrblAlarm(
      code: 4,
      name: 'Probe fail',
      description: 'Probe fail. Probe is not in the expected initial state before starting probe cycle when G38.2 and G38.3 is not triggered and G38.4 and G38.5 is triggered.',
      userMessage: 'Probe failure. Check probe connection and try again.',
    ),
    5: GrblAlarm(
      code: 5,
      name: 'Probe fail',
      description: 'Probe fail. Probe did not contact the workpiece within the programmed travel for G38.2 and G38.4.',
      userMessage: 'Probe did not make contact. Check probe position.',
    ),
    6: GrblAlarm(
      code: 6,
      name: 'Homing fail',
      description: 'Homing fail. The active homing cycle was reset.',
      userMessage: 'Homing cycle failed or was cancelled.',
    ),
    7: GrblAlarm(
      code: 7,
      name: 'Homing fail',
      description: 'Homing fail. Safety door was opened during homing cycle.',
      userMessage: 'Homing failed: safety door opened.',
    ),
    8: GrblAlarm(
      code: 8,
      name: 'Homing fail',
      description: 'Homing fail. Pull off travel failed to clear limit switch. Try increasing pull-off setting or check wiring.',
      userMessage: 'Homing failed: cannot clear limit switch. Check pull-off distance.',
    ),
    9: GrblAlarm(
      code: 9,
      name: 'Homing fail',
      description: 'Homing fail. Could not find limit switch within search distances. Try increasing max travel, decreasing pull-off distance, or check wiring.',
      userMessage: 'Homing failed: limit switch not found. Check wiring and settings.',
    ),
    10: GrblAlarm(
      code: 10,
      name: 'EStop',
      description: 'EStop asserted. Clear and reset.',
      userMessage: 'EMERGENCY STOP! Clear E-stop and reset machine.',
    ),
    11: GrblAlarm(
      code: 11,
      name: 'Homing required',
      description: 'Homing required. Execute homing command to continue.',
      userMessage: 'Machine must be homed before operation.',
    ),
    12: GrblAlarm(
      code: 12,
      name: 'Limit switch engaged',
      description: 'Limit switch engaged. Clear before continuing.',
      userMessage: 'Limit switch is engaged. Move away from limit.',
    ),
    13: GrblAlarm(
      code: 13,
      name: 'Probe protection',
      description: 'Probe protection triggered. Clear before continuing.',
      userMessage: 'Probe protection active. Check probe and clear.',
    ),
    14: GrblAlarm(
      code: 14,
      name: 'Spindle at speed timeout',
      description: 'Spindle at speed timeout. Clear before continuing.',
      userMessage: 'Spindle failed to reach target speed in time.',
    ),
  };

  /// Get error message for an error code
  static GrblError? getError(int code) {
    return errors[code];
  }

  /// Get alarm message for an alarm code
  static GrblAlarm? getAlarm(int code) {
    return alarms[code];
  }

  /// Parse error from response line (e.g., "error:9")
  static GrblError? parseErrorResponse(String response) {
    final match = RegExp(r'error:(\d+)').firstMatch(response.toLowerCase());
    if (match != null) {
      final code = int.tryParse(match.group(1)!);
      if (code != null) {
        return getError(code) ??
            GrblError(
              code: code,
              name: 'Unknown error',
              description: 'Unknown error code $code',
              userMessage: 'Machine error $code occurred. Check machine documentation.',
            );
      }
    }
    return null;
  }

  /// Parse alarm from response line (e.g., "ALARM:1")
  static GrblAlarm? parseAlarmResponse(String response) {
    final match = RegExp(r'alarm:(\d+)').firstMatch(response.toLowerCase());
    if (match != null) {
      final code = int.tryParse(match.group(1)!);
      if (code != null) {
        return getAlarm(code) ??
            GrblAlarm(
              code: code,
              name: 'Unknown alarm',
              description: 'Unknown alarm code $code',
              userMessage: 'Machine alarm $code triggered. Check machine documentation.',
            );
      }
    }
    return null;
  }
}
