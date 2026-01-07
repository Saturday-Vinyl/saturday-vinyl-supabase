import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/models/firmware_version.dart';
import 'package:saturday_app/models/production_step.dart';
import 'package:saturday_app/models/production_unit.dart';
import 'package:saturday_app/providers/service_mode_provider.dart';
import 'package:saturday_app/screens/service_mode/service_mode_screen.dart';

/// Screen for performing firmware provisioning on a production unit.
/// This screen now redirects to the global Service Mode screen with context.
class FirmwareProvisioningScreen extends ConsumerStatefulWidget {
  final ProductionUnit unit;
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
    // Redirect to Service Mode screen after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigateToServiceMode();
    });
  }

  void _navigateToServiceMode() {
    // Navigate to Service Mode screen with production unit context
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => ServiceModeScreen(
          args: ServiceModeArgs(
            unit: widget.unit,
            step: widget.step,
          ),
        ),
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
            Text('Redirecting to Service Mode...'),
          ],
        ),
      ),
    );
  }
}
