import 'package:saturday_app/models/production_unit.dart';

/// ProductionUnit with consumer device association info
///
/// Used in the provisioning flow to show warnings when a unit
/// has already been linked to a consumer device.
class ProductionUnitWithConsumerInfo {
  final ProductionUnit unit;
  final bool hasConsumerDevice;
  final String? consumerDeviceId;

  const ProductionUnitWithConsumerInfo({
    required this.unit,
    required this.hasConsumerDevice,
    this.consumerDeviceId,
  });

  /// Create from JSON response with consumer_devices join data
  factory ProductionUnitWithConsumerInfo.fromJson(Map<String, dynamic> json) {
    final consumerDevices = json['consumer_devices'] as List?;
    final hasConsumer = consumerDevices != null && consumerDevices.isNotEmpty;
    final consumerId =
        hasConsumer ? consumerDevices.first['id'] as String? : null;

    // Remove the consumer_devices key before parsing ProductionUnit
    final unitJson = Map<String, dynamic>.from(json);
    unitJson.remove('consumer_devices');

    return ProductionUnitWithConsumerInfo(
      unit: ProductionUnit.fromJson(unitJson),
      hasConsumerDevice: hasConsumer,
      consumerDeviceId: consumerId,
    );
  }
}
