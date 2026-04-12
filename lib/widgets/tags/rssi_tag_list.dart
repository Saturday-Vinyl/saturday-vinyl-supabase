import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/providers/roll_write_provider.dart';

/// Role of a tag in the 3-slot horizontal display
enum TagSlotRole { previous, focus, next }

/// Displays detected RFID tags in a horizontal 3-slot layout matching the
/// physical left-to-right movement of tags across the reader.
///
/// Slots:
/// - Left: previous tag (last written or previously focused)
/// - Center: active/focus tag (strongest unwritten — write candidate)
/// - Right: next tag approaching the reader
class RssiTagList extends ConsumerWidget {
  final void Function(DetectedTag tag)? onTagTap;

  const RssiTagList({super.key, this.onTagTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rollWriteState = ref.watch(rollWriteProvider);
    final previousTag = rollWriteState.previousTag;
    final activeTag = rollWriteState.activeTag;
    final nextTag = rollWriteState.nextTag;

    if (previousTag == null && activeTag == null && nextTag == null) {
      return _buildEmptyState(rollWriteState.isScanning);
    }

    return SizedBox(
      height: 150,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left slot: previous tag
          Expanded(
            child: previousTag != null
                ? Opacity(
                    opacity: 0.5,
                    child: CompactTagCard(
                      key: ValueKey('prev-${previousTag.epcHex}'),
                      tag: previousTag,
                      role: TagSlotRole.previous,
                      onTap: onTagTap != null
                          ? () => onTagTap!(previousTag)
                          : null,
                    ),
                  )
                : const _EmptySlot(),
          ),
          const SizedBox(width: 8),
          // Center slot: focus tag (wider)
          Expanded(
            flex: 2,
            child: activeTag != null
                ? CompactTagCard(
                    key: ValueKey('focus-${activeTag.epcHex}'),
                    tag: activeTag,
                    role: TagSlotRole.focus,
                    onTap: onTagTap != null
                        ? () => onTagTap!(activeTag)
                        : null,
                  )
                : const _EmptySlot(),
          ),
          const SizedBox(width: 8),
          // Right slot: next tag
          Expanded(
            child: nextTag != null
                ? Opacity(
                    opacity: 0.7,
                    child: CompactTagCard(
                      key: ValueKey('next-${nextTag.epcHex}'),
                      tag: nextTag,
                      role: TagSlotRole.next,
                      onTap: onTagTap != null
                          ? () => onTagTap!(nextTag)
                          : null,
                    ),
                  )
                : const _EmptySlot(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isScanning) {
    return SizedBox(
      height: 150,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isScanning ? Icons.sensors : Icons.sensors_off,
              size: 36,
              color: SaturdayColors.secondaryGrey,
            ),
            const SizedBox(height: 12),
            Text(
              isScanning ? 'Searching for tags...' : 'No tags detected',
              style: const TextStyle(
                fontSize: 14,
                color: SaturdayColors.secondaryGrey,
              ),
            ),
            if (isScanning) ...[
              const SizedBox(height: 4),
              Text(
                'Move the reader closer to the roll',
                style: TextStyle(
                  fontSize: 12,
                  color: SaturdayColors.secondaryGrey.withValues(alpha: 0.7),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Compact tag card for horizontal slot layout
class CompactTagCard extends StatelessWidget {
  final DetectedTag tag;
  final TagSlotRole role;
  final VoidCallback? onTap;

  const CompactTagCard({
    super.key,
    required this.tag,
    required this.role,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final (accentColor, backgroundColor, roleLabel) = _roleStyle();

    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(12),
      elevation: role == TagSlotRole.focus ? 2 : 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: role == TagSlotRole.focus
                  ? accentColor
                  : Colors.grey.shade200,
              width: role == TagSlotRole.focus ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Role label
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  roleLabel,
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Status icon
              Icon(
                tag.isSaturdayTag ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 18,
                color: tag.isSaturdayTag ? SaturdayColors.success : accentColor,
              ),
              const SizedBox(height: 6),
              // Truncated EPC (last 8 chars)
              Text(
                _truncatedEpc(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                  color: SaturdayColors.primaryDark,
                ),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              // Signal strength bar
              RssiStrengthBar(
                strength: tag.smoothedSignalStrength,
                accentColor: tag.isSaturdayTag ? SaturdayColors.success : accentColor,
                height: 6,
              ),
              const SizedBox(height: 4),
              // RSSI value
              Text(
                '${tag.smoothedSignalStrength}%',
                style: const TextStyle(
                  fontSize: 10,
                  color: SaturdayColors.secondaryGrey,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  (Color, Color, String) _roleStyle() {
    switch (role) {
      case TagSlotRole.previous:
        return (
          SaturdayColors.secondaryGrey,
          Colors.grey.shade50,
          'PREV',
        );
      case TagSlotRole.focus:
        return (
          SaturdayColors.info,
          SaturdayColors.info.withValues(alpha: 0.08),
          'ACTIVE',
        );
      case TagSlotRole.next:
        return (
          SaturdayColors.secondaryGrey,
          Colors.grey.shade50,
          'NEXT',
        );
    }
  }

  String _truncatedEpc() {
    final epc = tag.formattedEpc;
    if (epc.length <= 9) return epc;
    return '...${epc.substring(epc.length - 9)}';
  }
}

/// Placeholder widget for empty tag slots
class _EmptySlot extends StatelessWidget {
  const _EmptySlot({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey.shade200,
          style: BorderStyle.solid,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.remove,
          size: 20,
          color: Colors.grey.shade300,
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
    final Color barColor = accentColor ?? _getStrengthColor(strength);

    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: Stack(
        children: [
          Container(
            height: height,
            width: double.infinity,
            color: SaturdayColors.light,
          ),
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
    );
  }

  Color _getStrengthColor(int strength) {
    if (strength >= 70) return SaturdayColors.success;
    if (strength >= 40) return SaturdayColors.info;
    return SaturdayColors.error;
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
