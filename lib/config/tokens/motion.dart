import 'package:flutter/animation.dart';

/// Saturday motion tokens.
///
/// Three named curves only — none of them spring — per
/// `shared-docs/foundation/constitution.md` (Tokens → Motion). Bounce, spring,
/// and elastic curves are banned everywhere in the product.
///
/// The named gestures (`arrive`, `recede`, `pulse`, `settle`, `blend`,
/// `override`, `hold`) compose these primitives. The full gesture helper
/// lands in a later step alongside the Skeleton primitive; for now this file
/// only exposes the underlying durations and curves so the token layer is
/// complete.
class SaturdayMotion {
  SaturdayMotion._();

  // ---------------------------------------------------------------------------
  // Durations
  // ---------------------------------------------------------------------------

  /// 180 ms — quick reflows without urgency (`settle`).
  static const Duration quick = Duration(milliseconds: 180);

  /// 320 ms — content lands or dismisses (`arrive`, `recede`).
  static const Duration standard = Duration(milliseconds: 320);

  /// 1200 ms — color transitions, stand glow (`blend`).
  static const Duration slow = Duration(milliseconds: 1200);

  /// 1500 ms — single-beat invitation (`pulse`).
  static const Duration pulse = Duration(milliseconds: 1500);

  /// Lower bound of the stand fade range. Working window pending tuning.
  static const Duration standFadeMin = Duration(seconds: 30);

  /// Upper bound of the stand fade range. Working window pending tuning.
  static const Duration standFadeMax = Duration(seconds: 60);

  /// Reduced-motion duration. When `MediaQuery.disableAnimations` is on, every
  /// gesture collapses to roughly this length and pulse curves are removed
  /// entirely (single appearance instead of a brightness curve).
  static const Duration reduced = Duration(milliseconds: 100);

  // ---------------------------------------------------------------------------
  // Curves
  // ---------------------------------------------------------------------------

  /// Content arriving — decelerating outro.
  static const Cubic easeArrive = Cubic(0.16, 1.0, 0.3, 1.0);

  /// Content leaving — accelerating intro.
  static const Cubic easeRecede = Cubic(0.7, 0.0, 0.84, 0.0);

  /// Color blends and quiet reflows — symmetric ease.
  static const Cubic easeBlend = Cubic(0.45, 0.0, 0.55, 1.0);
}
