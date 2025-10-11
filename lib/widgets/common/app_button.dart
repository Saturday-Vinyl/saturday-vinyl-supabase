import 'package:flutter/material.dart';
import '../../config/theme.dart';

enum AppButtonStyle {
  primary,
  secondary,
  text,
}

class AppButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final AppButtonStyle style;
  final bool isLoading;
  final IconData? icon;
  final double? width;

  const AppButton({
    super.key,
    required this.text,
    this.onPressed,
    this.style = AppButtonStyle.primary,
    this.isLoading = false,
    this.icon,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDisabled = onPressed == null || isLoading;

    switch (style) {
      case AppButtonStyle.primary:
        return _buildPrimaryButton(context, isDisabled);
      case AppButtonStyle.secondary:
        return _buildSecondaryButton(context, isDisabled);
      case AppButtonStyle.text:
        return _buildTextButton(context, isDisabled);
    }
  }

  Widget _buildPrimaryButton(BuildContext context, bool isDisabled) {
    return SizedBox(
      width: width,
      height: 48,
      child: ElevatedButton(
        onPressed: isDisabled ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: SaturdayColors.primaryDark,
          disabledBackgroundColor: SaturdayColors.secondaryGrey,
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white70,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: 0,
        ),
        child: _buildButtonContent(Colors.white),
      ),
    );
  }

  Widget _buildSecondaryButton(BuildContext context, bool isDisabled) {
    return SizedBox(
      width: width,
      height: 48,
      child: OutlinedButton(
        onPressed: isDisabled ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: SaturdayColors.primaryDark,
          disabledForegroundColor: SaturdayColors.secondaryGrey,
          side: BorderSide(
            color: isDisabled ? SaturdayColors.secondaryGrey : SaturdayColors.primaryDark,
            width: 1.5,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: _buildButtonContent(SaturdayColors.primaryDark),
      ),
    );
  }

  Widget _buildTextButton(BuildContext context, bool isDisabled) {
    return SizedBox(
      width: width,
      height: 48,
      child: TextButton(
        onPressed: isDisabled ? null : onPressed,
        style: TextButton.styleFrom(
          foregroundColor: SaturdayColors.primaryDark,
          disabledForegroundColor: SaturdayColors.secondaryGrey,
        ),
        child: _buildButtonContent(SaturdayColors.primaryDark),
      ),
    );
  }

  Widget _buildButtonContent(Color iconColor) {
    if (isLoading) {
      return SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(iconColor),
        ),
      );
    }

    if (icon != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }

    return Text(text);
  }
}
