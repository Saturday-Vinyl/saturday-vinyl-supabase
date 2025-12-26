import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:saturday_app/config/rfid_config.dart';
import 'package:saturday_app/models/rfid_settings.dart';
import 'package:saturday_app/utils/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for persisting RFID module settings
///
/// Uses SharedPreferences for non-sensitive settings (port, baud rate, power)
/// and FlutterSecureStorage for sensitive data (access password).
class RfidSettingsService {
  static const String _keyPort = 'rfid_port';
  static const String _keyBaudRate = 'rfid_baud_rate';
  static const String _keyRfPower = 'rfid_rf_power';
  static const String _keyAccessPassword = 'rfid_access_password';

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secureStorage;

  RfidSettingsService(this._prefs, [FlutterSecureStorage? secureStorage])
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  // ==========================================================================
  // Port Settings
  // ==========================================================================

  /// Save the selected serial port
  Future<void> savePort(String port) async {
    await _prefs.setString(_keyPort, port);
    AppLogger.debug('RfidSettingsService: Saved port: $port');
  }

  /// Get the saved serial port
  String? getPort() {
    return _prefs.getString(_keyPort);
  }

  /// Clear the saved port
  Future<void> clearPort() async {
    await _prefs.remove(_keyPort);
    AppLogger.debug('RfidSettingsService: Cleared port');
  }

  // ==========================================================================
  // Baud Rate Settings
  // ==========================================================================

  /// Save the baud rate
  Future<void> saveBaudRate(int baudRate) async {
    await _prefs.setInt(_keyBaudRate, baudRate);
    AppLogger.debug('RfidSettingsService: Saved baud rate: $baudRate');
  }

  /// Get the saved baud rate (defaults to 115200)
  int getBaudRate() {
    return _prefs.getInt(_keyBaudRate) ?? RfidConfig.defaultBaudRate;
  }

  // ==========================================================================
  // RF Power Settings
  // ==========================================================================

  /// Save the RF power level
  Future<void> saveRfPower(int dbm) async {
    // Validate power range
    final clampedPower = dbm.clamp(RfidConfig.minRfPower, RfidConfig.maxRfPower);
    await _prefs.setInt(_keyRfPower, clampedPower);
    AppLogger.debug('RfidSettingsService: Saved RF power: $clampedPower dBm');
  }

  /// Get the saved RF power level (defaults to 20 dBm)
  int getRfPower() {
    return _prefs.getInt(_keyRfPower) ?? RfidConfig.defaultRfPower;
  }

  // ==========================================================================
  // Access Password (Secure Storage)
  // ==========================================================================

  /// Save the access password securely
  ///
  /// [passwordHex] - 8 hex characters representing 4 bytes (32 bits)
  Future<void> saveAccessPassword(String passwordHex) async {
    if (!RfidSettings.isValidAccessPassword(passwordHex)) {
      throw ArgumentError(
          'Access password must be 8 hex characters (e.g., "00000000")');
    }
    await _secureStorage.write(key: _keyAccessPassword, value: passwordHex);
    AppLogger.debug('RfidSettingsService: Saved access password');
  }

  /// Get the saved access password
  ///
  /// Returns null if no password is saved
  Future<String?> getAccessPassword() async {
    return await _secureStorage.read(key: _keyAccessPassword);
  }

  /// Clear the saved access password
  Future<void> clearAccessPassword() async {
    await _secureStorage.delete(key: _keyAccessPassword);
    AppLogger.debug('RfidSettingsService: Cleared access password');
  }

  // ==========================================================================
  // Bulk Operations
  // ==========================================================================

  /// Load all settings into an RfidSettings object
  Future<RfidSettings> loadAllSettings() async {
    final port = getPort();
    final baudRate = getBaudRate();
    final rfPower = getRfPower();
    final accessPassword = await getAccessPassword();

    final settings = RfidSettings(
      port: port,
      baudRate: baudRate,
      rfPower: rfPower,
      accessPassword: accessPassword,
    );

    AppLogger.debug('RfidSettingsService: Loaded settings: $settings');
    return settings;
  }

  /// Save all settings from an RfidSettings object
  ///
  /// Note: This does NOT save the access password. Use [saveAccessPassword]
  /// separately for security reasons.
  Future<void> saveSettings(RfidSettings settings) async {
    if (settings.port != null) {
      await savePort(settings.port!);
    }
    await saveBaudRate(settings.baudRate);
    await saveRfPower(settings.rfPower);

    AppLogger.debug('RfidSettingsService: Saved settings (excluding password)');
  }

  /// Clear all saved settings
  Future<void> clearSettings() async {
    await clearPort();
    await _prefs.remove(_keyBaudRate);
    await _prefs.remove(_keyRfPower);
    await clearAccessPassword();

    AppLogger.info('RfidSettingsService: Cleared all settings');
  }

  /// Check if any settings have been saved
  bool hasSettings() {
    return _prefs.containsKey(_keyPort) ||
        _prefs.containsKey(_keyBaudRate) ||
        _prefs.containsKey(_keyRfPower);
  }
}
