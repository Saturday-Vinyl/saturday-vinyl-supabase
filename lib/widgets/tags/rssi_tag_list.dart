import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/providers/roll_write_provider.dart';

/// Displays a list of detected RFID tags sorted by signal strength (RSSI)
///
/// Tags are shown with:
/// - Signal strength indicator bar
/// - RSSI value and percentage
/// - Tag status (Saturday tag vs unwritten)
/// - Visual highlight for the active (strongest unwritten) tag
class RssiTagList extends ConsumerWidget {
  /// Optional callback when a tag is tapped
  final void Function(DetectedTag tag)? onTagTap;

  const RssiTagList({super.key, this.onTagTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rollWriteState = ref.watch(rollWriteProvider);
    final detectedTags = rollWriteState.detectedTags;
    final activeTag = rollWriteState.activeTag;

    if (detectedTags.isEmpty) {
      return _buildEmptyState(rollWriteState.isScanning);
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: detectedTags.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final tag = detectedTags[index];
        final isActive = activeTag != null && tag.epcHex == activeTag.epcHex;
        return RssiTagCard(
          tag: tag,
          isActive: isActive,
          onTap: onTagTap != null ? () => onTagTap!(tag) : null,
        );
      },
    );
  }

  Widget _buildEmptyState(bool isScanning) {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isScanning ? Icons.sensors : Icons.sensors_off,
            size: 48,
            color: SaturdayColors.secondaryGrey,
          ),
          const SizedBox(height: 16),
          Text(
            isScanning ? 'Searching for tags...' : 'No tags detected',
            style: TextStyle(
              fontSize: 16,
              color: SaturdayColors.secondaryGrey,
            ),
          ),
          if (isScanning) ...[
            const SizedBox(height: 8),
            Text(
              'Move the reader closer to the roll',
              style: TextStyle(
                fontSize: 14,
                color: SaturdayColors.secondaryGrey.withValues(alpha: 0.7),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Individual card displaying a detected tag with RSSI visualization
class RssiTagCard extends StatelessWidget {
  final DetectedTag tag;
  final bool isActive;
  final VoidCallback? onTap;

  const RssiTagCard({
    super.key,
    required this.tag,
    this.isActive = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Determine colors based on tag status
    final Color accentColor;
    final Color backgroundColor;
    final IconData statusIcon;
    final String statusLabel;

    if (tag.isSaturdayTag) {
      // Already a Saturday tag
      accentColor = SaturdayColors.success;
      backgroundColor = isActive
          ? SaturdayColors.success.withValues(alpha: 0.15)
          : SaturdayColors.success.withValues(alpha: 0.05);
      statusIcon = Icons.check_circle;
      statusLabel = tag.isInDatabase ? 'Written' : 'Saturday Tag';
    } else {
      // Unwritten tag - candidate for writing
      accentColor = isActive ? SaturdayColors.info : SaturdayColors.secondaryGrey;
      backgroundColor = isActive
          ? SaturdayColors.info.withValues(alpha: 0.15)
          : Colors.white;
      statusIcon = Icons.radio_button_unchecked;
      statusLabel = 'Unwritten';
    }

    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive ? accentColor : Colors.transparent,
              width: isActive ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row: Active badge + Status
              Row(
                children: [
                  if (isActive) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: SaturdayColors.info,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'ACTIVE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Icon(statusIcon, size: 16, color: accentColor),
                  const SizedBox(width: 4),
                  Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 12,
                      color: accentColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  // RSSI value
                  Text(
                    '${tag.rssi} dBm',
                    style: TextStyle(
                      fontSize: 12,
                      color: SaturdayColors.secondaryGrey,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // EPC display
              Text(
                tag.formattedEpc,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                  color: SaturdayColors.primaryDark,
                ),
              ),

              const SizedBox(height: 12),

              // Signal strength bar
              RssiStrengthBar(
                strength: tag.signalStrength,
                accentColor: accentColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Visual bar showing signal strength as a percentage
class RssiStrengthBar extends StatelessWidget {
  final int strength; // 0-100
  final Color? accentColor;
  final double height;

  const RssiStrengthBar({
    super.key,
    required this.strength,
    this.accentColor,
    this.height = 8,
  });

  @override
  Widget build(BuildContext context) {
    // Determine bar color based on signal strength
    final Color barColor = accentColor ?? _getStrengthColor(strength);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              _getStrengthIcon(strength),
              size: 14,
              color: barColor,
            ),
            const SizedBox(width: 4),
            Text(
              'Signal: $strength%',
              style: TextStyle(
                fontSize: 11,
                color: SaturdayColors.secondaryGrey,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(height / 2),
          child: Stack(
            children: [
              // Background
              Container(
                height: height,
                width: double.infinity,
                color: SaturdayColors.light,
              ),
              // Filled portion
              LayoutBuilder(
                builder: (context, constraints) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    height: height,
                    width: constraints.maxWidth * (strength / 100),
                    decoration: BoxDecoration(
                      color: barColor,
                      borderRadius: BorderRadius.circular(height / 2),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Color _getStrengthColor(int strength) {
    if (strength >= 70) return SaturdayColors.success;
    if (strength >= 40) return SaturdayColors.info;
    return SaturdayColors.error;
  }

  IconData _getStrengthIcon(int strength) {
    if (strength >= 70) return Icons.signal_cellular_alt;
    if (strength >= 40) return Icons.signal_cellular_alt_2_bar;
    return Icons.signal_cellular_alt_1_bar;
  }
}

/// Compact RSSI indicator for use in small spaces
class RssiIndicator extends StatelessWidget {
  final int strength;
  final int rssi;

  const RssiIndicator({
    super.key,
    required this.strength,
    required this.rssi,
  });

  @override
  Widget build(BuildContext context) {
    final color = _getStrengthColor(strength);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          _getStrengthIcon(strength),
          size: 16,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          '$strength%',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }

  Color _getStrengthColor(int strength) {
    if (strength >= 70) return SaturdayColors.success;
    if (strength >= 40) return SaturdayColors.info;
    return SaturdayColors.error;
  }

  IconData _getStrengthIcon(int strength) {
    if (strength >= 70) return Icons.signal_cellular_alt;
    if (strength >= 40) return Icons.signal_cellular_alt_2_bar;
    return Icons.signal_cellular_alt_1_bar;
  }
}
