/// Saturday spacing tokens.
///
/// Linear 4-pixel scale from `shared-docs/foundation/constitution.md`
/// (Tokens → Spacing). Values like 13 or 19 are not allowed — change the
/// layout or change the scale.
///
/// The listening room reaches for the high end (atmospheric, `space16`/
/// `space24`). The archive uses tight stops within regions and high stops
/// between regions.
class SaturdaySpace {
  SaturdaySpace._();

  /// 4 — tight component-internal.
  static const double space1 = 4;

  /// 8 — component-internal.
  static const double space2 = 8;

  /// 12 — between related elements.
  static const double space3 = 12;

  /// 16 — base gap.
  static const double space4 = 16;

  /// 24 — between groups within a section.
  static const double space6 = 24;

  /// 32 — between sections.
  static const double space8 = 32;

  /// 48 — between major regions.
  static const double space12 = 48;

  /// 64 — atmospheric page-level breathing.
  static const double space16 = 64;

  /// 96 — large compositional space; the listening room uses this often.
  static const double space24 = 96;
}
