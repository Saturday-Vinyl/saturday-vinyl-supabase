import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/models/device.dart';
import 'package:saturday_consumer_app/providers/auth_provider.dart';
import 'package:saturday_consumer_app/providers/repository_providers.dart';

/// FutureProvider for all devices owned by the current user.
final userDevicesProvider = FutureProvider<List<Device>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return [];

  final deviceRepo = ref.watch(deviceRepositoryProvider);
  return deviceRepo.getUserDevices(userId);
});

/// FutureProvider.family for fetching a device by ID.
final deviceByIdProvider =
    FutureProvider.family<Device?, String>((ref, deviceId) async {
  final deviceRepo = ref.watch(deviceRepositoryProvider);
  return deviceRepo.getDevice(deviceId);
});

/// Provider for user's hubs only.
final userHubsProvider = FutureProvider<List<Device>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return [];

  final deviceRepo = ref.watch(deviceRepositoryProvider);
  return deviceRepo.getUserHubs(userId);
});

/// Provider for user's crates only.
final userCratesProvider = FutureProvider<List<Device>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return [];

  final deviceRepo = ref.watch(deviceRepositoryProvider);
  return deviceRepo.getUserCrates(userId);
});

/// Provider for the count of user's devices.
final deviceCountProvider = Provider<int>((ref) {
  final devices = ref.watch(userDevicesProvider);
  return devices.whenOrNull(data: (d) => d.length) ?? 0;
});

/// Provider for online devices (using heartbeat-aware connectivity status).
final onlineDevicesProvider = Provider<List<Device>>((ref) {
  final devices = ref.watch(userDevicesProvider);
  return devices.whenOrNull(
        data: (d) => d.where((device) => device.isEffectivelyOnline).toList(),
      ) ??
      [];
});

/// Provider for devices that need setup.
final devicesNeedingSetupProvider = Provider<List<Device>>((ref) {
  final devices = ref.watch(userDevicesProvider);
  return devices.whenOrNull(
        data: (d) => d.where((device) => device.needsSetup).toList(),
      ) ??
      [];
});

/// Provider for devices with low battery.
final lowBatteryDevicesProvider = Provider<List<Device>>((ref) {
  final devices = ref.watch(userDevicesProvider);
  return devices.whenOrNull(
        data: (d) => d.where((device) => device.isLowBattery).toList(),
      ) ??
      [];
});

/// Provider for the primary hub (first online hub, or first hub).
/// Uses heartbeat-aware connectivity status to determine if hub is online.
final primaryHubProvider = Provider<Device?>((ref) {
  final hubs = ref.watch(userHubsProvider);
  return hubs.whenOrNull(
    data: (h) {
      if (h.isEmpty) return null;
      // Prefer effectively online hub (accounts for stale heartbeats)
      final online = h.where((hub) => hub.isEffectivelyOnline).toList();
      if (online.isNotEmpty) return online.first;
      return h.first;
    },
  );
});
