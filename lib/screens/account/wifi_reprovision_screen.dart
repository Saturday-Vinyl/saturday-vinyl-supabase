import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/models/consumer_attributes.dart';
import 'package:saturday_consumer_app/providers/auth_provider.dart';
import 'package:saturday_consumer_app/providers/device_provider.dart';
import 'package:saturday_consumer_app/providers/repository_providers.dart';
import 'package:saturday_consumer_app/providers/wifi_reprovision_provider.dart';
import 'package:saturday_consumer_app/services/ble_service.dart';

/// Data passed via route extra to avoid redundant DB fetches.
class WifiReprovisionExtra {
  final String deviceName;
  final String serialNumber;
  final String? knownSsid;

  const WifiReprovisionExtra({
    required this.deviceName,
    required this.serialNumber,
    this.knownSsid,
  });
}

/// Screen for changing WiFi credentials on an already-provisioned Hub.
class WifiReprovisionScreen extends ConsumerStatefulWidget {
  final String unitId;
  final String deviceName;
  final String serialNumber;
  final String? knownSsid;

  const WifiReprovisionScreen({
    super.key,
    required this.unitId,
    required this.deviceName,
    required this.serialNumber,
    this.knownSsid,
  });

  @override
  ConsumerState<WifiReprovisionScreen> createState() => _WifiReprovisionScreenState();
}

class _WifiReprovisionScreenState extends ConsumerState<WifiReprovisionScreen> {
  late final WifiReprovisionArgs _args;

  @override
  void initState() {
    super.initState();
    _args = WifiReprovisionArgs(
      unitId: widget.unitId,
      serialNumber: widget.serialNumber,
      knownSsid: widget.knownSsid,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(wifiReprovisionProvider(_args));

    return Scaffold(
      appBar: AppBar(
        title: Text(_getTitle(state)),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _confirmExit(context),
        ),
      ),
      body: _buildBody(context, state),
    );
  }

  String _getTitle(WifiReprovisionState state) {
    switch (state.currentStep) {
      case ReprovisionStep.instructions:
        return 'Change Wi-Fi Network';
      case ReprovisionStep.scanning:
        return 'Searching...';
      case ReprovisionStep.connecting:
        return 'Connecting...';
      case ReprovisionStep.configure:
        return 'Update Wi-Fi';
      case ReprovisionStep.complete:
        return 'Network Updated';
    }
  }

  Widget _buildBody(BuildContext context, WifiReprovisionState state) {
    // Show error overlay if present (except on complete step)
    if (state.hasError && state.currentStep != ReprovisionStep.complete) {
      return _buildError(context, state);
    }

    switch (state.currentStep) {
      case ReprovisionStep.instructions:
        return _InstructionsStep(
          deviceName: widget.deviceName,
          onStartScan: _startScan,
        );
      case ReprovisionStep.scanning:
        return _ScanningStep(deviceName: widget.deviceName);
      case ReprovisionStep.connecting:
        return _ConnectingStep(deviceName: widget.deviceName);
      case ReprovisionStep.configure:
        return _WifiConfigureStep(
          args: _args,
          deviceName: widget.deviceName,
          wifiNetworks: state.wifiNetworks,
          provisioningStatus: state.provisioningStatus,
          knownSsid: widget.knownSsid,
        );
      case ReprovisionStep.complete:
        return _CompleteStep(
          deviceName: widget.deviceName,
          newSsid: state.wifiSsid ?? '',
          onDone: () => _onReprovisionComplete(context),
        );
    }
  }

  Widget _buildError(BuildContext context, WifiReprovisionState state) {
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
            Icon(icon, size: 64, color: SaturdayColors.error),
            const SizedBox(height: 24),
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
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
                  onPressed: () =>
                      ref.read(wifiReprovisionProvider(_args).notifier).retry(),
                  child: const Text('Try Again'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startScan() async {
    final notifier = ref.read(wifiReprovisionProvider(_args).notifier);
    final available = await notifier.checkBleAvailability();
    if (!available && mounted) {
      _showBleError();
    } else {
      notifier.startScan();
    }
  }

  void _showBleError() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bluetooth Required'),
        content: const Text(
          'Please enable Bluetooth to change your device\'s Wi-Fi network.',
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
              _startScan();
            },
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  Future<void> _onReprovisionComplete(BuildContext context) async {
    final state = ref.read(wifiReprovisionProvider(_args));
    final userId = ref.read(currentUserIdProvider);

    if (userId == null) {
      debugPrint('[WiFi Reprovision] No user ID');
      if (context.mounted) context.pop();
      return;
    }

    try {
      final unitRepo = ref.read(unitRepositoryProvider);
      final newSsid = state.wifiSsid;

      if (newSsid != null) {
        await unitRepo.updateUnitProvisioning(
          unitId: widget.unitId,
          userId: userId,
          deviceName: widget.deviceName,
          provisionData: ProvisionData.wifi(
            ssid: newSsid,
            consumerOutput: state.consumerOutput,
          ),
        );
        debugPrint('[WiFi Reprovision] Updated provision_data with SSID=$newSsid');
      }
    } catch (e) {
      debugPrint('[WiFi Reprovision] Error updating provision data: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Network updated but failed to save: $e')),
        );
      }
    }

    // Refresh device data
    ref.invalidate(deviceByIdProvider(widget.unitId));
    ref.invalidate(userDevicesProvider);

    if (context.mounted) {
      context.pop();
    }
  }

  Future<void> _confirmExit(BuildContext context) async {
    final state = ref.read(wifiReprovisionProvider(_args));

    if (state.isConnected && !state.isSuccess) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Cancel Network Change?'),
          content: const Text(
            'Are you sure you want to cancel? Your device will keep '
            'its current Wi-Fi settings.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Continue'),
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

    await ref.read(wifiReprovisionProvider(_args).notifier).reset();
    if (context.mounted) {
      context.pop();
    }
  }
}

/// Instructions step — tells user to long-press the device.
class _InstructionsStep extends StatelessWidget {
  final String deviceName;
  final VoidCallback onStartScan;

  const _InstructionsStep({
    required this.deviceName,
    required this.onStartScan,
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
              color: SaturdayColors.info.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.bluetooth,
              color: SaturdayColors.info,
              size: 40,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Put Your Hub in Pairing Mode',
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            'Long-press the button on "$deviceName" for 3 seconds '
            'until the light flashes blue.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: SaturdayColors.secondary,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onStartScan,
              child: const Text('Start Scanning'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Scanning step — searching for the target device.
class _ScanningStep extends StatelessWidget {
  final String deviceName;

  const _ScanningStep({required this.deviceName});

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
            'Searching for $deviceName...',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Make sure the light is flashing blue',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: SaturdayColors.secondary,
                ),
          ),
        ],
      ),
    );
  }
}

/// Connecting step.
class _ConnectingStep extends StatelessWidget {
  final String deviceName;

  const _ConnectingStep({required this.deviceName});

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
            'Connecting to $deviceName...',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Please wait while we connect',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: SaturdayColors.secondary,
                ),
          ),
        ],
      ),
    );
  }
}

/// WiFi configuration step.
class _WifiConfigureStep extends ConsumerStatefulWidget {
  final WifiReprovisionArgs args;
  final String deviceName;
  final List<WifiNetwork> wifiNetworks;
  final BleProvisioningStatus? provisioningStatus;
  final String? knownSsid;

  const _WifiConfigureStep({
    required this.args,
    required this.deviceName,
    required this.wifiNetworks,
    this.provisioningStatus,
    this.knownSsid,
  });

  @override
  ConsumerState<_WifiConfigureStep> createState() => _WifiConfigureStepState();
}

class _WifiConfigureStepState extends ConsumerState<_WifiConfigureStep> {
  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocusNode = FocusNode();
  final _ssidFocusNode = FocusNode();
  bool _obscurePassword = true;
  bool _hasRestoredFromRetry = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill SSID from known value or previous attempt
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreSsid();
    });
  }

  void _restoreSsid() {
    if (_hasRestoredFromRetry) return;

    final state = ref.read(wifiReprovisionProvider(widget.args));

    // Restore SSID from state (retry) or known value (first time)
    final ssid = state.wifiSsid ?? widget.knownSsid;
    if (ssid != null && ssid.isNotEmpty && _ssidController.text.isEmpty) {
      _ssidController.text = ssid;
      _hasRestoredFromRetry = true;

      // Focus the right field based on error type
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

    return _buildWifiForm(context);
  }

  Widget _buildWifiForm(BuildContext context) {
    return SingleChildScrollView(
      padding: Spacing.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Update Wi-Fi Network',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Enter the credentials for the network you want '
            '"${widget.deviceName}" to connect to.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: SaturdayColors.secondary,
                ),
          ),
          const SizedBox(height: 24),
          // Available networks list
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
            onPressed: _submitCredentials,
            child: const Text('Connect'),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () {
              ref.read(wifiReprovisionProvider(widget.args).notifier).requestWifiScan();
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
              widget.provisioningStatus?.displayMessage ?? 'Updating network...',
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

  void _submitCredentials() {
    final ssid = _ssidController.text.trim();
    final password = _passwordController.text;

    if (ssid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a network name')),
      );
      return;
    }

    ref.read(wifiReprovisionProvider(widget.args).notifier).provisionWifi(
          ssid: ssid,
          password: password,
        );
  }
}

/// Completion step.
class _CompleteStep extends StatefulWidget {
  final String deviceName;
  final String newSsid;
  final Future<void> Function() onDone;

  const _CompleteStep({
    required this.deviceName,
    required this.newSsid,
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
            _isSaving ? 'Saving...' : 'Network Updated',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            _isSaving
                ? 'Saving your new network settings...'
                : '"${widget.deviceName}" is now connected to "${widget.newSsid}".',
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
