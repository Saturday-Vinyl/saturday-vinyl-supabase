import 'package:shared_preferences/shared_preferences.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// Service for persisting machine configuration preferences
class MachineConfigStorage {
  static const String _cncPortKey = 'machine_cnc_port';
  static const String _laserPortKey = 'machine_laser_port';
  static const String _cncBaudRateKey = 'machine_cnc_baud_rate';
  static const String _laserBaudRateKey = 'machine_laser_baud_rate';

  final SharedPreferences _prefs;

  MachineConfigStorage(this._prefs);

  /// Get saved CNC port
  String? getCncPort() {
    try {
      return _prefs.getString(_cncPortKey);
    } catch (error) {
      AppLogger.error('Error getting CNC port', error, null);
      return null;
    }
  }

  /// Set CNC port
  Future<bool> setCncPort(String port) async {
    try {
      final success = await _prefs.setString(_cncPortKey, port);
      if (success) {
        AppLogger.info('Saved CNC port: $port');
      }
      return success;
    } catch (error) {
      AppLogger.error('Error saving CNC port', error, null);
      return false;
    }
  }

  /// Get saved Laser port
  String? getLaserPort() {
    try {
      return _prefs.getString(_laserPortKey);
    } catch (error) {
      AppLogger.error('Error getting Laser port', error, null);
      return null;
    }
  }

  /// Set Laser port
  Future<bool> setLaserPort(String port) async {
    try {
      final success = await _prefs.setString(_laserPortKey, port);
      if (success) {
        AppLogger.info('Saved Laser port: $port');
      }
      return success;
    } catch (error) {
      AppLogger.error('Error saving Laser port', error, null);
      return false;
    }
  }

  /// Get saved CNC baud rate (default: 115200)
  int getCncBaudRate() {
    try {
      return _prefs.getInt(_cncBaudRateKey) ?? 115200;
    } catch (error) {
      AppLogger.error('Error getting CNC baud rate', error, null);
      return 115200;
    }
  }

  /// Set CNC baud rate
  Future<bool> setCncBaudRate(int baudRate) async {
    try {
      final success = await _prefs.setInt(_cncBaudRateKey, baudRate);
      if (success) {
        AppLogger.info('Saved CNC baud rate: $baudRate');
      }
      return success;
    } catch (error) {
      AppLogger.error('Error saving CNC baud rate', error, null);
      return false;
    }
  }

  /// Get saved Laser baud rate (default: 115200)
  int getLaserBaudRate() {
    try {
      return _prefs.getInt(_laserBaudRateKey) ?? 115200;
    } catch (error) {
      AppLogger.error('Error getting Laser baud rate', error, null);
      return 115200;
    }
  }

  /// Set Laser baud rate
  Future<bool> setLaserBaudRate(int baudRate) async {
    try {
      final success = await _prefs.setInt(_laserBaudRateKey, baudRate);
      if (success) {
        AppLogger.info('Saved Laser baud rate: $baudRate');
      }
      return success;
    } catch (error) {
      AppLogger.error('Error saving Laser baud rate', error, null);
      return false;
    }
  }

  /// Clear all machine configuration
  Future<bool> clearAll() async {
    try {
      await _prefs.remove(_cncPortKey);
      await _prefs.remove(_laserPortKey);
      await _prefs.remove(_cncBaudRateKey);
      await _prefs.remove(_laserBaudRateKey);
      AppLogger.info('Cleared all machine configuration');
      return true;
    } catch (error) {
      AppLogger.error('Error clearing machine configuration', error, null);
      return false;
    }
  }
}
