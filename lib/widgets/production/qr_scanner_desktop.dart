import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/services/qr_scanner_service.dart';

/// Desktop QR scanner widget - captures input from USB barcode scanner
class QRScannerDesktop extends StatefulWidget {
  final Function(String uuid) onScanned;
  final VoidCallback? onCancel;

  const QRScannerDesktop({
    super.key,
    required this.onScanned,
    this.onCancel,
  });

  @override
  State<QRScannerDesktop> createState() => _QRScannerDesktopState();
}

class _QRScannerDesktopState extends State<QRScannerDesktop> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _scannerService = QRScannerService();
  bool _isProcessing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Auto-focus the input field to receive scanner data
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _processInput(String input) async {
    if (_isProcessing || input.isEmpty) return;

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      // Process the scanned code
      final uuid = await _scannerService.processScannedCode(input);

      if (mounted) {
        widget.onScanned(uuid);
      }
    } catch (error) {
      setState(() {
        _errorMessage = 'Invalid QR code: ${error.toString()}';
        _isProcessing = false;
      });

      // Reset after showing error
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _errorMessage = null;
            _controller.clear();
          });
          _focusNode.requestFocus();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Card(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Scanner icon
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: _isProcessing
                        ? SaturdayColors.info.withValues(alpha: 0.1)
                        : _errorMessage != null
                            ? SaturdayColors.error.withValues(alpha: 0.1)
                            : SaturdayColors.success.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isProcessing
                        ? Icons.hourglass_empty
                        : _errorMessage != null
                            ? Icons.error_outline
                            : Icons.qr_code_scanner,
                    size: 60,
                    color: _isProcessing
                        ? SaturdayColors.info
                        : _errorMessage != null
                            ? SaturdayColors.error
                            : SaturdayColors.success,
                  ),
                ),

                const SizedBox(height: 24),

                // Status text
                Text(
                  _isProcessing
                      ? 'Processing...'
                      : _errorMessage != null
                          ? 'Error'
                          : 'Ready to Scan',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: SaturdayColors.primaryDark,
                      ),
                ),

                const SizedBox(height: 8),

                Text(
                  _errorMessage ??
                      'Position QR code in front of scanner\nor enter unit ID manually below',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: _errorMessage != null
                            ? SaturdayColors.error
                            : SaturdayColors.secondaryGrey,
                      ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 24),

                // Hidden input field for USB scanner
                // USB scanners act like keyboards and type the barcode
                TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Scan QR code or enter unit ID',
                    prefixIcon: const Icon(Icons.qr_code_2),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: SaturdayColors.light,
                  ),
                  onSubmitted: _processInput,
                  enabled: !_isProcessing,
                ),

                const SizedBox(height: 16),

                // Instructions
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: SaturdayColors.info.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 20,
                        color: SaturdayColors.info,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'USB scanners will automatically populate this field',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: SaturdayColors.info,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),

                if (widget.onCancel != null) ...[
                  const SizedBox(height: 24),
                  TextButton(
                    onPressed: widget.onCancel,
                    child: const Text('Cancel'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
