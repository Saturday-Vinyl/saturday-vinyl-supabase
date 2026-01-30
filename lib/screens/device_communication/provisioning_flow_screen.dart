import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/connected_device.dart';
import 'package:saturday_app/models/device_communication_state.dart';
import 'package:saturday_app/models/unit.dart';
import 'package:saturday_app/providers/device_communication_provider.dart';
import 'package:saturday_app/providers/unit_provider.dart';

/// Guided wizard for provisioning an unprovisioned Saturday device.
///
/// Steps:
/// 1. Device detected (show MAC, device_type, firmware)
/// 2. Unit selection: Create new OR select existing unprovisioned
/// 3. Provision data (auto-fill cloud_url, cloud_anon_key)
/// 4. Execute factory_provision command
/// 5. Verify (get_status shows serial_number)
/// 6. Complete (database records updated)
class ProvisioningFlowScreen extends ConsumerStatefulWidget {
  /// The device to provision (from USB detection)
  final ConnectedDevice device;

  const ProvisioningFlowScreen({
    super.key,
    required this.device,
  });

  @override
  ConsumerState<ProvisioningFlowScreen> createState() =>
      _ProvisioningFlowScreenState();
}

class _ProvisioningFlowScreenState
    extends ConsumerState<ProvisioningFlowScreen> {
  int _currentStep = 0;
  Unit? _selectedUnit;
  bool _isProvisioning = false;
  String? _error;
  bool _provisioningComplete = false;

  @override
  void initState() {
    super.initState();
    // Connect to device
    _connectToDevice();
  }

  Future<void> _connectToDevice() async {
    final notifier = ref.read(deviceCommunicationStateProvider.notifier);
    await notifier.connectToDevice(widget.device);
  }

  @override
  Widget build(BuildContext context) {
    final commState = ref.watch(deviceCommunicationStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Provision Device'),
        backgroundColor: SaturdayColors.primaryDark,
        foregroundColor: Colors.white,
      ),
      body: commState.phase == DeviceCommunicationPhase.connecting
          ? const Center(child: CircularProgressIndicator())
          : _buildContent(context, commState),
    );
  }

  Widget _buildContent(
      BuildContext context, DeviceCommunicationState commState) {
    return Row(
      children: [
        // Left side: Stepper
        Expanded(
          flex: 2,
          child: Stepper(
            currentStep: _currentStep,
            onStepContinue: _canContinue() ? _onStepContinue : null,
            onStepCancel:
                _currentStep > 0 && !_provisioningComplete ? _onStepCancel : null,
            controlsBuilder: _buildStepControls,
            steps: [
              _buildDeviceInfoStep(),
              _buildUnitSelectionStep(),
              _buildProvisionStep(commState),
              _buildCompleteStep(),
            ],
          ),
        ),

        // Right side: Device info card
        Container(
          width: 320,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: SaturdayColors.primaryDark.withValues(alpha: 0.05),
            border: Border(
              left: BorderSide(
                color: SaturdayColors.secondaryGrey.withValues(alpha: 0.3),
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Device Information',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              _buildDeviceInfoCard(),
              if (_selectedUnit != null) ...[
                const SizedBox(height: 24),
                Text(
                  'Selected Unit',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 16),
                _buildSelectedUnitCard(),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStepControls(BuildContext context, ControlsDetails details) {
    if (_provisioningComplete) {
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Row(
          children: [
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.check),
              label: const Text('Done'),
              style: ElevatedButton.styleFrom(
                backgroundColor: SaturdayColors.success,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        children: [
          if (_currentStep < 3)
            ElevatedButton(
              onPressed: _canContinue() ? details.onStepContinue : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: SaturdayColors.primaryDark,
                foregroundColor: Colors.white,
              ),
              child: Text(_currentStep == 2 ? 'Provision' : 'Continue'),
            ),
          if (_currentStep > 0 && _currentStep < 3) ...[
            const SizedBox(width: 12),
            TextButton(
              onPressed: _isProvisioning ? null : details.onStepCancel,
              child: const Text('Back'),
            ),
          ],
        ],
      ),
    );
  }

  Step _buildDeviceInfoStep() {
    return Step(
      title: const Text('Device Detected'),
      subtitle: Text(widget.device.formattedMacAddress),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'A Saturday device has been detected via USB. '
            'Review the device information and proceed to select a unit for provisioning.',
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.check_circle, color: SaturdayColors.success, size: 20),
              const SizedBox(width: 8),
              Text(
                'Device connected on ${widget.device.portName}',
                style: TextStyle(color: SaturdayColors.success),
              ),
            ],
          ),
        ],
      ),
      isActive: _currentStep >= 0,
      state: _currentStep > 0 ? StepState.complete : StepState.indexed,
    );
  }

  Step _buildUnitSelectionStep() {
    return Step(
      title: const Text('Select Unit'),
      subtitle: _selectedUnit != null
          ? Text(_selectedUnit!.serialNumber ?? 'Unit selected')
          : null,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Select an existing unprovisioned unit to assign to this device, '
            'or create a new unit.',
          ),
          const SizedBox(height: 16),
          _buildUnitSelector(),
        ],
      ),
      isActive: _currentStep >= 1,
      state: _currentStep > 1 ? StepState.complete : StepState.indexed,
    );
  }

  Step _buildProvisionStep(DeviceCommunicationState commState) {
    return Step(
      title: const Text('Provision'),
      subtitle: _isProvisioning
          ? const Text('Provisioning in progress...')
          : _error != null
              ? Text('Error: $_error', style: TextStyle(color: SaturdayColors.error))
              : null,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'The device will be configured with the selected unit\'s serial number '
            'and cloud credentials.',
          ),
          const SizedBox(height: 16),
          if (_isProvisioning)
            Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                const Text('Sending factory_provision command...'),
              ],
            )
          else if (_error != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: SaturdayColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: SaturdayColors.error),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: SaturdayColors.error),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_error!)),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: SaturdayColors.info.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: SaturdayColors.info),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Click "Provision" to send the factory_provision command to the device.',
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      isActive: _currentStep >= 2,
      state: _provisioningComplete
          ? StepState.complete
          : _error != null
              ? StepState.error
              : StepState.indexed,
    );
  }

  Step _buildCompleteStep() {
    return Step(
      title: const Text('Complete'),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: SaturdayColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: SaturdayColors.success),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: SaturdayColors.success, size: 32),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Device Provisioned Successfully!',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Serial: ${_selectedUnit?.serialNumber ?? 'N/A'}',
                        style: TextStyle(color: SaturdayColors.secondaryGrey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      isActive: _currentStep >= 3,
      state: _provisioningComplete ? StepState.complete : StepState.indexed,
    );
  }

  Widget _buildDeviceInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('Type', _formatDeviceType(widget.device.deviceType)),
            const SizedBox(height: 8),
            _buildInfoRow('MAC', widget.device.formattedMacAddress),
            const SizedBox(height: 8),
            _buildInfoRow('Firmware', 'v${widget.device.firmwareVersion}'),
            const SizedBox(height: 8),
            _buildInfoRow('Port', widget.device.portName),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedUnitCard() {
    if (_selectedUnit == null) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('Serial', _selectedUnit!.serialNumber ?? 'N/A'),
            const SizedBox(height: 8),
            _buildInfoRow('Name', _selectedUnit!.displayName),
            const SizedBox(height: 8),
            _buildInfoRow('Status', _selectedUnit!.status.name),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: SaturdayColors.secondaryGrey,
            fontSize: 12,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w500,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  Widget _buildUnitSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search/Select existing unit
        Consumer(
          builder: (context, ref, _) {
            final unitsAsync = ref.watch(unitsByStatusProvider(UnitStatus.unprovisioned));

            return unitsAsync.when(
              data: (units) {
                // Units with unprovisioned status are available for provisioning
                final unprovisionedUnits = units;

                if (unprovisionedUnits.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: SaturdayColors.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber, color: SaturdayColors.warning),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'No unprovisioned units available. Create a new unit first.',
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${unprovisionedUnits.length} unprovisioned unit(s) available',
                      style: TextStyle(
                        color: SaturdayColors.secondaryGrey,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...unprovisionedUnits.map((unit) => _buildUnitOption(unit)),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error loading units: $e'),
            );
          },
        ),
      ],
    );
  }

  Widget _buildUnitOption(Unit unit) {
    final isSelected = _selectedUnit?.id == unit.id;

    return Card(
      color: isSelected
          ? SaturdayColors.primaryDark.withValues(alpha: 0.1)
          : null,
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedUnit = unit;
          });
          // Also set on the provider
          ref
              .read(deviceCommunicationStateProvider.notifier)
              .setUnitForProvisioning(unit);
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                color:
                    isSelected ? SaturdayColors.primaryDark : SaturdayColors.secondaryGrey,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      unit.serialNumber ?? 'No serial',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                      ),
                    ),
                    Text(
                      unit.displayName,
                      style: TextStyle(
                        color: SaturdayColors.secondaryGrey,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _canContinue() {
    switch (_currentStep) {
      case 0:
        return true;
      case 1:
        return _selectedUnit != null;
      case 2:
        return !_isProvisioning && _selectedUnit != null;
      default:
        return false;
    }
  }

  void _onStepContinue() {
    if (_currentStep == 2) {
      _executeProvisioning();
    } else {
      setState(() {
        _currentStep++;
      });
    }
  }

  void _onStepCancel() {
    setState(() {
      _currentStep--;
      _error = null;
    });
  }

  Future<void> _executeProvisioning() async {
    setState(() {
      _isProvisioning = true;
      _error = null;
    });

    try {
      final notifier = ref.read(deviceCommunicationStateProvider.notifier);
      final success = await notifier.factoryProvision();

      if (success) {
        setState(() {
          _isProvisioning = false;
          _provisioningComplete = true;
          _currentStep = 3;
        });
      } else {
        final state = ref.read(deviceCommunicationStateProvider);
        setState(() {
          _isProvisioning = false;
          _error = state.errorMessage ?? 'Provisioning failed';
        });
      }
    } catch (e) {
      setState(() {
        _isProvisioning = false;
        _error = e.toString();
      });
    }
  }

  String _formatDeviceType(String type) {
    return type
        .split('-')
        .map((word) =>
            word.isNotEmpty ? '${word[0].toUpperCase()}${word.substring(1)}' : '')
        .join(' ');
  }
}
