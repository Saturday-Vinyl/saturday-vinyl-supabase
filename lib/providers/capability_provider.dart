import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/models/capability.dart';
import 'package:saturday_app/repositories/capability_repository.dart';

/// Provider for CapabilityRepository singleton
final capabilityRepositoryProvider = Provider<CapabilityRepository>((ref) {
  return CapabilityRepository();
});

/// Provider for all capabilities
final allCapabilitiesProvider = FutureProvider<List<Capability>>((ref) async {
  final repository = ref.watch(capabilityRepositoryProvider);
  return repository.getAllCapabilities();
});

/// Provider for active capabilities only
final activeCapabilitiesProvider = FutureProvider<List<Capability>>((ref) async {
  final repository = ref.watch(capabilityRepositoryProvider);
  return repository.getActiveCapabilities();
});

/// Provider for a single capability by ID
final capabilityByIdProvider =
    FutureProvider.family<Capability, String>((ref, id) async {
  final repository = ref.watch(capabilityRepositoryProvider);
  return repository.getCapabilityById(id);
});

/// Provider for a single capability by name
final capabilityByNameProvider =
    FutureProvider.family<Capability?, String>((ref, name) async {
  final repository = ref.watch(capabilityRepositoryProvider);
  return repository.getCapabilityByName(name);
});

/// Provider for capabilities of a device type
final capabilitiesForDeviceTypeProvider =
    FutureProvider.family<List<Capability>, String>((ref, deviceTypeId) async {
  final repository = ref.watch(capabilityRepositoryProvider);
  return repository.getCapabilitiesForDeviceType(deviceTypeId);
});

/// Provider for factory input schema of a device type
final factoryInputSchemaForDeviceTypeProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, deviceTypeId) async {
  final repository = ref.watch(capabilityRepositoryProvider);
  return repository.getFactoryInputSchemaForDeviceType(deviceTypeId);
});

/// Provider for factory output schema of a device type
final factoryOutputSchemaForDeviceTypeProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, deviceTypeId) async {
  final repository = ref.watch(capabilityRepositoryProvider);
  return repository.getFactoryOutputSchemaForDeviceType(deviceTypeId);
});

/// Provider for consumer input schema of a device type
final consumerInputSchemaForDeviceTypeProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, deviceTypeId) async {
  final repository = ref.watch(capabilityRepositoryProvider);
  return repository.getConsumerInputSchemaForDeviceType(deviceTypeId);
});

/// Provider for consumer output schema of a device type
final consumerOutputSchemaForDeviceTypeProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, deviceTypeId) async {
  final repository = ref.watch(capabilityRepositoryProvider);
  return repository.getConsumerOutputSchemaForDeviceType(deviceTypeId);
});

/// Provider for heartbeat schema of a device type
final heartbeatSchemaForDeviceTypeProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, deviceTypeId) async {
  final repository = ref.watch(capabilityRepositoryProvider);
  return repository.getHeartbeatSchemaForDeviceType(deviceTypeId);
});

/// Provider for tests available for a device type
final testsForDeviceTypeProvider =
    FutureProvider.family<List<CapabilityTest>, String>((ref, deviceTypeId) async {
  final repository = ref.watch(capabilityRepositoryProvider);
  return repository.getTestsForDeviceType(deviceTypeId);
});

/// Provider for capability management actions
final capabilityManagementProvider = Provider<CapabilityManagement>((ref) {
  return CapabilityManagement(ref);
});

/// Class for managing capability actions
class CapabilityManagement {
  final Ref ref;

  CapabilityManagement(this.ref);

  /// Create a new capability
  Future<Capability> createCapability(Capability capability) async {
    final repository = ref.read(capabilityRepositoryProvider);
    final created = await repository.createCapability(capability);

    ref.invalidate(allCapabilitiesProvider);
    ref.invalidate(activeCapabilitiesProvider);

    return created;
  }

  /// Update a capability
  Future<Capability> updateCapability(Capability capability) async {
    final repository = ref.read(capabilityRepositoryProvider);
    final updated = await repository.updateCapability(capability);

    ref.invalidate(capabilityByIdProvider(capability.id));
    ref.invalidate(capabilityByNameProvider(capability.name));
    ref.invalidate(allCapabilitiesProvider);
    ref.invalidate(activeCapabilitiesProvider);

    return updated;
  }

  /// Activate a capability
  Future<Capability> activateCapability(String id) async {
    final repository = ref.read(capabilityRepositoryProvider);
    final capability = await repository.activateCapability(id);

    ref.invalidate(capabilityByIdProvider(id));
    ref.invalidate(allCapabilitiesProvider);
    ref.invalidate(activeCapabilitiesProvider);

    return capability;
  }

  /// Deactivate a capability
  Future<Capability> deactivateCapability(String id) async {
    final repository = ref.read(capabilityRepositoryProvider);
    final capability = await repository.deactivateCapability(id);

    ref.invalidate(capabilityByIdProvider(id));
    ref.invalidate(allCapabilitiesProvider);
    ref.invalidate(activeCapabilitiesProvider);

    return capability;
  }

  /// Assign capability to device type
  Future<void> assignToDeviceType({
    required String deviceTypeId,
    required String capabilityId,
  }) async {
    final repository = ref.read(capabilityRepositoryProvider);
    await repository.assignCapabilityToDeviceType(
      deviceTypeId: deviceTypeId,
      capabilityId: capabilityId,
    );

    ref.invalidate(capabilitiesForDeviceTypeProvider(deviceTypeId));
    ref.invalidate(factoryInputSchemaForDeviceTypeProvider(deviceTypeId));
    ref.invalidate(factoryOutputSchemaForDeviceTypeProvider(deviceTypeId));
    ref.invalidate(consumerInputSchemaForDeviceTypeProvider(deviceTypeId));
    ref.invalidate(consumerOutputSchemaForDeviceTypeProvider(deviceTypeId));
    ref.invalidate(heartbeatSchemaForDeviceTypeProvider(deviceTypeId));
    ref.invalidate(testsForDeviceTypeProvider(deviceTypeId));
  }

  /// Remove capability from device type
  Future<void> removeFromDeviceType({
    required String deviceTypeId,
    required String capabilityId,
  }) async {
    final repository = ref.read(capabilityRepositoryProvider);
    await repository.removeCapabilityFromDeviceType(
      deviceTypeId: deviceTypeId,
      capabilityId: capabilityId,
    );

    ref.invalidate(capabilitiesForDeviceTypeProvider(deviceTypeId));
    ref.invalidate(factoryInputSchemaForDeviceTypeProvider(deviceTypeId));
    ref.invalidate(factoryOutputSchemaForDeviceTypeProvider(deviceTypeId));
    ref.invalidate(consumerInputSchemaForDeviceTypeProvider(deviceTypeId));
    ref.invalidate(consumerOutputSchemaForDeviceTypeProvider(deviceTypeId));
    ref.invalidate(heartbeatSchemaForDeviceTypeProvider(deviceTypeId));
    ref.invalidate(testsForDeviceTypeProvider(deviceTypeId));
  }

  /// Set all capabilities for a device type (replace existing)
  Future<void> setCapabilitiesForDeviceType({
    required String deviceTypeId,
    required List<String> capabilityIds,
  }) async {
    final repository = ref.read(capabilityRepositoryProvider);
    await repository.setCapabilitiesForDeviceType(
      deviceTypeId: deviceTypeId,
      capabilityIds: capabilityIds,
    );

    ref.invalidate(capabilitiesForDeviceTypeProvider(deviceTypeId));
    ref.invalidate(factoryInputSchemaForDeviceTypeProvider(deviceTypeId));
    ref.invalidate(factoryOutputSchemaForDeviceTypeProvider(deviceTypeId));
    ref.invalidate(consumerInputSchemaForDeviceTypeProvider(deviceTypeId));
    ref.invalidate(consumerOutputSchemaForDeviceTypeProvider(deviceTypeId));
    ref.invalidate(heartbeatSchemaForDeviceTypeProvider(deviceTypeId));
    ref.invalidate(testsForDeviceTypeProvider(deviceTypeId));
  }

  /// Delete a capability
  Future<void> deleteCapability(String id) async {
    final repository = ref.read(capabilityRepositoryProvider);
    await repository.deleteCapability(id);

    ref.invalidate(capabilityByIdProvider(id));
    ref.invalidate(allCapabilitiesProvider);
    ref.invalidate(activeCapabilitiesProvider);
  }
}
