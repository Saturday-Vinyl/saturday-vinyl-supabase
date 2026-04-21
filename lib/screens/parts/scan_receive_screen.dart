import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/part.dart';
import 'package:saturday_app/providers/digikey_provider.dart';
import 'package:saturday_app/providers/inventory_provider.dart';
import 'package:saturday_app/providers/parts_provider.dart';
import 'package:saturday_app/providers/suppliers_provider.dart';
import 'package:saturday_app/repositories/inventory_repository.dart';
import 'package:saturday_app/repositories/parts_repository.dart';
import 'package:saturday_app/repositories/supplier_parts_repository.dart';
import 'package:saturday_app/repositories/suppliers_repository.dart';
import 'package:saturday_app/services/barcode_matcher_service.dart';
import 'package:saturday_app/services/digikey_service.dart';
import 'package:saturday_app/services/supabase_service.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// Scan-to-receive workflow: scan a barcode, match to a part, receive inventory.
class ScanReceiveScreen extends ConsumerStatefulWidget {
  const ScanReceiveScreen({super.key});

  @override
  ConsumerState<ScanReceiveScreen> createState() => _ScanReceiveScreenState();
}

class _ScanReceiveScreenState extends ConsumerState<ScanReceiveScreen> {
  final _matcher = BarcodeMatcherService();
  final _desktopController = TextEditingController();
  final _desktopFocusNode = FocusNode();
  MobileScannerController? _cameraController;

  _ScanState _state = _ScanState.ready;
  String? _lastBarcode;
  BarcodeMatchResult? _matchResult;
  ParsedBarcodeData? _lastParsedData;
  List<DigiKeyProduct>? _digikeyResults;
  bool _digikeyLoading = false;
  bool _cameraActive = true;

  // Session tracking
  final List<_ReceivedItem> _sessionItems = [];
  final Set<String> _receivedBarcodes = {};

  bool get _isDesktop =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  @override
  void initState() {
    super.initState();
    if (!_isDesktop) {
      _cameraController = MobileScannerController();
    }
  }

  @override
  void dispose() {
    _desktopController.dispose();
    _desktopFocusNode.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Listen for USB barcode scans forwarded from the global keyboard listener
    ref.listen<String?>(usbBarcodeProvider, (prev, next) {
      if (next != null && _state == _ScanState.ready) {
        ref.read(usbBarcodeProvider.notifier).state = null;
        _processBarcode(next.trim());
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan to Receive'),
        actions: [
          if (_sessionItems.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: Chip(
                  avatar: const Icon(Icons.check, size: 16),
                  label: Text(
                      '${_sessionItems.length} received this session'),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: switch (_state) {
              _ScanState.ready => _isDesktop
                  ? _buildDesktopScanner()
                  : _buildMobileScanner(),
              _ScanState.matching => _buildMatchingView(),
              _ScanState.matched => _buildMatchedView(),
              _ScanState.unmatched => _buildUnmatchedView(),
              _ScanState.receiving => _buildReceivingView(),
            },
          ),
          if (_sessionItems.isNotEmpty) _buildSessionSummary(),
        ],
      ),
    );
  }

  // ---- Desktop USB scanner ----

  Widget _buildDesktopScanner() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Card(
          elevation: 4,
          margin: const EdgeInsets.all(32),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: SaturdayColors.success.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.qr_code_scanner,
                      size: 50, color: SaturdayColors.success),
                ),
                const SizedBox(height: 24),
                const Text('Ready to Scan',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text(
                  'Scan a supplier barcode with USB scanner\nor enter barcode manually',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: SaturdayColors.secondaryGrey),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _desktopController,
                  focusNode: _desktopFocusNode,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Scan or type barcode...',
                    prefixIcon: const Icon(Icons.qr_code_2),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: SaturdayColors.light,
                  ),
                  onSubmitted: _handleBarcodeInput,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---- Mobile camera scanner ----

  Widget _buildMobileScanner() {
    if (!_cameraActive) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.camera_alt,
                size: 48, color: SaturdayColors.secondaryGrey),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => setState(() => _cameraActive = true),
              child: const Text('Resume Scanning'),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        MobileScanner(
          controller: _cameraController!,
          onDetect: _handleCameraBarcode,
        ),
        // Overlay
        Container(
          color: Colors.black.withValues(alpha: 0.3),
          child: Center(
            child: Container(
              width: 250,
              height: 150,
              decoration: BoxDecoration(
                border: Border.all(color: SaturdayColors.success, width: 3),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        // Instructions
        Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Text(
                'Scan supplier barcode',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---- State views ----

  Widget _buildMatchingView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Looking up barcode...'),
        ],
      ),
    );
  }

  Widget _buildMatchedView() {
    final result = _matchResult!;
    final parsed = result.parsedData;
    // Pre-fill quantity from barcode if available
    final defaultQty = parsed?.quantity;
    final qtyController = TextEditingController(
      text: defaultQty != null
          ? (defaultQty % 1 == 0
              ? defaultQty.toInt().toString()
              : defaultQty.toString())
          : '1',
    );

    return SingleChildScrollView(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.check_circle,
                      size: 48, color: SaturdayColors.success),
                  const SizedBox(height: 12),
                  const Text('Part Matched!',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: const Icon(Icons.widgets),
                    title: Text(result.part.name,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                        '${result.part.partNumber}  |  SKU: ${result.supplierPart.supplierSku}'),
                  ),
                  // Show barcode metadata if we parsed a structured barcode
                  if (parsed != null && parsed.detectedFormat != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: SaturdayColors.light,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Barcode: ${parsed.detectedFormat}',
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: SaturdayColors.secondaryGrey)),
                          const SizedBox(height: 4),
                          if (parsed.manufacturerPartNumber != null)
                            Text('Mfr PN: ${parsed.manufacturerPartNumber}',
                                style: const TextStyle(fontSize: 12)),
                          if (parsed.distributorPartNumber != null)
                            Text('Dist PN: ${parsed.distributorPartNumber}',
                                style: const TextStyle(fontSize: 12)),
                          if (parsed.lotCode != null)
                            Text('Lot: ${parsed.lotCode}',
                                style: const TextStyle(fontSize: 12)),
                          if (parsed.dateCode != null)
                            Text('Date Code: ${parsed.dateCode}',
                                style: const TextStyle(fontSize: 12)),
                          if (parsed.countryOfOrigin != null)
                            Text('Origin: ${parsed.countryOfOrigin}',
                                style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: qtyController,
                    decoration: InputDecoration(
                      labelText: defaultQty != null
                          ? 'Quantity to receive (from barcode: ${defaultQty % 1 == 0 ? defaultQty.toInt() : defaultQty})'
                          : 'Quantity to receive',
                      suffixText: result.part.unitOfMeasure.displayName,
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) {
                      final qty = double.tryParse(qtyController.text);
                      if (qty != null && qty > 0) {
                        _receiveMatched(result, qty);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _resetToReady,
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            final qty = double.tryParse(qtyController.text);
                            if (qty == null || qty <= 0) return;
                            _receiveMatched(result, qty);
                          },
                          child: const Text('Receive'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildUnmatchedView() {
    final parsed = _lastParsedData;
    final hasDigikeyData = parsed != null && !parsed.isEmpty;
    final digikeyConnected =
        ref.watch(digikeyConnectionProvider).valueOrNull?.isReady ?? false;

    return SingleChildScrollView(
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.help_outline,
                      size: 48, color: Colors.orange),
                  const SizedBox(height: 12),
                  const Text('No Match Found',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    'Barcode: ${_lastBarcode!.length > 60 ? '${_lastBarcode!.substring(0, 60)}...' : _lastBarcode}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: SaturdayColors.secondaryGrey),
                  ),

                  // Show parsed barcode metadata
                  if (hasDigikeyData) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: SaturdayColors.light,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Detected: ${parsed.detectedFormat ?? "structured"}',
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: SaturdayColors.secondaryGrey)),
                          if (parsed.distributorPartNumber != null)
                            Text('Dist PN: ${parsed.distributorPartNumber}',
                                style: const TextStyle(fontSize: 12)),
                          if (parsed.manufacturerPartNumber != null)
                            Text('Mfr PN: ${parsed.manufacturerPartNumber}',
                                style: const TextStyle(fontSize: 12)),
                          if (parsed.quantity != null)
                            Text(
                                'Qty: ${parsed.quantity! % 1 == 0 ? parsed.quantity!.toInt() : parsed.quantity}',
                                style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ],

                  // DigiKey lookup results
                  if (hasDigikeyData && digikeyConnected) ...[
                    const SizedBox(height: 16),
                    if (_digikeyLoading)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2)),
                            SizedBox(width: 8),
                            Text('Looking up on DigiKey...',
                                style: TextStyle(fontSize: 13)),
                          ],
                        ),
                      )
                    else if (_digikeyResults != null &&
                        _digikeyResults!.isNotEmpty) ...[
                      const Text('Found on DigiKey:',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 8),
                      ..._digikeyResults!.take(3).map(
                            (product) => _DigiKeyResultTile(
                              product: product,
                              onUse: () => _showLinkAndReceiveDialog(
                                  digikeyProduct: product),
                            ),
                          ),
                    ] else if (_digikeyResults != null &&
                        _digikeyResults!.isEmpty)
                      const Text('Not found on DigiKey',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: SaturdayColors.secondaryGrey,
                              fontSize: 13)),
                  ],

                  // Connect DigiKey prompt
                  if (hasDigikeyData && !digikeyConnected) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final launched =
                            await DigiKeyService.instance.connectAccount();
                        if (launched && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'Complete DigiKey login in your browser, then return here'),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.electrical_services, size: 18),
                      label: const Text('Connect DigiKey for auto-lookup'),
                    ),
                  ],

                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => _showLinkAndReceiveDialog(),
                    icon: const Icon(Icons.link),
                    label: const Text('Link to Part & Receive'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _resetToReady,
                    child: const Text('Skip'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReceivingView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Receiving inventory...'),
        ],
      ),
    );
  }

  Widget _buildSessionSummary() {
    return Container(
      color: SaturdayColors.primaryDark,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.receipt_long, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _sessionItems.map((i) => '${i.partName} x${i.quantity}').join(', '),
              style: const TextStyle(color: Colors.white, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${_sessionItems.length} items',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  // ---- Handlers ----

  void _handleBarcodeInput(String barcode) {
    _desktopController.clear();
    _processBarcode(barcode.trim());
  }

  void _handleCameraBarcode(BarcodeCapture capture) {
    if (_state != _ScanState.ready) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    setState(() => _cameraActive = false);
    _processBarcode(barcode.rawValue!.trim());
  }

  Future<void> _processBarcode(String barcode) async {
    if (barcode.isEmpty) return;

    HapticFeedback.mediumImpact();

    // Parse structured data early so we can determine the dedup key
    final earlyParsed = _matcher.parseBarcode(barcode);
    final isStructured = earlyParsed != null && !earlyParsed.isEmpty;

    // For structured barcodes (DigiKey ECIA), each package is unique
    // (different invoice/qty) so we don't deduplicate — you can scan
    // multiple packages of the same part.
    // For simple barcodes (Amazon FNSKU, etc.), deduplicate on the raw value.
    if (!isStructured) {
      final reference = 'Scanned: $barcode';
      if (_receivedBarcodes.contains(barcode)) {
        _showDuplicateWarning();
        return;
      }

      // Check DB for prior receives with this exact barcode
      final alreadyReceived =
          await InventoryRepository().hasReceiveWithReference(reference);
      if (alreadyReceived) {
        if (mounted) _showDuplicateWarning();
        return;
      }
    }

    setState(() {
      _state = _ScanState.matching;
      _lastBarcode = barcode;
      _lastParsedData = null;
      _digikeyResults = null;
      _digikeyLoading = false;
    });

    try {

      final result = await _matcher.match(barcode);

      if (!mounted) return;

      if (result != null) {
        setState(() {
          _state = _ScanState.matched;
          _matchResult = result;
          _lastParsedData = result.parsedData;
        });
      } else {
        // Parse barcode data even on no match (for DigiKey lookup)
        _lastParsedData = _matcher.parseBarcode(barcode);
        setState(() {
          _state = _ScanState.unmatched;
          _matchResult = null;
        });
        // Auto-trigger DigiKey lookup if we parsed an ECIA barcode
        if (_lastParsedData != null && !_lastParsedData!.isEmpty) {
          _lookupOnDigiKey();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error matching barcode: $e'),
              backgroundColor: SaturdayColors.error),
        );
        _resetToReady();
      }
    }
  }

  Future<void> _lookupOnDigiKey() async {
    if (_lastParsedData == null || _lastParsedData!.isEmpty) return;

    setState(() => _digikeyLoading = true);

    try {
      final results = await DigiKeyService.instance.lookupByBarcode(
        distributorPn: _lastParsedData!.distributorPartNumber,
        manufacturerPn: _lastParsedData!.manufacturerPartNumber,
      );

      if (mounted) {
        setState(() {
          _digikeyResults = results;
          _digikeyLoading = false;
        });
      }
    } on DigiKeyNotConnectedException {
      if (mounted) {
        setState(() {
          _digikeyResults = [];
          _digikeyLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _digikeyResults = [];
          _digikeyLoading = false;
        });
      }
    }
  }

  Future<void> _receiveMatched(BarcodeMatchResult result, double qty) async {
    setState(() => _state = _ScanState.receiving);

    try {
      final userId =
          SupabaseService.instance.client.auth.currentUser!.id;
      // For structured barcodes, include the parsed invoice/lot info in the reference
      // so each package receive is distinguishable. For simple barcodes, use the raw value.
      final String receiveRef;
      if (_lastParsedData != null && !_lastParsedData!.isEmpty) {
        final parts = <String>['SKU: ${result.supplierPart.supplierSku}'];
        if (_lastParsedData!.salesOrder != null) {
          parts.add('SO: ${_lastParsedData!.salesOrder}');
        }
        if (_lastParsedData!.purchaseOrder != null) {
          parts.add('PO: ${_lastParsedData!.purchaseOrder}');
        }
        receiveRef = 'Scanned: ${parts.join(', ')}';
      } else {
        receiveRef = 'Scanned: $_lastBarcode';
      }

      await ref.read(inventoryManagementProvider).receive(
            partId: result.part.id,
            quantity: qty,
            supplierId: result.supplierPart.supplierId,
            reference: receiveRef,
            performedBy: userId,
          );

      if (mounted) {
        _receivedBarcodes.add(_lastBarcode!);
        _sessionItems.add(_ReceivedItem(
          partName: result.part.name,
          quantity: qty,
        ));

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Received $qty ${result.part.unitOfMeasure.displayName} of ${result.part.name}'),
            backgroundColor: SaturdayColors.success,
            duration: const Duration(seconds: 2),
          ),
        );

        _resetToReady();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor: SaturdayColors.error),
        );
        _resetToReady();
      }
    }
  }

  Future<void> _showLinkAndReceiveDialog({DigiKeyProduct? digikeyProduct}) async {
    AppLogger.info('_showLinkAndReceiveDialog called, digikeyProduct: ${digikeyProduct?.digikeyPn}');

    final List<Part> parts;
    final List suppliers;
    try {
      parts = await ref.read(partsListProvider.future);
      suppliers = await ref.read(suppliersListProvider.future);
    } catch (e) {
      AppLogger.error('Failed to load parts/suppliers', e, StackTrace.current);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load data: $e'),
              backgroundColor: SaturdayColors.error),
        );
      }
      return;
    }
    if (!mounted) return;

    AppLogger.info('Loaded ${parts.length} parts, ${suppliers.length} suppliers');

    // Determine initial mode: create new if DigiKey product provided or no parts exist
    final bool startWithNew = digikeyProduct != null || parts.isEmpty;
    bool createNew = startWithNew;

    // New-part fields pre-filled from DigiKey
    final nameController = TextEditingController(
      text: digikeyProduct?.description ?? digikeyProduct?.manufacturerPn ?? '',
    );
    final partNumberController = TextEditingController(
      text: digikeyProduct?.digikeyPn ?? digikeyProduct?.manufacturerPn ?? '',
    );
    final descriptionController = TextEditingController(
      text: digikeyProduct != null
          ? [
              if (digikeyProduct.manufacturer != null) digikeyProduct.manufacturer!,
              if (digikeyProduct.category != null) digikeyProduct.category!,
              if (digikeyProduct.family != null) digikeyProduct.family!,
            ].join(' | ')
          : '',
    );

    // Existing-part selection
    String? selectedPartId;
    String? selectedSupplierId;

    // Pre-select DigiKey supplier when we have DigiKey/ECIA data
    if (digikeyProduct != null ||
        (_lastParsedData?.detectedFormat == 'DigiKey/ECIA')) {
      final dk = suppliers.where((s) {
        final name = (s.name as String).toLowerCase();
        return name.contains('digikey') || name.contains('digi-key');
      });
      if (dk.isNotEmpty) selectedSupplierId = dk.first.id as String;
    }

    final skuController = TextEditingController(
      text: digikeyProduct?.digikeyPn ?? _lastParsedData?.distributorPartNumber ?? _lastBarcode,
    );
    final defaultQty = _lastParsedData?.quantity;
    final qtyController = TextEditingController(
      text: defaultQty != null
          ? (defaultQty % 1 == 0 ? defaultQty.toInt().toString() : defaultQty.toString())
          : '1',
    );

    bool saving = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(createNew ? 'Create Part & Receive' : 'Link Barcode & Receive'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Mode toggle (only show if there are existing parts)
                if (parts.isNotEmpty) ...[
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('New Part'), icon: Icon(Icons.add, size: 16)),
                      ButtonSegment(value: false, label: Text('Existing Part'), icon: Icon(Icons.link, size: 16)),
                    ],
                    selected: {createNew},
                    onSelectionChanged: (v) => setDialogState(() => createNew = v.first),
                  ),
                  const SizedBox(height: 16),
                ],

                if (createNew) ...[
                  // -- New Part form --
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Part Name *'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: partNumberController,
                    decoration: const InputDecoration(labelText: 'Part Number *'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: descriptionController,
                    decoration: const InputDecoration(labelText: 'Description'),
                    maxLines: 2,
                  ),
                  if (digikeyProduct != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: SaturdayColors.light,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('DigiKey Info', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: SaturdayColors.secondaryGrey)),
                          if (digikeyProduct.manufacturer != null)
                            Text('Mfr: ${digikeyProduct.manufacturer}', style: const TextStyle(fontSize: 12)),
                          if (digikeyProduct.digikeyPn != null)
                            Text('DK PN: ${digikeyProduct.digikeyPn}', style: const TextStyle(fontSize: 12)),
                          if (digikeyProduct.unitPrice != null)
                            Text('Price: \$${digikeyProduct.unitPrice!.toStringAsFixed(4)}', style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ] else ...[
                  // -- Existing Part picker --
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Part *'),
                    isExpanded: true,
                    items: parts
                        .map((p) => DropdownMenuItem(
                            value: p.id,
                            child: Text('${p.name} (${p.partNumber})')))
                        .toList(),
                    onChanged: (v) => selectedPartId = v,
                  ),
                ],

                const SizedBox(height: 12),
                if (suppliers.isNotEmpty)
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Supplier (optional)'),
                    isExpanded: true,
                    value: selectedSupplierId,
                    items: [
                      const DropdownMenuItem<String>(value: null, child: Text('None')),
                      ...suppliers.map((s) => DropdownMenuItem(
                          value: s.id as String, child: Text(s.name as String))),
                    ],
                    onChanged: (v) => selectedSupplierId = v,
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: skuController,
                  decoration: const InputDecoration(labelText: 'Supplier SKU'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: qtyController,
                  decoration: const InputDecoration(labelText: 'Quantity to receive'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final qty = double.tryParse(qtyController.text);
                      if (qty == null || qty <= 0) return;

                      if (createNew) {
                        if (nameController.text.trim().isEmpty ||
                            partNumberController.text.trim().isEmpty) {
                          return;
                        }
                      } else {
                        if (selectedPartId == null) return;
                      }

                      setDialogState(() => saving = true);

                      try {
                        String partId;
                        String partName;

                        if (createNew) {
                          // Create the part
                          final newPart = await PartsRepository().createPart(
                            name: nameController.text.trim(),
                            partNumber: partNumberController.text.trim(),
                            description: descriptionController.text.trim().isNotEmpty
                                ? descriptionController.text.trim()
                                : null,
                            partType: PartType.component,
                            category: PartCategory.electronics,
                            unitOfMeasure: UnitOfMeasure.each,
                          );
                          partId = newPart.id;
                          partName = newPart.name;

                          // Auto-create DigiKey supplier if none selected and we have DK data
                          if (selectedSupplierId == null && digikeyProduct != null) {
                            // Query DB directly to avoid stale list
                            final allSuppliers = await SuppliersRepository().getSuppliers();
                            final existingDk = allSuppliers.where((s) =>
                                s.name.toLowerCase().contains('digikey') ||
                                s.name.toLowerCase().contains('digi-key'));
                            if (existingDk.isNotEmpty) {
                              selectedSupplierId = existingDk.first.id;
                            } else {
                              final dkSupplier = await SuppliersRepository().createSupplier(
                                name: 'DigiKey',
                                website: 'https://www.digikey.com',
                              );
                              selectedSupplierId = dkSupplier.id;
                            }
                          }
                        } else {
                          partId = selectedPartId!;
                          partName = parts.firstWhere((p) => p.id == partId).name;
                        }

                        // Link supplier part — for structured barcodes (ECIA/DigiKey),
                        // don't store the raw barcode as barcode_value since it's
                        // unique per package (contains invoice, qty, etc.)
                        final isStructuredBarcode =
                            _lastParsedData != null && !_lastParsedData!.isEmpty;
                        if (selectedSupplierId != null && skuController.text.isNotEmpty) {
                          try {
                            await SupplierPartsRepository().createSupplierPart(
                              partId: partId,
                              supplierId: selectedSupplierId!,
                              supplierSku: skuController.text,
                              barcodeValue: isStructuredBarcode ? null : _lastBarcode,
                              barcodeFormat: _lastParsedData?.detectedFormat,
                              unitCost: digikeyProduct?.unitPrice,
                              isPreferred: true,
                              url: digikeyProduct?.productUrl,
                            );
                          } catch (e) {
                            AppLogger.warning('Failed to create supplier part link: $e');
                          }
                        }

                        Navigator.pop(dialogContext);

                        // Receive inventory
                        setState(() => _state = _ScanState.receiving);
                        final userId = SupabaseService.instance.client.auth.currentUser!.id;

                        // Build a meaningful reference for the transaction
                        final String receiveRef;
                        if (isStructuredBarcode) {
                          final refParts = <String>['SKU: ${skuController.text}'];
                          if (_lastParsedData!.salesOrder != null) {
                            refParts.add('SO: ${_lastParsedData!.salesOrder}');
                          }
                          if (_lastParsedData!.purchaseOrder != null) {
                            refParts.add('PO: ${_lastParsedData!.purchaseOrder}');
                          }
                          receiveRef = 'Scanned: ${refParts.join(', ')}';
                        } else {
                          receiveRef = 'Scanned: $_lastBarcode';
                        }

                        await ref.read(inventoryManagementProvider).receive(
                              partId: partId,
                              quantity: qty,
                              supplierId: selectedSupplierId,
                              reference: receiveRef,
                              performedBy: userId,
                            );

                        if (mounted) {
                          _receivedBarcodes.add(_lastBarcode!);
                          _sessionItems.add(_ReceivedItem(
                            partName: partName,
                            quantity: qty,
                          ));
                          // Invalidate parts provider so new part shows up
                          ref.invalidate(partsListProvider);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  '${createNew ? "Created part & r" : "Linked barcode & r"}eceived $qty of $partName'),
                              backgroundColor: SaturdayColors.success,
                            ),
                          );
                        }
                      } catch (e) {
                        AppLogger.error('Link & receive failed', e, StackTrace.current);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text('Error: $e'),
                                backgroundColor: SaturdayColors.error),
                          );
                        }
                      }
                      _resetToReady();
                    },
              child: Text(createNew ? 'Create & Receive' : 'Link & Receive'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDuplicateWarning() {
    HapticFeedback.heavyImpact();
    _resetToReady();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.white),
            SizedBox(width: 8),
            Expanded(child: Text('This barcode has already been received')),
          ],
        ),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _resetToReady() {
    setState(() {
      _state = _ScanState.ready;
      _matchResult = null;
      _lastParsedData = null;
      _digikeyResults = null;
      _digikeyLoading = false;
      _cameraActive = true;
    });
    if (_isDesktop) {
      _desktopFocusNode.requestFocus();
    }
  }
}

class _DigiKeyResultTile extends StatelessWidget {
  final DigiKeyProduct product;
  final VoidCallback onUse;

  const _DigiKeyResultTile({required this.product, required this.onUse});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (product.manufacturer != null)
                        Text(product.manufacturer!,
                            style: const TextStyle(
                                fontSize: 11,
                                color: SaturdayColors.secondaryGrey)),
                      Text(
                        product.description ?? product.manufacturerPn ?? 'Unknown',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: onUse,
                  style: FilledButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  child: const Text('Use'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                if (product.digikeyPn != null)
                  Text('DK: ${product.digikeyPn}',
                      style: const TextStyle(
                          fontSize: 11, color: SaturdayColors.secondaryGrey)),
                if (product.manufacturerPn != null)
                  Text('Mfr: ${product.manufacturerPn}',
                      style: const TextStyle(
                          fontSize: 11, color: SaturdayColors.secondaryGrey)),
                if (product.unitPrice != null)
                  Text('\$${product.unitPrice!.toStringAsFixed(4)}',
                      style: const TextStyle(
                          fontSize: 11,
                          color: SaturdayColors.success,
                          fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _ScanState { ready, matching, matched, unmatched, receiving }

class _ReceivedItem {
  final String partName;
  final double quantity;
  _ReceivedItem({required this.partName, required this.quantity});
}
