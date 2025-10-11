import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/printer_settings.dart';
import '../models/app_association.dart';
import '../utils/app_logger.dart';

/// Repository for managing application settings persistence
class SettingsRepository {
  static const String _printerSettingsKey = 'printer_settings';
  static const String _appAssociationsKey = 'app_associations';

  /// Save printer settings to local storage
  Future<void> savePrinterSettings(PrinterSettings settings) async {
    try {
      AppLogger.info('Saving printer settings: $settings');

      if (!settings.isValid()) {
        throw ArgumentError('Invalid printer settings');
      }

      final prefs = await SharedPreferences.getInstance();
      final json = settings.toJson();
      final jsonString = jsonEncode(json);

      await prefs.setString(_printerSettingsKey, jsonString);
      AppLogger.info('Printer settings saved successfully');
    } catch (e) {
      AppLogger.error('Error saving printer settings', e);
      rethrow;
    }
  }

  /// Load printer settings from local storage
  Future<PrinterSettings> loadPrinterSettings() async {
    try {
      AppLogger.info('Loading printer settings');

      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_printerSettingsKey);

      if (jsonString == null) {
        AppLogger.info('No saved printer settings found, using defaults');
        return const PrinterSettings.defaultSettings();
      }

      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      final settings = PrinterSettings.fromJson(json);

      AppLogger.info('Printer settings loaded: $settings');
      return settings;
    } catch (e) {
      AppLogger.error('Error loading printer settings, using defaults', e);
      return const PrinterSettings.defaultSettings();
    }
  }

  /// Clear printer settings (reset to defaults)
  Future<void> clearPrinterSettings() async {
    try {
      AppLogger.info('Clearing printer settings');
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_printerSettingsKey);
      AppLogger.info('Printer settings cleared');
    } catch (e) {
      AppLogger.error('Error clearing printer settings', e);
      rethrow;
    }
  }

  /// Check if printer settings exist
  Future<bool> hasPrinterSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.containsKey(_printerSettingsKey);
    } catch (e) {
      AppLogger.error('Error checking for printer settings', e);
      return false;
    }
  }

  /// Set an application association for a file type
  ///
  /// [fileType] - File extension (e.g., ".gcode", ".svg")
  /// [appPath] - Full path to the application
  /// [appName] - Human-readable name of the application
  Future<void> setAppAssociation(
    String fileType,
    String appPath,
    String appName,
  ) async {
    try {
      AppLogger.info(
          'Setting app association: $fileType -> $appName ($appPath)');

      // Load existing associations
      final associations = await _loadAppAssociations();

      // Update or add the association
      associations[fileType] = AppAssociation(
        fileType: fileType,
        appPath: appPath,
        appName: appName,
      );

      // Save back to storage
      await _saveAppAssociations(associations);

      AppLogger.info('App association saved successfully');
    } catch (e) {
      AppLogger.error('Error setting app association', e);
      rethrow;
    }
  }

  /// Get the application association for a file type
  ///
  /// Returns the [AppAssociation] if one exists, null otherwise
  Future<AppAssociation?> getAppAssociation(String fileType) async {
    try {
      AppLogger.info('Getting app association for: $fileType');

      final associations = await _loadAppAssociations();
      final association = associations[fileType];

      if (association != null) {
        AppLogger.info('Found association: ${association.appName}');
      } else {
        AppLogger.info('No association found for $fileType');
      }

      return association;
    } catch (e) {
      AppLogger.error('Error getting app association', e);
      return null;
    }
  }

  /// Remove an application association for a file type
  Future<void> removeAppAssociation(String fileType) async {
    try {
      AppLogger.info('Removing app association for: $fileType');

      final associations = await _loadAppAssociations();
      associations.remove(fileType);

      await _saveAppAssociations(associations);

      AppLogger.info('App association removed successfully');
    } catch (e) {
      AppLogger.error('Error removing app association', e);
      rethrow;
    }
  }

  /// Get all configured application associations
  Future<Map<String, AppAssociation>> getAllAppAssociations() async {
    try {
      return await _loadAppAssociations();
    } catch (e) {
      AppLogger.error('Error getting all app associations', e);
      return {};
    }
  }

  /// Load app associations from storage
  Future<Map<String, AppAssociation>> _loadAppAssociations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_appAssociationsKey);

      if (jsonString == null) {
        return {};
      }

      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      final associations = <String, AppAssociation>{};

      for (final entry in json.entries) {
        associations[entry.key] =
            AppAssociation.fromJson(entry.value as Map<String, dynamic>);
      }

      return associations;
    } catch (e) {
      AppLogger.error('Error loading app associations', e);
      return {};
    }
  }

  /// Save app associations to storage
  Future<void> _saveAppAssociations(
      Map<String, AppAssociation> associations) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final json = <String, dynamic>{};
      for (final entry in associations.entries) {
        json[entry.key] = entry.value.toJson();
      }

      final jsonString = jsonEncode(json);
      await prefs.setString(_appAssociationsKey, jsonString);
    } catch (e) {
      AppLogger.error('Error saving app associations', e);
      rethrow;
    }
  }
}
