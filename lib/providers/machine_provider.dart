import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saturday_app/services/machine_connection_service.dart';
import 'package:saturday_app/services/gcode_streaming_service.dart';
import 'package:saturday_app/services/machine_config_storage.dart';
import 'package:saturday_app/services/github_service.dart';

/// Provider for SharedPreferences
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences must be overridden in main.dart');
});

/// Provider for MachineConfigStorage
final machineConfigStorageProvider = Provider<MachineConfigStorage>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return MachineConfigStorage(prefs);
});

/// Provider for CNC Machine Connection Service
final cncMachineServiceProvider = Provider<MachineConnectionService>((ref) {
  return MachineConnectionService();
});

/// Provider for Laser Machine Connection Service
final laserMachineServiceProvider = Provider<MachineConnectionService>((ref) {
  return MachineConnectionService();
});

/// Provider for CNC gCode Streaming Service
final cncStreamingServiceProvider = Provider<GCodeStreamingService>((ref) {
  final machineService = ref.watch(cncMachineServiceProvider);
  return GCodeStreamingService(machineService);
});

/// Provider for Laser gCode Streaming Service
final laserStreamingServiceProvider = Provider<GCodeStreamingService>((ref) {
  final machineService = ref.watch(laserMachineServiceProvider);
  return GCodeStreamingService(machineService);
});

/// Provider for GitHub Service (kept for future use)
final githubServiceProvider = Provider<GitHubService>((ref) {
  return GitHubService();
});
