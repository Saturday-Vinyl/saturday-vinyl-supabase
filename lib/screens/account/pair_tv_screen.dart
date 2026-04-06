import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/providers/supabase_provider.dart';

class PairTvScreen extends ConsumerStatefulWidget {
  const PairTvScreen({super.key});

  @override
  ConsumerState<PairTvScreen> createState() => _PairTvScreenState();
}

class _PairTvScreenState extends ConsumerState<PairTvScreen> {
  final _codeController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMessage;
  bool _success = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submitCode() async {
    final code = _codeController.text.toUpperCase().trim();
    if (code.length != 6) {
      setState(
        () =>
            _errorMessage = 'Please enter the 6-character code from your TV',
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final client = ref.read(supabaseClientProvider);
      final response = await client.functions.invoke(
        'device-auth-claim',
        body: {'user_code': code},
      );

      if (!mounted) return;

      if (response.status == 200) {
        setState(() => _success = true);
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          Navigator.of(context).pop();
        }
      } else {
        final data = response.data as Map<String, dynamic>?;
        setState(
          () =>
              _errorMessage =
                  data?['error'] as String? ?? 'Something went wrong',
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Network error. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pair TV')),
      body: ListView(
        padding: Spacing.pagePadding,
        children: [
          if (_success) ...[
            const SizedBox(height: Spacing.xxxl),
            Icon(
              Icons.check_circle,
              size: 64,
              color: SaturdayColors.success,
            ),
            const SizedBox(height: Spacing.md),
            Text(
              'TV paired successfully!',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
          ] else ...[
            const SizedBox(height: Spacing.md),
            Text(
              'Enter the code shown on your TV',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Spacing.xl),
            Container(
              decoration: AppDecorations.card,
              padding: Spacing.cardPadding,
              child: TextField(
                controller: _codeController,
                maxLength: 6,
                textCapitalization: TextCapitalization.characters,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.headlineMedium?.copyWith(letterSpacing: 8),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
                  UpperCaseTextFormatter(),
                ],
                decoration: const InputDecoration(
                  hintText: 'XXXXXX',
                  counterText: '',
                  border: InputBorder.none,
                ),
                onSubmitted: (_) => _submitCode(),
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: Spacing.md),
              Text(
                _errorMessage!,
                style: TextStyle(color: SaturdayColors.error),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: Spacing.xl),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isSubmitting ? null : _submitCode,
                child:
                    _isSubmitting
                        ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Text('Pair'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
