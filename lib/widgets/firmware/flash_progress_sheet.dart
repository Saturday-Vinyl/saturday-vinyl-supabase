import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/device_type.dart';
import 'package:saturday_app/models/firmware.dart';
import 'package:saturday_app/repositories/firmware_repository.dart';
import 'package:saturday_app/services/esp_flash_service.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// Result returned when the flash progress sheet completes
class FlashSheetResult {
  final bool success;
  final String? macAddress;

  const FlashSheetResult({required this.success, this.macAddress});
}

/// Bottom sheet that manages the firmware flash process with real-time logs
///
/// Handles port selection, downloading firmware binaries, flashing via esptool,
/// and displaying real-time output. Supports multi-SoC devices by flashing
/// all binaries in a single esptool invocation.
class FlashProgressSheet extends StatefulWidget {
  final DeviceType deviceType;
  final Firmware firmware;
  final FirmwareRepository firmwareRepository;

  /// Pre-selected port (e.g., from USB monitor)
  final String? initialPort;

  const FlashProgressSheet({
    super.key,
    required this.deviceType,
    required this.firmware,
    required this.firmwareRepository,
    this.initialPort,
  });

  /// Show the flash progress sheet as a modal bottom sheet
  static Future<FlashSheetResult?> show({
    required BuildContext context,
    required DeviceType deviceType,
    required Firmware firmware,
    required FirmwareRepository firmwareRepository,
    String? initialPort,
  }) {
    return showModalBottomSheet<FlashSheetResult>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      builder: (context) => FlashProgressSheet(
        deviceType: deviceType,
        firmware: firmware,
        firmwareRepository: firmwareRepository,
        initialPort: initialPort,
      ),
    );
  }

  @override
  State<FlashProgressSheet> createState() => _FlashProgressSheetState();
}

enum _FlashPhase { portSelection, downloading, flashing, success, failed }

class _FlashProgressSheetState extends State<FlashProgressSheet> {
  final _espFlashService = EspFlashService();
  final _logLines = <String>[];
  final _scrollController = ScrollController();

  StreamSubscription<String>? _logSubscription;

  _FlashPhase _phase = _FlashPhase.portSelection;
  String? _selectedPort;
  List<String> _availablePorts = [];
  String? _errorMessage;
  String? _macAddress;
  bool _esptoolAvailable = false;

  @override
  void initState() {
    super.initState();
    _selectedPort = widget.initialPort;
    _checkEsptool();
    _refreshPorts();

    _logSubscription = _espFlashService.logStream.listen((line) {
      if (mounted) {
        setState(() {
          _logLines.add(line);
        });
        _scrollToBottom();
      }
    });
  }

  @override
  void dispose() {
    _logSubscription?.cancel();
    _espFlashService.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _checkEsptool() async {
    final available = await _espFlashService.isEsptoolAvailable();
    if (mounted) {
      setState(() {
        _esptoolAvailable = available;
      });
    }
  }

  void _refreshPorts() {
    final ports = _espFlashService.getAvailablePorts();
    if (mounted) {
      setState(() {
        _availablePorts = ports;
        // If initial port is not in list, clear it
        if (_selectedPort != null && !ports.contains(_selectedPort)) {
          _selectedPort = ports.isNotEmpty ? ports.first : null;
        }
        // Auto-select first port if none selected
        if (_selectedPort == null && ports.isNotEmpty) {
          _selectedPort = ports.first;
        }
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _startFlash() async {
    if (_selectedPort == null) return;

    setState(() {
      _phase = _FlashPhase.downloading;
      _logLines.clear();
      _errorMessage = null;
    });

    try {
      // Determine which files to flash
      final files = widget.firmware.files;
      final List<FlashTarget> targets = [];

      if (files.isNotEmpty) {
        // Multi-SoC firmware: download each file and create flash targets
        for (final firmwareFile in files) {
          _logLines.add('[INFO] Downloading ${firmwareFile.socType.toUpperCase()} binary...');
          setState(() {});

          final localFile =
              await widget.firmwareRepository.downloadFirmwareFile(firmwareFile);

          targets.add(FlashTarget(
            binaryPath: localFile.path,
            flashOffset: firmwareFile.flashOffset,
            label:
                '${firmwareFile.isMaster ? "Master" : "Secondary"} (${firmwareFile.socType.toUpperCase()})',
          ));
        }
      } else if (widget.firmware.binaryUrl != null) {
        // Legacy single-file firmware
        _logLines.add('[INFO] Downloading firmware binary...');
        setState(() {});

        final localFile = await widget.firmwareRepository
            .downloadFirmwareBinary(widget.firmware.id);

        targets.add(FlashTarget(
          binaryPath: localFile.path,
          flashOffset: 0,
          label: 'Firmware ${widget.firmware.version}',
        ));
      } else {
        throw Exception('No firmware files available to flash');
      }

      if (!mounted) return;

      setState(() {
        _phase = _FlashPhase.flashing;
      });

      // Flash using the master SoC's chip type
      final chipType = widget.deviceType.effectiveMasterSoc ?? 'esp32';

      final result = await _espFlashService.flashMultipleFirmware(
        targets: targets,
        port: _selectedPort!,
        chipType: chipType,
      );

      if (!mounted) return;

      if (result.success) {
        setState(() {
          _phase = _FlashPhase.success;
          _macAddress = result.macAddress;
        });
      } else {
        setState(() {
          _phase = _FlashPhase.failed;
          _errorMessage = result.errorMessage;
        });
      }

      // Clean up downloaded files
      for (final target in targets) {
        try {
          await File(target.binaryPath).delete();
        } catch (_) {}
      }
    } catch (e, stackTrace) {
      AppLogger.error('Flash process failed', e, stackTrace);
      if (mounted) {
        setState(() {
          _phase = _FlashPhase.failed;
          _errorMessage = e.toString();
          _logLines.add('[ERROR] $e');
        });
      }
    }
  }

  void _cancel() {
    if (_phase == _FlashPhase.flashing) {
      _espFlashService.cancel();
    }
    Navigator.of(context).pop(null);
  }

  void _finish(bool success) {
    Navigator.of(context).pop(FlashSheetResult(
      success: success,
      macAddress: _macAddress,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.flash_on, color: SaturdayColors.primaryDark),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Flash Firmware',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      '${widget.deviceType.name} - v${widget.firmware.version}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: SaturdayColors.secondaryGrey,
                          ),
                    ),
                  ],
                ),
              ),
              if (_phase == _FlashPhase.portSelection ||
                  _phase == _FlashPhase.success ||
                  _phase == _FlashPhase.failed)
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => _phase == _FlashPhase.success
                      ? _finish(true)
                      : _cancel(),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Multi-SoC info
          if (widget.firmware.isMultiSoc) ...[
            Card(
              color: SaturdayColors.info.withValues(alpha: 0.1),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 16, color: SaturdayColors.info),
                        SizedBox(width: 8),
                        Text(
                          'Multi-SoC Flash',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: SaturdayColors.info,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...widget.firmware.files.map((f) => Padding(
                          padding: const EdgeInsets.only(left: 24, bottom: 4),
                          child: Text(
                            '${f.isMaster ? "Master" : "Secondary"} ${f.socType.toUpperCase()} '
                            '@ 0x${f.flashOffset.toRadixString(16).toUpperCase()} '
                            '(${f.formattedSize})',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        )),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Port selection
          if (_phase == _FlashPhase.portSelection) ...[
            if (!_esptoolAvailable) ...[
              Card(
                color: SaturdayColors.error.withValues(alpha: 0.1),
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: SaturdayColors.error),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'esptool not found. Install via: pip install esptool',
                          style: TextStyle(color: SaturdayColors.error),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedPort,
                    decoration: const InputDecoration(
                      labelText: 'Serial Port',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: _availablePorts
                        .map((port) => DropdownMenuItem(
                              value: port,
                              child: Text(port, overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedPort = value;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _refreshPorts,
                  tooltip: 'Refresh ports',
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _cancel,
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _selectedPort != null && _esptoolAvailable
                      ? _startFlash
                      : null,
                  icon: const Icon(Icons.flash_on),
                  label: const Text('Flash'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SaturdayColors.primaryDark,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],

          // Status indicator
          if (_phase == _FlashPhase.downloading) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            const Text('Downloading firmware binaries...'),
          ],
          if (_phase == _FlashPhase.flashing) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            const Text('Flashing firmware via esptool...'),
          ],

          // Log viewer
          if (_logLines.isNotEmpty) ...[
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount: _logLines.length,
                  itemBuilder: (context, index) {
                    final line = _logLines[index];
                    Color textColor = Colors.white70;
                    if (line.startsWith('[ERROR]') || line.startsWith('[ERR]')) {
                      textColor = SaturdayColors.error;
                    } else if (line.startsWith('[SUCCESS]')) {
                      textColor = SaturdayColors.success;
                    } else if (line.startsWith('[INFO]')) {
                      textColor = SaturdayColors.info;
                    } else if (line.startsWith('[CMD]')) {
                      textColor = Colors.amber;
                    }
                    return Text(
                      line,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: textColor,
                      ),
                    );
                  },
                ),
              ),
            ),
          ],

          // Result actions
          if (_phase == _FlashPhase.success) ...[
            const SizedBox(height: 16),
            Card(
              color: SaturdayColors.success.withValues(alpha: 0.1),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Icon(Icons.check_circle,
                        color: SaturdayColors.success, size: 48),
                    const SizedBox(height: 8),
                    const Text(
                      'Firmware flashed successfully!',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: SaturdayColors.success,
                      ),
                    ),
                    if (_macAddress != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'MAC: $_macAddress',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => _finish(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: SaturdayColors.success,
                foregroundColor: Colors.white,
              ),
              child: const Text('Done'),
            ),
          ],
          if (_phase == _FlashPhase.failed) ...[
            const SizedBox(height: 16),
            Card(
              color: SaturdayColors.error.withValues(alpha: 0.1),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Icon(Icons.error,
                        color: SaturdayColors.error, size: 48),
                    const SizedBox(height: 8),
                    Text(
                      _errorMessage ?? 'Flashing failed',
                      style: const TextStyle(color: SaturdayColors.error),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _finish(false),
                  child: const Text('Close'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _phase = _FlashPhase.portSelection;
                      _logLines.clear();
                      _errorMessage = null;
                    });
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ],

          // Cancel button during flash
          if (_phase == _FlashPhase.flashing ||
              _phase == _FlashPhase.downloading) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: _cancel,
              child: const Text('Cancel'),
            ),
          ],
        ],
      ),
    );
  }
}
