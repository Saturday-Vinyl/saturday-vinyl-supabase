import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/models/firmware_version.dart';
import 'package:saturday_app/models/production_step.dart';
import 'package:saturday_app/models/unit.dart';
import 'package:saturday_app/screens/device_communication/device_communication_screen.dart';

/// Screen for performing firmware provisioning on a production unit.
/// This screen redirects to the Device Communication screen.
class FirmwareProvisioningScreen extends ConsumerStatefulWidget {
  final Unit unit;
  final ProductionStep step;
  final FirmwareVersion firmware;

  const FirmwareProvisioningScreen({
    super.key,
    required this.unit,
    required this.step,
    required this.firmware,
  });

  @override
  ConsumerState<FirmwareProvisioningScreen> createState() =>
      _FirmwareProvisioningScreenState();
}

class _FirmwareProvisioningScreenState
    extends ConsumerState<FirmwareProvisioningScreen> {
  @override
  void initState() {
    super.initState();
    // Redirect to Device Communication screen after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigateToDeviceCommunication();
    });
  }

  void _navigateToDeviceCommunication() {
    // Navigate to Device Communication screen
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => const DeviceCommunicationScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Show loading while redirecting
    return Scaffold(
      appBar: AppBar(
        title: const Text('Firmware Provisioning'),
      ),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Redirecting to Device Communication...'),
          ],
        ),
      ),
    );
  }
}
