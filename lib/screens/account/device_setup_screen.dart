import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/models/device.dart';
import 'package:saturday_consumer_app/providers/auth_provider.dart';
import 'package:saturday_consumer_app/providers/ble_provider.dart';
import 'package:saturday_consumer_app/providers/device_provider.dart';
import 'package:saturday_consumer_app/providers/repository_providers.dart';
import 'package:saturday_consumer_app/services/ble_service.dart';

/// Main screen for setting up a new Saturday device.
class DeviceSetupScreen extends ConsumerStatefulWidget {
  const DeviceSetupScreen({super.key});

  @override
  ConsumerState<DeviceSetupScreen> createState() => _DeviceSetupScreenState();
}

class _DeviceSetupScreenState extends ConsumerState<DeviceSetupScreen> {
  @override
  void initState() {
    super.initState();
    // Check BLE availability on mount
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkBleAndStartScan();
    });
  }

  Future<void> _checkBleAndStartScan() async {
    final notifier = ref.read(deviceSetupProvider.notifier);
    final available = await notifier.checkBleAvailability();
    if (!available && mounted) {
      _showBleError();
    } else {
      // BLE is available, start scanning immediately
      notifier.startScan();
    }
  }

  void _showBleError() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bluetooth Required'),
        content: const Text(
          'Please enable Bluetooth to set up your Saturday device.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.pop();
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _checkBleAndStartScan();
            },
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(deviceSetupProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_getTitle(state.currentStep)),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _confirmExit(context, ref),
        ),
      ),
      body: _buildBody(context, ref, state),
    );
  }

  String _getTitle(SetupStep step) {
    switch (step) {
      case SetupStep.selectType:
        return 'Add Device'; // Legacy, no longer used
      case SetupStep.scanning:
        return 'Searching for Devices';
      case SetupStep.selectDevice:
        return 'Select Device';
      case SetupStep.connecting:
        return 'Connecting...';
      case SetupStep.configure:
        return 'Configure Device';
      case SetupStep.complete:
        return 'Setup Complete';
    }
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, DeviceSetupState state) {
    // Show error if present
    if (state.hasError && state.currentStep != SetupStep.complete) {
      return _buildError(context, ref, state);
    }

    switch (state.currentStep) {
      case SetupStep.selectType:
        // Legacy step - now we go straight to scanning
        // Fall through to scanning
        return const _ScanningStep();
      case SetupStep.scanning:
        return const _ScanningStep();
      case SetupStep.selectDevice:
        return _SelectDeviceStep(
          devices: state.discoveredDevices,
          onSelectDevice: (device) => _onDeviceSelected(ref, device),
          onRescan: () => ref.read(deviceSetupProvider.notifier).startScan(),
        );
      case SetupStep.connecting:
        return const _ConnectingStep();
      case SetupStep.configure:
        return _ConfigureStep(
          deviceInfo: state.deviceInfo!,
          wifiNetworks: state.wifiNetworks,
          provisioningStatus: state.provisioningStatus,
        );
      case SetupStep.complete:
        return _CompleteStep(
          deviceName: state.effectiveDeviceName,
          onDone: () => _onSetupComplete(context, ref),
        );
    }
  }

  Widget _buildError(BuildContext context, WidgetRef ref, DeviceSetupState state) {
    return Center(
      child: Padding(
        padding: Spacing.pagePadding,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: SaturdayColors.error,
            ),
            const SizedBox(height: 24),
            Text(
              'Something went wrong',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              state.errorMessage ?? 'An unknown error occurred',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: SaturdayColors.secondary,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: () => context.pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: () => ref.read(deviceSetupProvider.notifier).retry(),
                  child: const Text('Try Again'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _onDeviceSelected(WidgetRef ref, DiscoveredDevice device) {
    ref.read(deviceSetupProvider.notifier).selectDevice(device);
  }

  Future<void> _onSetupComplete(BuildContext context, WidgetRef ref) async {
    final state = ref.read(deviceSetupProvider);
    final userId = ref.read(currentUserIdProvider);

    if (userId == null) {
      debugPrint('[DeviceSetup] No user ID, cannot save device');
      context.pop();
      return;
    }

    final deviceInfo = state.deviceInfo;
    if (deviceInfo == null) {
      debugPrint('[DeviceSetup] No device info, cannot save device');
      context.pop();
      return;
    }

    // Create and save the device to the database
    try {
      final deviceRepo = ref.read(deviceRepositoryProvider);

      // Use user-defined name or default
      final deviceName = state.effectiveDeviceName;

      final device = Device(
        id: '', // Will be generated by the database
        userId: userId,
        deviceType: deviceInfo.isHub ? DeviceType.hub : DeviceType.crate,
        name: deviceName,
        serialNumber: deviceInfo.unitId,
        firmwareVersion: deviceInfo.firmwareVersion,
        status: DeviceStatus.online,
        lastSeenAt: DateTime.now(),
        createdAt: DateTime.now(),
      );

      await deviceRepo.createDevice(device);
      debugPrint('[DeviceSetup] Device saved successfully: $deviceName');
    } catch (e) {
      debugPrint('[DeviceSetup] Error saving device: $e');
      // Show error but still allow navigation
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Device configured but failed to save: $e')),
        );
      }
    }

    // Invalidate device list to refresh
    ref.invalidate(userDevicesProvider);

    if (context.mounted) {
      context.pop();
    }
  }

  Future<void> _confirmExit(BuildContext context, WidgetRef ref) async {
    final state = ref.read(deviceSetupProvider);

    if (state.isConnected && !state.isSuccess) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Cancel Setup?'),
          content: const Text(
            'Are you sure you want to cancel the device setup? '
            'You can try again later.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Continue Setup'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    }

    ref.read(deviceSetupProvider.notifier).reset();
    if (context.mounted) {
      context.pop();
    }
  }
}

/// Step 1: Scanning for devices
class _ScanningStep extends StatelessWidget {
  const _ScanningStep();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 64,
            height: 64,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 32),
          Text(
            'Searching for devices...',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Make sure your device is in pairing mode',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: SaturdayColors.secondary,
                ),
          ),
        ],
      ),
    );
  }
}

/// Step 3: Select from discovered devices
class _SelectDeviceStep extends StatelessWidget {
  final List<DiscoveredDevice> devices;
  final void Function(DiscoveredDevice) onSelectDevice;
  final VoidCallback onRescan;

  const _SelectDeviceStep({
    required this.devices,
    required this.onSelectDevice,
    required this.onRescan,
  });

  @override
  Widget build(BuildContext context) {
    if (devices.isEmpty) {
      return _buildNoDevicesFound(context);
    }

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: Spacing.pagePadding,
            itemCount: devices.length,
            itemBuilder: (context, index) {
              final device = devices[index];
              return _DiscoveredDeviceCard(
                device: device,
                onTap: () => onSelectDevice(device),
              );
            },
          ),
        ),
        Padding(
          padding: Spacing.pagePadding,
          child: TextButton.icon(
            onPressed: onRescan,
            icon: const Icon(Icons.refresh),
            label: const Text('Scan Again'),
          ),
        ),
      ],
    );
  }

  Widget _buildNoDevicesFound(BuildContext context) {
    return Center(
      child: Padding(
        padding: Spacing.pagePadding,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bluetooth_searching,
              size: 64,
              color: SaturdayColors.secondary,
            ),
            const SizedBox(height: 24),
            Text(
              'No devices found',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Make sure your device is powered on and in pairing mode.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: SaturdayColors.secondary,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: onRescan,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiscoveredDeviceCard extends StatelessWidget {
  final DiscoveredDevice device;
  final VoidCallback onTap;

  const _DiscoveredDeviceCard({
    required this.device,
    required this.onTap,
  });

  IconData get _signalIcon {
    final rssi = device.rssi;
    if (rssi >= -50) return Icons.signal_wifi_4_bar;
    if (rssi >= -60) return Icons.network_wifi_3_bar;
    if (rssi >= -70) return Icons.network_wifi_2_bar;
    if (rssi >= -80) return Icons.network_wifi_1_bar;
    return Icons.signal_wifi_0_bar;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: SaturdayColors.primaryDark.withValues(alpha: 0.1),
            borderRadius: AppRadius.mediumRadius,
          ),
          child: Icon(
            device.isHub ? Icons.router : Icons.inventory_2_outlined,
            color: SaturdayColors.primaryDark,
          ),
        ),
        title: Text(device.name),
        subtitle: Text(device.identifier ?? 'Saturday Device'),
        trailing: Icon(_signalIcon, color: SaturdayColors.secondary),
        onTap: onTap,
      ),
    );
  }
}

/// Step 4: Connecting to device
class _ConnectingStep extends StatelessWidget {
  const _ConnectingStep();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 64,
            height: 64,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 32),
          Text(
            'Connecting...',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Please wait while we connect to your device',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: SaturdayColors.secondary,
                ),
          ),
        ],
      ),
    );
  }
}

/// Step 5: Configure device (Wi-Fi for Hub)
class _ConfigureStep extends ConsumerStatefulWidget {
  final BleDeviceInfo deviceInfo;
  final List<WifiNetwork> wifiNetworks;
  final BleProvisioningStatus? provisioningStatus;

  const _ConfigureStep({
    required this.deviceInfo,
    required this.wifiNetworks,
    this.provisioningStatus,
  });

  @override
  ConsumerState<_ConfigureStep> createState() => _ConfigureStepState();
}

class _ConfigureStepState extends ConsumerState<_ConfigureStep> {
  final _nameController = TextEditingController();
  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    // Initialize with default device name
    final defaultName = widget.deviceInfo.isHub
        ? 'Saturday Hub ${widget.deviceInfo.unitId}'
        : 'Saturday Crate ${widget.deviceInfo.unitId}';
    _nameController.text = defaultName;
    // Set in state so it persists
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(deviceSetupProvider.notifier).setCustomDeviceName(defaultName);
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isProvisioning = widget.provisioningStatus != null &&
        !widget.provisioningStatus!.isError &&
        widget.provisioningStatus != BleProvisioningStatus.ready;

    if (isProvisioning) {
      return _buildProvisioningProgress(context);
    }

    if (widget.deviceInfo.isHub) {
      return _buildWifiConfig(context);
    } else {
      return _buildThreadConfig(context);
    }
  }

  Widget _buildWifiConfig(BuildContext context) {
    return SingleChildScrollView(
      padding: Spacing.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Name Your Device',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Give your device a name to help you identify it.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: SaturdayColors.secondary,
                ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Device Name',
              hintText: 'e.g., Living Room Hub',
              prefixIcon: Icon(Icons.edit_outlined),
            ),
            textInputAction: TextInputAction.next,
            onChanged: (value) {
              ref.read(deviceSetupProvider.notifier).setCustomDeviceName(value);
            },
          ),
          const SizedBox(height: 32),
          Text(
            'Connect to Wi-Fi',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Enter your Wi-Fi network credentials to connect your Hub.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: SaturdayColors.secondary,
                ),
          ),
          const SizedBox(height: 16),
          // Wi-Fi network selection
          if (widget.wifiNetworks.isNotEmpty) ...[
            Text(
              'Available Networks',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            ...widget.wifiNetworks.take(5).map((network) => ListTile(
                  leading: Icon(
                    network.secure ? Icons.wifi_lock : Icons.wifi,
                    color: SaturdayColors.primaryDark,
                  ),
                  title: Text(network.ssid),
                  trailing: _buildSignalBars(network.signalStrength),
                  onTap: () {
                    _ssidController.text = network.ssid;
                  },
                )),
            const Divider(height: 32),
          ],
          // Manual entry
          TextField(
            controller: _ssidController,
            decoration: const InputDecoration(
              labelText: 'Network Name (SSID)',
              hintText: 'Enter your Wi-Fi network name',
              prefixIcon: Icon(Icons.wifi),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'Password',
              hintText: 'Enter your Wi-Fi password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: () {
                  setState(() => _obscurePassword = !_obscurePassword);
                },
              ),
            ),
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: _submitWifiCredentials,
            child: const Text('Connect'),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () {
              ref.read(deviceSetupProvider.notifier).requestWifiScan();
            },
            child: const Text('Scan for Networks'),
          ),
        ],
      ),
    );
  }

  Widget _buildSignalBars(int strength) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(4, (index) {
        return Container(
          width: 4,
          height: 6 + (index * 4.0),
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: index < strength
                ? SaturdayColors.primaryDark
                : SaturdayColors.secondary.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(1),
          ),
        );
      }),
    );
  }

  Widget _buildThreadConfig(BuildContext context) {
    // For crates, we need to get Thread credentials from the Hub
    return SingleChildScrollView(
      padding: Spacing.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Name Your Device',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Give your device a name to help you identify it.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: SaturdayColors.secondary,
                ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Device Name',
              hintText: 'e.g., Bedroom Crate',
              prefixIcon: Icon(Icons.edit_outlined),
            ),
            textInputAction: TextInputAction.done,
            onChanged: (value) {
              ref.read(deviceSetupProvider.notifier).setCustomDeviceName(value);
            },
          ),
          const SizedBox(height: 32),
          Icon(
            Icons.hub_outlined,
            size: 64,
            color: SaturdayColors.primaryDark,
          ),
          const SizedBox(height: 24),
          Text(
            'Hub Required',
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'To set up a Crate, you need a Saturday Hub already configured. '
            'The Crate will automatically receive network credentials from your Hub.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: SaturdayColors.secondary,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: _submitThreadCredentials,
            child: const Text('Connect to Hub'),
          ),
        ],
      ),
    );
  }

  Widget _buildProvisioningProgress(BuildContext context) {
    return Center(
      child: Padding(
        padding: Spacing.pagePadding,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 64,
              height: 64,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 32),
            Text(
              widget.provisioningStatus?.displayMessage ?? 'Setting up...',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'This may take a minute',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: SaturdayColors.secondary,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  void _submitWifiCredentials() {
    final ssid = _ssidController.text.trim();
    final password = _passwordController.text;

    if (ssid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a network name')),
      );
      return;
    }

    ref.read(deviceSetupProvider.notifier).provisionWifi(
          ssid: ssid,
          password: password,
        );
  }

  void _submitThreadCredentials() {
    // In a real implementation, we'd get Thread credentials from the Hub
    // For now, we'll show a placeholder
    ref.read(deviceSetupProvider.notifier).provisionThread(
          threadDataset: '{}', // Placeholder
        );
  }
}

/// Step 6: Setup complete
class _CompleteStep extends StatelessWidget {
  final String deviceName;
  final VoidCallback onDone;

  const _CompleteStep({
    required this.deviceName,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: Spacing.pagePadding,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: SaturdayColors.success.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check,
              color: SaturdayColors.success,
              size: 48,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Setup Complete!',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            '"$deviceName" is now connected and ready to use.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: SaturdayColors.secondary,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          ElevatedButton(
            onPressed: onDone,
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}
