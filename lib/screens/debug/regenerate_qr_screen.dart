import 'package:flutter/material.dart';
import 'package:saturday_app/scripts/regenerate_qr_codes.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// Debug screen to regenerate QR codes for existing production units
///
/// This screen provides a UI to run the QR code regeneration script
/// for production units that were created before the branded QR code feature.
class RegenerateQRScreen extends StatefulWidget {
  const RegenerateQRScreen({super.key});

  @override
  State<RegenerateQRScreen> createState() => _RegenerateQRScreenState();
}

class _RegenerateQRScreenState extends State<RegenerateQRScreen> {
  bool _isRegenerating = false;
  String _status = 'Ready to regenerate QR codes';
  final List<String> _logs = [];

  Future<void> _regenerateQRCodes() async {
    setState(() {
      _isRegenerating = true;
      _status = 'Regenerating QR codes...';
      _logs.clear();
    });

    try {
      final uuids = [
        '51807ce2-11ab-41e0-8900-e1e1c5bae9bd',
        'ee7736c1-a48b-4b5d-8498-6f811634aea5',
      ];

      _addLog('Starting regeneration for ${uuids.length} production units');

      await regenerateQRCodes(uuids);

      setState(() {
        _status = '✓ Successfully regenerated ${uuids.length} QR codes';
        _addLog('Regeneration complete!');
      });
    } catch (error, stackTrace) {
      AppLogger.error('QR regeneration failed', error, stackTrace);
      setState(() {
        _status = '✗ Regeneration failed: $error';
        _addLog('Error: $error');
      });
    } finally {
      setState(() {
        _isRegenerating = false;
      });
    }
  }

  void _addLog(String message) {
    setState(() {
      _logs.add('[${DateTime.now().toString().substring(11, 19)}] $message');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Regenerate QR Codes'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'QR Code Regeneration',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'This will regenerate QR codes for the following production units with the new branded design:',
                    ),
                    const SizedBox(height: 8),
                    const Text('• 51807ce2-11ab-41e0-8900-e1e1c5bae9bd'),
                    const Text('• ee7736c1-a48b-4b5d-8498-6f811634aea5'),
                    const SizedBox(height: 16),
                    Text(
                      _status,
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: _status.startsWith('✓')
                            ? Colors.green
                            : _status.startsWith('✗')
                                ? Colors.red
                                : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isRegenerating ? null : _regenerateQRCodes,
              icon: _isRegenerating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              label: Text(
                _isRegenerating ? 'Regenerating...' : 'Regenerate QR Codes',
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Logs:',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Card(
                child: _logs.isEmpty
                    ? const Center(
                        child: Text('No logs yet'),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: _logs.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              _logs[index],
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
