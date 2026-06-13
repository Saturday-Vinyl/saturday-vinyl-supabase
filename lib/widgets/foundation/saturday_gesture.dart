import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/config/tokens/tokens.dart';

/// Named motion gestures, per the Saturday constitution.
///
/// The constitution defines seven gestures composed from three curves and a
/// small set of durations:
///
/// | Gesture     | Duration               | Curve         | When                                 |
/// |-------------|------------------------|---------------|--------------------------------------|
/// | `arrive`    | [SaturdayMotion.standard] | `easeArrive`  | Content lands, screens appear        |
/// | `recede`    | [SaturdayMotion.standard] | `easeRecede`  | Content dismissed, invitations end   |
/// | `pulse`     | [SaturdayMotion.pulse]    | `easeBlend`   | Single-beat invitation (once only)   |
/// | `settle`    | [SaturdayMotion.quick]    | `easeBlend`   | Layout reflow without urgency        |
/// | `blend`     | [SaturdayMotion.slow]     | `easeBlend`   | Color transitions (stand glow)       |
/// | `override`  | `Duration.zero`           | none          | User-initiated state change          |
/// | `hold`      | —                         | —             | Stillness; the system at rest        |
///
/// This file ships widget helpers for the common cases ([SaturdayArrive],
/// [SaturdayPulse]) and exposes the rest as constants so call sites can
/// build their own transitions (page routes, AnimatedSwitcher, implicit
/// animations) on top of the same primitives.
///
/// All helpers honor `MediaQuery.disableAnimations` (which reflects iOS's
/// "Reduce Motion" setting and Android's equivalent): durations collapse to
/// [SaturdayMotion.reduced] and pulse becomes a single appearance instead
/// of a brightness curve.
class SaturdayGesture {
  SaturdayGesture._();

  /// Duration to use for `arrive` and `recede`, with reduced-motion respect.
  static Duration durationFor(BuildContext context, Duration intended) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      return SaturdayMotion.reduced;
    }
    return intended;
  }
}

// ============================================================================
// arrive
// ============================================================================

/// Plays an `arrive` gesture once when the widget mounts.
///
/// The child fades in from `0` opacity and translates `8` logical pixels up
/// to its final position over [SaturdayMotion.standard], using
/// [SaturdayMotion.easeArrive]. Reduced-motion users see a single immediate
/// appearance with no translation.
class SaturdayArrive extends StatefulWidget {
  const SaturdayArrive({
    super.key,
    required this.child,
    this.delay = Duration.zero,
  });

  final Widget child;

  /// Hold the entrance for this long after mount. Useful for staggering
  /// children so they don't all arrive on the same frame.
  final Duration delay;

  @override
  State<SaturdayArrive> createState() => _SaturdayArriveState();
}

class _SaturdayArriveState extends State<SaturdayArrive>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: SaturdayMotion.standard,
    );
    _scheduleStart();
  }

  void _scheduleStart() {
    if (widget.delay == Duration.zero) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controller.forward();
      });
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduced) {
      return widget.child;
    }

    _controller.duration = SaturdayMotion.standard;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = SaturdayMotion.easeArrive.transform(_controller.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 8),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

// ============================================================================
// pulse
// ============================================================================

/// Plays a `pulse` gesture **exactly once**, then holds.
///
/// The constitution forbids `animation-iteration-count: infinite` on pulse —
/// a pulse that repeats until tapped is a notification, and Saturday has no
/// notifications. This widget enforces the single-shot constraint at the
/// type level: there is no `loop` option.
///
/// The child animates from `0.6` opacity → `1.0` → `0.85` over
/// [SaturdayMotion.pulse], using [SaturdayMotion.easeBlend], and then stays
/// at `0.85` opacity. Reduced-motion users see a single immediate appearance.
class SaturdayPulse extends StatefulWidget {
  const SaturdayPulse({super.key, required this.child});

  final Widget child;

  @override
  State<SaturdayPulse> createState() => _SaturdayPulseState();
}

class _SaturdayPulseState extends State<SaturdayPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: SaturdayMotion.pulse,
    );
    _opacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.6, end: 1.0),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.85),
        weight: 60,
      ),
    ]).animate(
      CurvedAnimation(parent: _controller, curve: SaturdayMotion.easeBlend),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduced) {
      return widget.child;
    }

    return AnimatedBuilder(
      animation: _opacity,
      builder: (context, child) =>
          Opacity(opacity: _opacity.value, child: child),
      child: widget.child,
    );
  }
}
