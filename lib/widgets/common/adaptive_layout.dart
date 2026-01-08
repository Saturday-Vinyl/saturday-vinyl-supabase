import 'package:flutter/material.dart';

/// Breakpoints for responsive layouts.
class Breakpoints {
  Breakpoints._();

  /// Phone width threshold (< 600dp is considered phone).
  static const double phone = 600;

  /// Tablet width threshold (>= 600dp and < 900dp is considered tablet).
  static const double tablet = 900;

  /// Desktop width threshold (>= 900dp is considered desktop).
  static const double desktop = 1200;
}

/// Device type based on screen size.
enum DeviceType {
  /// Phone (< 600dp width).
  phone,

  /// Tablet (>= 600dp width).
  tablet,

  /// Desktop (>= 900dp width).
  desktop,
}

/// Orientation helper.
enum LayoutOrientation {
  portrait,
  landscape,
}

/// Utility class for determining device characteristics.
class AdaptiveLayout {
  AdaptiveLayout._();

  /// Returns the device type based on screen width.
  static DeviceType getDeviceType(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= Breakpoints.desktop) return DeviceType.desktop;
    if (width >= Breakpoints.phone) return DeviceType.tablet;
    return DeviceType.phone;
  }

  /// Returns whether the device is a phone.
  static bool isPhone(BuildContext context) {
    return getDeviceType(context) == DeviceType.phone;
  }

  /// Returns whether the device is a tablet.
  static bool isTablet(BuildContext context) {
    return getDeviceType(context) == DeviceType.tablet;
  }

  /// Returns whether the device is tablet or larger.
  static bool isTabletOrLarger(BuildContext context) {
    final type = getDeviceType(context);
    return type == DeviceType.tablet || type == DeviceType.desktop;
  }

  /// Returns whether the device is in landscape orientation.
  static bool isLandscape(BuildContext context) {
    return MediaQuery.orientationOf(context) == Orientation.landscape;
  }

  /// Returns whether the device is in portrait orientation.
  static bool isPortrait(BuildContext context) {
    return MediaQuery.orientationOf(context) == Orientation.portrait;
  }

  /// Returns the current layout orientation.
  static LayoutOrientation getOrientation(BuildContext context) {
    return isLandscape(context)
        ? LayoutOrientation.landscape
        : LayoutOrientation.portrait;
  }

  /// Returns true if we should show a dual-pane layout.
  ///
  /// This is typically true for tablets in landscape orientation.
  static bool shouldShowDualPane(BuildContext context) {
    return isTabletOrLarger(context) && isLandscape(context);
  }

  /// Returns the number of columns for a grid based on screen width.
  static int getGridColumnCount(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= Breakpoints.desktop) return 5;
    if (width >= Breakpoints.tablet) return 4;
    if (width >= Breakpoints.phone) return 3;
    return 2;
  }

  /// Returns the recommended content width for centered layouts.
  static double getContentMaxWidth(BuildContext context) {
    final type = getDeviceType(context);
    switch (type) {
      case DeviceType.phone:
        return double.infinity;
      case DeviceType.tablet:
        return 720;
      case DeviceType.desktop:
        return 960;
    }
  }
}

/// A widget that builds different layouts based on device type.
class AdaptiveBuilder extends StatelessWidget {
  const AdaptiveBuilder({
    super.key,
    required this.phone,
    this.tablet,
    this.desktop,
  });

  /// Builder for phone layouts.
  final WidgetBuilder phone;

  /// Builder for tablet layouts. Falls back to phone if not provided.
  final WidgetBuilder? tablet;

  /// Builder for desktop layouts. Falls back to tablet, then phone if not provided.
  final WidgetBuilder? desktop;

  @override
  Widget build(BuildContext context) {
    final type = AdaptiveLayout.getDeviceType(context);

    switch (type) {
      case DeviceType.desktop:
        return (desktop ?? tablet ?? phone)(context);
      case DeviceType.tablet:
        return (tablet ?? phone)(context);
      case DeviceType.phone:
        return phone(context);
    }
  }
}

/// A widget that shows different layouts for portrait vs landscape.
class OrientationBuilder2 extends StatelessWidget {
  const OrientationBuilder2({
    super.key,
    required this.portrait,
    required this.landscape,
  });

  /// Builder for portrait orientation.
  final WidgetBuilder portrait;

  /// Builder for landscape orientation.
  final WidgetBuilder landscape;

  @override
  Widget build(BuildContext context) {
    return AdaptiveLayout.isLandscape(context)
        ? landscape(context)
        : portrait(context);
  }
}

/// A widget that conditionally shows dual-pane layout.
class DualPaneLayout extends StatelessWidget {
  const DualPaneLayout({
    super.key,
    required this.primary,
    required this.secondary,
    this.primaryFlex = 1,
    this.secondaryFlex = 1,
    this.divider,
    this.fallbackToSinglePane = true,
    this.singlePaneBuilder,
  });

  /// The primary pane (typically on the left).
  final Widget primary;

  /// The secondary pane (typically on the right).
  final Widget secondary;

  /// Flex factor for primary pane.
  final int primaryFlex;

  /// Flex factor for secondary pane.
  final int secondaryFlex;

  /// Optional divider between panes.
  final Widget? divider;

  /// Whether to fall back to single pane on phones.
  final bool fallbackToSinglePane;

  /// Custom builder for single pane mode. If not provided, shows primary only.
  final Widget Function(BuildContext, Widget primary, Widget secondary)?
      singlePaneBuilder;

  @override
  Widget build(BuildContext context) {
    final showDualPane = AdaptiveLayout.shouldShowDualPane(context);

    if (!showDualPane && fallbackToSinglePane) {
      if (singlePaneBuilder != null) {
        return singlePaneBuilder!(context, primary, secondary);
      }
      return primary;
    }

    return Row(
      children: [
        Expanded(
          flex: primaryFlex,
          child: primary,
        ),
        if (divider != null) divider!,
        Expanded(
          flex: secondaryFlex,
          child: secondary,
        ),
      ],
    );
  }
}
