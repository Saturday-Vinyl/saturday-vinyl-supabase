import 'package:flutter/material.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/service_mode_state.dart';

/// Card displaying device information from beacon or status
class DeviceInfoCard extends StatelessWidget {
  final DeviceInfo? deviceInfo;
  final bool isInServiceMode;

  const DeviceInfoCard({
    super.key,
    this.deviceInfo,
    this.isInServiceMode = false,
  });

  @override
  Widget build(BuildContext context) {
    if (deviceInfo == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.device_unknown, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Device Info',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Waiting for device...',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    final info = deviceInfo!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _getDeviceIcon(info.deviceType),
                  size: 20,
                  color: SaturdayColors.info,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Device Info',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                if (isInServiceMode)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: SaturdayColors.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: SaturdayColors.success),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.build,
                          size: 12,
                          color: SaturdayColors.success,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'SERVICE MODE',
                          style: TextStyle(
                            color: SaturdayColors.success,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const Divider(height: 24),

            // Device type and firmware
            _buildInfoRow(
              context,
              'Type',
              _formatDeviceType(info.deviceType),
              Icons.devices,
            ),
            _buildInfoRow(
              context,
              'Firmware',
              'v${info.firmwareVersion}',
              Icons.memory,
            ),
            if (info.firmwareId != null)
              _buildInfoRow(
                context,
                'Firmware ID',
                info.firmwareId!.substring(0, 8) + '...',
                Icons.fingerprint,
                tooltip: info.firmwareId,
              ),
            _buildInfoRow(
              context,
              'MAC Address',
              info.macAddress.isNotEmpty ? info.macAddress : 'Unknown',
              Icons.router,
            ),

            // Unit ID (if provisioned)
            if (info.isProvisioned) ...[
              _buildInfoRow(
                context,
                'Unit ID',
                info.unitId!,
                Icons.qr_code,
                valueColor: SaturdayColors.success,
              ),
            ] else ...[
              _buildInfoRow(
                context,
                'Status',
                'Not Provisioned',
                Icons.warning_amber,
                valueColor: Colors.orange,
              ),
            ],

            // Connectivity status
            if (info.wifiConfigured || info.cloudConfigured) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (info.wifiConfigured)
                    _buildStatusChip(
                      info.wifiConnected ? 'Wi-Fi Connected' : 'Wi-Fi Configured',
                      info.wifiConnected ? Icons.wifi : Icons.wifi_off,
                      info.wifiConnected
                          ? SaturdayColors.success
                          : Colors.orange,
                    ),
                  if (info.cloudConfigured)
                    _buildStatusChip(
                      'Cloud Configured',
                      Icons.cloud_done,
                      SaturdayColors.info,
                    ),
                  if (info.bluetoothEnabled == true)
                    _buildStatusChip(
                      'Bluetooth',
                      Icons.bluetooth,
                      SaturdayColors.info,
                    ),
                ],
              ),
            ],

            // System info
            if (info.freeHeap != null || info.uptimeMs != null) ...[
              const Divider(height: 24),
              Row(
                children: [
                  if (info.uptimeMs != null)
                    Expanded(
                      child: _buildMiniInfo(
                        'Uptime',
                        info.formattedUptime,
                        Icons.timer,
                      ),
                    ),
                  if (info.freeHeap != null)
                    Expanded(
                      child: _buildMiniInfo(
                        'Free Heap',
                        info.formattedFreeHeap,
                        Icons.memory,
                      ),
                    ),
                  if (info.batteryLevel != null)
                    Expanded(
                      child: _buildMiniInfo(
                        'Battery',
                        '${info.batteryLevel}%${info.batteryCharging == true ? ' (charging)' : ''}',
                        _getBatteryIcon(info.batteryLevel!, info.batteryCharging ?? false),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context,
    String label,
    String value,
    IconData icon, {
    Color? valueColor,
    String? tooltip,
  }) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );

    if (tooltip != null) {
      return Tooltip(
        message: tooltip,
        child: content,
      );
    }
    return content;
  }

  Widget _buildStatusChip(String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniInfo(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  IconData _getDeviceIcon(String deviceType) {
    switch (deviceType.toLowerCase()) {
      case 'hub':
        return Icons.hub;
      case 'speaker':
        return Icons.speaker;
      case 'display':
        return Icons.tv;
      default:
        return Icons.devices_other;
    }
  }

  String _formatDeviceType(String deviceType) {
    // Capitalize first letter of each word
    return deviceType.split('_').map((word) {
      if (word.isEmpty) return word;
      return '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
    }).join(' ');
  }

  IconData _getBatteryIcon(int level, bool charging) {
    if (charging) return Icons.battery_charging_full;
    if (level > 80) return Icons.battery_full;
    if (level > 60) return Icons.battery_6_bar;
    if (level > 40) return Icons.battery_4_bar;
    if (level > 20) return Icons.battery_2_bar;
    return Icons.battery_alert;
  }
}
