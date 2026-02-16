import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/models/consumer_attributes.dart';
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
    // Get context-specific icon and title based on error code
    final errorCode = state.errorCode;
    IconData icon;
    String title;

    switch (errorCode) {
      case BleErrorCode.authFailed:
        icon = Icons.lock_outline;
        title = 'Incorrect Password';
      case BleErrorCode.networkNotFound:
        icon = Icons.wifi_off;
        title = 'Network Not Found';
      case BleErrorCode.timeout:
        icon = Icons.timer_off_outlined;
        title = 'Connection Timed Out';
      case BleErrorCode.wifiFailed:
        icon = Icons.wifi_off;
        title = 'Wi-Fi Connection Failed';
      case BleErrorCode.storageFailed:
        icon = Icons.storage_outlined;
        title = 'Storage Error';
      default:
        icon = Icons.error_outline;
        title = 'Something went wrong';
    }

    return Center(
      child: Padding(
        padding: Spacing.pagePadding,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 64,
              color: SaturdayColors.error,
            ),
            const SizedBox(height: 24),
            Text(
              title,
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

    // Claim the unit and update with provisioning data
    try {
      final unitRepo = ref.read(unitRepositoryProvider);

      // Step 1: Claim the unit via Edge Function
      debugPrint('[DeviceSetup] Claiming unit: ${deviceInfo.serialNumber}');
      final claimedDevice = await unitRepo.claimUnit(deviceInfo.serialNumber);
      debugPrint('[DeviceSetup] Unit claimed successfully: ${claimedDevice.id}');

      // Step 2: Build provision data based on device type
      // Per the Device Command Protocol, both consumer_input (sent to device)
      // and consumer_output (returned by device) are stored in provision_data.
      final consumerOutput = state.consumerOutput;
      ProvisionData provisionData;
      if (deviceInfo.isHub && state.wifiSsid != null) {
        // For hubs, store the WiFi SSID that was used for provisioning
        // Note: We don't store the password for security reasons
        provisionData = ProvisionData.wifi(
          ssid: state.wifiSsid!,
          consumerOutput: consumerOutput,
        );
        debugPrint('[DeviceSetup] Storing WiFi config: SSID=${state.wifiSsid}, '
            'consumerOutput=$consumerOutput');
      } else if (deviceInfo.isCrate && state.threadDataset != null) {
        // For crates, store the Thread dataset used for provisioning
        provisionData = ProvisionData.thread(
          dataset: state.threadDataset!,
          networkName: 'Saturday Thread Network',
          consumerOutput: consumerOutput,
        );
        debugPrint('[DeviceSetup] Storing Thread config from hub ${state.selectedHubId}, '
            'consumerOutput=$consumerOutput');
      } else {
        provisionData = ProvisionData(consumerOutput: consumerOutput);
      }

      // Step 3: Update unit with device name and provisioning data
      final deviceName = state.effectiveDeviceName;
      await unitRepo.updateUnitProvisioning(
        unitId: claimedDevice.id,
        userId: userId,
        deviceName: deviceName,
        provisionData: provisionData,
      );
      debugPrint('[DeviceSetup] Device provisioned successfully: $deviceName');
    } catch (e) {
      debugPrint('[DeviceSetup] Error claiming/provisioning device: $e');
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

    await ref.read(deviceSetupProvider.notifier).reset();
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
  final _passwordFocusNode = FocusNode();
  final _ssidFocusNode = FocusNode();
  bool _obscurePassword = true;
  Device? _selectedHub;
  bool _hasRestoredFromRetry = false;

  @override
  void initState() {
    super.initState();
    // Initialize with default device name
    final defaultName = widget.deviceInfo.isHub
        ? 'Saturday Hub ${widget.deviceInfo.serialNumber}'
        : 'Saturday Crate ${widget.deviceInfo.serialNumber}';
    _nameController.text = defaultName;
    // Set in state so it persists
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(deviceSetupProvider.notifier).setCustomDeviceName(defaultName);
      _handleRetryState();
    });
  }

  /// Handle smart retry behavior - restore SSID and focus appropriate field.
  void _handleRetryState() {
    if (_hasRestoredFromRetry) return;

    final state = ref.read(deviceSetupProvider);

    // If we have a stored SSID from a previous attempt, restore it
    if (state.wifiSsid != null && state.wifiSsid!.isNotEmpty) {
      _ssidController.text = state.wifiSsid!;
      _hasRestoredFromRetry = true;

      // For auth errors, clear password and focus password field
      // For network not found, focus SSID field so user can edit
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (state.errorCode?.isAuthError == true) {
          _passwordController.clear();
          _passwordFocusNode.requestFocus();
        } else if (state.errorCode?.isNetworkError == true) {
          _ssidFocusNode.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ssidController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    _ssidFocusNode.dispose();
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
            focusNode: _ssidFocusNode,
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
            focusNode: _passwordFocusNode,
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
    final hubsAsync = ref.watch(userHubsProvider);

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
          Text(
            'Select a Hub',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Choose a Saturday Hub to provide network credentials to your Crate. '
            'The Hub must be online.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: SaturdayColors.secondary,
                ),
          ),
          const SizedBox(height: 16),
          hubsAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (error, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Failed to load hubs: $error',
                style: TextStyle(color: SaturdayColors.error),
              ),
            ),
            data: (hubs) => _buildHubList(context, hubs),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: _selectedHub != null ? _submitThreadCredentials : null,
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Widget _buildHubList(BuildContext context, List<Device> hubs) {
    if (hubs.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: SaturdayColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: SaturdayColors.secondary.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Icon(
              Icons.hub_outlined,
              size: 48,
              color: SaturdayColors.secondary,
            ),
            const SizedBox(height: 16),
            Text(
              'No Hubs Found',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'You need to set up a Saturday Hub before you can add a Crate. '
              'The Hub provides the network connection for your Crate.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: SaturdayColors.secondary,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      children: hubs.map((hub) {
        final isOnline = hub.isEffectivelyOnline;
        final isSelected = _selectedHub?.id == hub.id;

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: isSelected
                ? SaturdayColors.primaryDark.withValues(alpha: 0.1)
                : SaturdayColors.white,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: isOnline
                  ? () {
                      setState(() {
                        _selectedHub = hub;
                      });
                    }
                  : null,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? SaturdayColors.primaryDark
                        : SaturdayColors.secondary.withValues(alpha: 0.2),
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: isOnline
                            ? SaturdayColors.primaryDark.withValues(alpha: 0.1)
                            : SaturdayColors.secondary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.hub_outlined,
                        color: isOnline
                            ? SaturdayColors.primaryDark
                            : SaturdayColors.secondary,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hub.name,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: isOnline ? null : SaturdayColors.secondary,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isOnline
                                      ? SaturdayColors.success
                                      : SaturdayColors.secondary,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isOnline ? 'Online' : 'Offline',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: isOnline
                                          ? SaturdayColors.success
                                          : SaturdayColors.secondary,
                                    ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (isSelected)
                      Icon(
                        Icons.check_circle,
                        color: SaturdayColors.primaryDark,
                      )
                    else if (!isOnline)
                      Icon(
                        Icons.block,
                        color: SaturdayColors.secondary.withValues(alpha: 0.5),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
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

  void _submitThreadCredentials() async {
    if (_selectedHub == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a Hub')),
      );
      return;
    }

    // Get Thread dataset from the selected hub's consumer attributes
    final unitRepo = ref.read(unitRepositoryProvider);
    final threadDataset = await unitRepo.getHubThreadDataset(_selectedHub!.id);

    if (threadDataset == null || threadDataset.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The selected Hub does not have Thread credentials. '
                'Please ensure the Hub is fully set up.'),
          ),
        );
      }
      return;
    }

    ref.read(deviceSetupProvider.notifier).provisionThread(
          threadDataset: threadDataset,
          hubId: _selectedHub!.id,
        );
  }
}

/// Step 6: Setup complete
class _CompleteStep extends StatefulWidget {
  final String deviceName;
  final Future<void> Function() onDone;

  const _CompleteStep({
    required this.deviceName,
    required this.onDone,
  });

  @override
  State<_CompleteStep> createState() => _CompleteStepState();
}

class _CompleteStepState extends State<_CompleteStep> {
  bool _isSaving = false;

  Future<void> _handleDone() async {
    setState(() => _isSaving = true);
    try {
      await widget.onDone();
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

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
            _isSaving ? 'Saving...' : 'Setup Complete!',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            _isSaving
                ? 'Registering your device with Saturday...'
                : '"${widget.deviceName}" is now connected and ready to use.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: SaturdayColors.secondary,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          SizedBox(
            width: 120,
            height: 48,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _handleDone,
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text('Done'),
            ),
          ),
        ],
      ),
    );
  }
}
