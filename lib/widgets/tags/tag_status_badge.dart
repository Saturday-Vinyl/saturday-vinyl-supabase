import 'package:flutter/material.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/rfid_tag.dart';

/// Badge widget showing RFID tag status with color coding
class TagStatusBadge extends StatelessWidget {
  final RfidTagStatus status;
  final bool compact;

  const TagStatusBadge({
    super.key,
    required this.status,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = _getStatusColor();
    final text = _getStatusText();

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(compact ? 4 : 6),
        border: Border.all(color: color, width: 1),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: compact ? 10 : 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Color _getStatusColor() {
    switch (status) {
      case RfidTagStatus.generated:
        return SaturdayColors.secondaryGrey;
      case RfidTagStatus.written:
        return SaturdayColors.info;
      case RfidTagStatus.locked:
        return SaturdayColors.success;
      case RfidTagStatus.failed:
        return SaturdayColors.error;
      case RfidTagStatus.retired:
        return const Color(0xFF5C5C5C); // Darker gray
    }
  }

  String _getStatusText() {
    switch (status) {
      case RfidTagStatus.generated:
        return 'Generated';
      case RfidTagStatus.written:
        return 'Written';
      case RfidTagStatus.locked:
        return 'Locked';
      case RfidTagStatus.failed:
        return 'Failed';
      case RfidTagStatus.retired:
        return 'Retired';
    }
  }

  /// Get status color for external use (e.g., icons)
  static Color getColorForStatus(RfidTagStatus status) {
    switch (status) {
      case RfidTagStatus.generated:
        return SaturdayColors.secondaryGrey;
      case RfidTagStatus.written:
        return SaturdayColors.info;
      case RfidTagStatus.locked:
        return SaturdayColors.success;
      case RfidTagStatus.failed:
        return SaturdayColors.error;
      case RfidTagStatus.retired:
        return const Color(0xFF5C5C5C);
    }
  }

  /// Get status icon for external use
  static IconData getIconForStatus(RfidTagStatus status) {
    switch (status) {
      case RfidTagStatus.generated:
        return Icons.auto_awesome;
      case RfidTagStatus.written:
        return Icons.edit_note;
      case RfidTagStatus.locked:
        return Icons.lock;
      case RfidTagStatus.failed:
        return Icons.error_outline;
      case RfidTagStatus.retired:
        return Icons.cancel_outlined;
    }
  }
}
