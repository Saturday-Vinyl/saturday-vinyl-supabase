import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/app_association.dart';
import '../repositories/settings_repository.dart';
import '../utils/app_logger.dart';

/// Result of a file launching operation
class FileLaunchResult {
  final bool success;
  final String? errorMessage;
  final String? suggestion;

  const FileLaunchResult({
    required this.success,
    this.errorMessage,
    this.suggestion,
  });

  factory FileLaunchResult.success() {
    return const FileLaunchResult(success: true);
  }

  factory FileLaunchResult.failure(String errorMessage, {String? suggestion}) {
    return FileLaunchResult(
      success: false,
      errorMessage: errorMessage,
      suggestion: suggestion,
    );
  }
}

/// Service for launching production files in external applications
class FileLauncherService {
  static final FileLauncherService _instance = FileLauncherService._internal();
  factory FileLauncherService() => _instance;
  FileLauncherService._internal();

  final SettingsRepository _settingsRepository = SettingsRepository();

  /// Check if file launching is available on this platform
  bool isFileLaunchingAvailable() {
    return Platform.isMacOS || Platform.isWindows || Platform.isLinux;
  }

  /// Open a production file from Supabase storage in an external application
  ///
  /// [fileUrl] - Full URL to the file in Supabase storage
  /// [fileName] - Name of the file including extension
  /// [fileType] - File extension (e.g., ".gcode", ".svg")
  ///
  /// Returns a [FileLaunchResult] indicating success or failure
  Future<FileLaunchResult> openProductionFile({
    required String fileUrl,
    required String fileName,
    required String fileType,
  }) async {
    try {
      if (!isFileLaunchingAvailable()) {
        return FileLaunchResult.failure(
          'File launching is only supported on desktop platforms',
        );
      }

      AppLogger.info('Opening production file: $fileName ($fileType)');

      // Download file to temp directory
      final filePath = await _downloadFile(fileUrl, fileName);
      AppLogger.info('File downloaded to: $filePath');

      // Check if there's a configured app association for this file type
      final appAssociation = await getDefaultAppForFileType(fileType);

      if (appAssociation != null) {
        // Open in specific app
        AppLogger.info(
            'Opening file in configured app: ${appAssociation.appName}');
        return await openInSpecificApp(filePath, appAssociation.appPath);
      } else {
        // Open in system default app
        AppLogger.info('Opening file in system default app');
        return await openInDefaultApp(filePath);
      }
    } catch (e, stackTrace) {
      AppLogger.error('Error opening production file', e, stackTrace);
      return FileLaunchResult.failure(
        'Failed to open file: ${e.toString()}',
      );
    }
  }

  /// Download file from URL to temp directory
  ///
  /// Returns the path to the downloaded file
  Future<String> _downloadFile(String fileUrl, String fileName) async {
    try {
      final tempDir = Directory.systemTemp;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final uniqueFileName = '${timestamp}_$fileName';
      final filePath = path.join(tempDir.path, uniqueFileName);

      AppLogger.info('Downloading file from Supabase storage: $fileUrl');

      // Extract the storage path from the URL
      // URL format: storage/v1/object/production-files/bucket-id/file-id-filename.ext
      // We need: production-files/bucket-id/file-id-filename.ext
      String storagePath = fileUrl;

      // Remove the storage API prefix if present
      if (storagePath.contains('storage/v1/object/')) {
        storagePath = storagePath.split('storage/v1/object/').last;
      }

      AppLogger.info('Storage path: $storagePath');

      // Download the file using Supabase client
      final supabase = Supabase.instance.client;
      final bytes = await supabase.storage.from('production-files').download(
            storagePath.replaceFirst('production-files/', ''),
          );

      AppLogger.info('Downloaded ${bytes.length} bytes');

      // Write to temp file
      final file = File(filePath);
      await file.writeAsBytes(bytes);

      AppLogger.info('File saved successfully to: $filePath');
      return filePath;
    } catch (e, stackTrace) {
      AppLogger.error('Error downloading file', e, stackTrace);
      rethrow;
    }
  }

  /// Open file in system default application
  ///
  /// [filePath] - Path to the file to open
  ///
  /// Returns a [FileLaunchResult] indicating success or failure
  Future<FileLaunchResult> openInDefaultApp(String filePath) async {
    try {
      final file = File(filePath);
      if (!file.existsSync()) {
        return FileLaunchResult.failure('File not found: $filePath');
      }

      AppLogger.info('Opening file in default app: $filePath');

      final uri = Uri.file(filePath);

      // Use url_launcher to open the file
      final canLaunch = await canLaunchUrl(uri);
      if (!canLaunch) {
        return FileLaunchResult.failure(
          'Cannot open file: No default application configured',
          suggestion:
              'Configure an application for this file type in Settings',
        );
      }

      final launched = await launchUrl(uri);
      if (!launched) {
        return FileLaunchResult.failure(
          'Failed to launch file',
          suggestion: 'Try configuring a specific application in Settings',
        );
      }

      AppLogger.info('File opened successfully in default app');
      return FileLaunchResult.success();
    } catch (e, stackTrace) {
      AppLogger.error('Error opening file in default app', e, stackTrace);
      return FileLaunchResult.failure(
        'Error opening file: ${e.toString()}',
      );
    }
  }

  /// Open file in a specific application
  ///
  /// [filePath] - Path to the file to open
  /// [appPath] - Path to the application executable
  ///
  /// Returns a [FileLaunchResult] indicating success or failure
  Future<FileLaunchResult> openInSpecificApp(
      String filePath, String appPath) async {
    try {
      final file = File(filePath);
      if (!file.existsSync()) {
        return FileLaunchResult.failure('File not found: $filePath');
      }

      // Check if app exists
      final app = File(appPath);
      final appDir = Directory(appPath);

      // On macOS, apps are directories (.app bundles)
      // On Windows/Linux, apps are executables
      final appExists = Platform.isMacOS
          ? appDir.existsSync()
          : (app.existsSync() || appDir.existsSync());

      if (!appExists) {
        final appName = path.basename(appPath);
        return FileLaunchResult.failure(
          'Application not found: $appName',
          suggestion:
              'Install $appName or update the file association in Settings',
        );
      }

      AppLogger.info('Opening file in specific app: $appPath');

      // Platform-specific launching
      ProcessResult result;
      if (Platform.isMacOS) {
        // Use 'open' command on macOS
        result = await Process.run('open', ['-a', appPath, filePath]);
      } else if (Platform.isWindows) {
        // Use 'start' command on Windows
        result = await Process.run('cmd', ['/c', 'start', '', appPath, filePath]);
      } else {
        // Linux - just execute the app with the file as argument
        result = await Process.run(appPath, [filePath]);
      }

      if (result.exitCode != 0) {
        AppLogger.error('Failed to launch app. Exit code: ${result.exitCode}');
        AppLogger.error('stderr: ${result.stderr}');
        return FileLaunchResult.failure(
          'Failed to launch application',
          suggestion: 'Check that the application path is correct in Settings',
        );
      }

      AppLogger.info('File opened successfully in specific app');
      return FileLaunchResult.success();
    } catch (e, stackTrace) {
      AppLogger.error('Error opening file in specific app', e, stackTrace);
      return FileLaunchResult.failure(
        'Error launching application: ${e.toString()}',
      );
    }
  }

  /// Get the configured application for a file type
  ///
  /// [fileType] - File extension (e.g., ".gcode", ".svg")
  ///
  /// Returns the [AppAssociation] if one is configured, null otherwise
  Future<AppAssociation?> getDefaultAppForFileType(String fileType) async {
    try {
      return await _settingsRepository.getAppAssociation(fileType);
    } catch (e) {
      AppLogger.error('Error getting app association for $fileType', e);
      return null;
    }
  }

  /// Get the human-readable name of the app that will open this file type
  ///
  /// Returns the app name if configured, "System Default" otherwise
  Future<String> getAppNameForFileType(String fileType) async {
    final association = await getDefaultAppForFileType(fileType);
    return association?.appName ?? 'System Default';
  }

  /// Launch firmware flashing tool for a device
  ///
  /// For ESP32 devices, this will launch a terminal with esptool command.
  /// For other devices, it will open the binary file in the default application.
  ///
  /// [deviceType] - The device type being flashed
  /// [firmware] - The firmware version to flash
  ///
  /// Returns a [FileLaunchResult] indicating success or failure
  Future<FileLaunchResult> launchFirmwareFlashTool({
    required deviceType,
    required firmware,
  }) async {
    try {
      if (!isFileLaunchingAvailable()) {
        return FileLaunchResult.failure(
          'Firmware flashing is only supported on desktop platforms',
        );
      }

      AppLogger.info(
          'Launching firmware flash tool for ${deviceType.name}: ${firmware.version}');

      // Download firmware binary to temp directory
      final tempDir = Directory.systemTemp;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = firmware.binaryFilename ?? 'firmware_${firmware.version}.bin';
      final uniqueFileName = '${timestamp}_$fileName';
      final filePath = path.join(tempDir.path, uniqueFileName);

      AppLogger.info('Downloading firmware from Supabase storage');

      // Download the firmware binary using Supabase client
      final supabase = Supabase.instance.client;

      // Extract storage path from URL
      String storagePath = firmware.binaryUrl;
      if (storagePath.contains('storage/v1/object/public/firmware-binaries/')) {
        storagePath = storagePath.split('storage/v1/object/public/firmware-binaries/').last;
      }

      final bytes = await supabase.storage
          .from('firmware-binaries')
          .download(storagePath);

      AppLogger.info('Downloaded ${bytes.length} bytes');

      // Write to temp file
      final file = File(filePath);
      await file.writeAsBytes(bytes);

      AppLogger.info('Firmware saved to: $filePath');

      // Check if device is ESP32 (could be enhanced to check device type name)
      final isESP32 = deviceType.name.toUpperCase().contains('ESP32');

      if (isESP32) {
        // For ESP32, launch terminal with esptool instructions
        return await _launchESP32FlashTool(filePath, deviceType.name);
      } else {
        // For other devices, just open the file
        AppLogger.info('Opening firmware file in default application');
        return await openInDefaultApp(filePath);
      }
    } catch (e, stackTrace) {
      AppLogger.error('Error launching firmware flash tool', e, stackTrace);
      return FileLaunchResult.failure(
        'Failed to launch flashing tool: ${e.toString()}',
      );
    }
  }

  /// Launch ESP32 flashing tool with esptool command
  Future<FileLaunchResult> _launchESP32FlashTool(
      String firmwarePath, String deviceName) async {
    try {
      // Create a script with esptool command and instructions
      final tempDir = Directory.systemTemp;
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      String scriptPath;
      String scriptContent;

      if (Platform.isMacOS || Platform.isLinux) {
        // Create bash script
        scriptPath = path.join(tempDir.path, '${timestamp}_flash_esp32.sh');
        scriptContent = '''#!/bin/bash
echo "========================================"
echo "ESP32 Firmware Flashing Tool"
echo "========================================"
echo ""
echo "Device: $deviceName"
echo "Firmware: $firmwarePath"
echo ""
echo "Instructions:"
echo "1. Connect your ESP32 device via USB"
echo "2. Identify the serial port (usually /dev/tty.usbserial* or /dev/cu.usbserial*)"
echo "3. Run the following command:"
echo ""
echo "   esptool.py --chip esp32 --port /dev/tty.SLAB_USBtoUART write_flash 0x10000 \\"$firmwarePath\\""
echo ""
echo "4. Replace /dev/tty.SLAB_USBtoUART with your actual port"
echo ""
echo "If you don't have esptool installed, run:"
echo "   pip install esptool"
echo ""
echo "========================================"
echo ""
read -p "Press Enter to close this window..."
''';

        final scriptFile = File(scriptPath);
        await scriptFile.writeAsString(scriptContent);
        await Process.run('chmod', ['+x', scriptPath]);

        // Launch terminal with script
        if (Platform.isMacOS) {
          await Process.run('open', ['-a', 'Terminal', scriptPath]);
        } else {
          // Linux - try common terminal emulators
          try {
            await Process.run('gnome-terminal', ['--', scriptPath]);
          } catch (_) {
            try {
              await Process.run('xterm', ['-e', scriptPath]);
            } catch (_) {
              return FileLaunchResult.failure(
                'No terminal emulator found',
                suggestion:
                    'Please install gnome-terminal or xterm to flash firmware',
              );
            }
          }
        }
      } else if (Platform.isWindows) {
        // Create batch script
        scriptPath = path.join(tempDir.path, '${timestamp}_flash_esp32.bat');
        scriptContent = '''@echo off
echo ========================================
echo ESP32 Firmware Flashing Tool
echo ========================================
echo.
echo Device: $deviceName
echo Firmware: $firmwarePath
echo.
echo Instructions:
echo 1. Connect your ESP32 device via USB
echo 2. Identify the serial port (usually COM3, COM4, etc.)
echo 3. Run the following command:
echo.
echo    esptool.py --chip esp32 --port COM3 write_flash 0x10000 "$firmwarePath"
echo.
echo 4. Replace COM3 with your actual port
echo.
echo If you don't have esptool installed, run:
echo    pip install esptool
echo.
echo ========================================
echo.
pause
''';

        final scriptFile = File(scriptPath);
        await scriptFile.writeAsString(scriptContent);

        // Launch command prompt with script
        await Process.run('cmd', ['/c', 'start', 'cmd', '/k', scriptPath]);
      }

      AppLogger.info('ESP32 flash tool launched successfully');
      return FileLaunchResult.success();
    } catch (e, stackTrace) {
      AppLogger.error('Error launching ESP32 flash tool', e, stackTrace);
      return FileLaunchResult.failure(
        'Failed to launch ESP32 flash tool: ${e.toString()}',
      );
    }
  }
}
