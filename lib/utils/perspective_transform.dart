import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:vector_math/vector_math_64.dart' show Matrix4;

/// Computes a 3×3 projective (homography) matrix that maps a source rectangle
/// to 4 arbitrary destination corners, then embeds it into a Flutter Matrix4.
class PerspectiveTransform {
  final Float64List _m; // 3×3 row-major (9 elements)

  PerspectiveTransform._(this._m);

  /// Compute the perspective transform mapping the rectangle
  /// (0, 0) → (srcWidth, srcHeight) to the 4 destination corners
  /// [topLeft, topRight, bottomRight, bottomLeft].
  factory PerspectiveTransform.compute({
    required double srcWidth,
    required double srcHeight,
    required List<Offset> dst,
  }) {
    assert(dst.length == 4, 'Exactly 4 destination corners required');

    // Source corners
    final src = [
      const Offset(0, 0),
      Offset(srcWidth, 0),
      Offset(srcWidth, srcHeight),
      Offset(0, srcHeight),
    ];

    // Build 8×8 system: A·h = b
    // For each pair (sx, sy) → (dx, dy):
    //   h0*sx + h1*sy + h2 - h6*sx*dx - h7*sy*dx = dx
    //   h3*sx + h4*sy + h5 - h6*sx*dy - h7*sy*dy = dy
    final a = Float64List(64);
    final b = Float64List(8);

    for (int i = 0; i < 4; i++) {
      final sx = src[i].dx, sy = src[i].dy;
      final dx = dst[i].dx, dy = dst[i].dy;
      final r0 = i * 2, r1 = r0 + 1;

      a[r0 * 8 + 0] = sx;
      a[r0 * 8 + 1] = sy;
      a[r0 * 8 + 2] = 1;
      a[r0 * 8 + 6] = -sx * dx;
      a[r0 * 8 + 7] = -sy * dx;
      b[r0] = dx;

      a[r1 * 8 + 3] = sx;
      a[r1 * 8 + 4] = sy;
      a[r1 * 8 + 5] = 1;
      a[r1 * 8 + 6] = -sx * dy;
      a[r1 * 8 + 7] = -sy * dy;
      b[r1] = dy;
    }

    final h = _solve(a, b, 8);

    return PerspectiveTransform._(Float64List.fromList([
      h[0], h[1], h[2],
      h[3], h[4], h[5],
      h[6], h[7], 1.0,
    ]));
  }

  /// Embed the 3×3 projective matrix into a 4×4 Matrix4 for Flutter's canvas.
  ///
  /// Maps the 3×3 rows/cols {0,1,2} into Matrix4 rows/cols {0,1,3},
  /// leaving row 2 / col 2 as the identity (z-axis pass-through).
  /// Matrix4 storage is column-major.
  Matrix4 toMatrix4() {
    return Matrix4(
      _m[0], _m[3], 0, _m[6], // column 0
      _m[1], _m[4], 0, _m[7], // column 1
      0,     0,     1, 0,     // column 2
      _m[2], _m[5], 0, _m[8], // column 3
    );
  }

  /// Gaussian elimination with partial pivoting for an n×n system.
  static Float64List _solve(Float64List a, Float64List b, int n) {
    // Build augmented matrix [A|b]
    final aug = List<Float64List>.generate(n, (i) {
      final row = Float64List(n + 1);
      for (int j = 0; j < n; j++) {
        row[j] = a[i * n + j];
      }
      row[n] = b[i];
      return row;
    });

    // Forward elimination
    for (int col = 0; col < n; col++) {
      // Partial pivoting
      int maxRow = col;
      double maxVal = aug[col][col].abs();
      for (int row = col + 1; row < n; row++) {
        final v = aug[row][col].abs();
        if (v > maxVal) {
          maxVal = v;
          maxRow = row;
        }
      }
      if (maxRow != col) {
        final tmp = aug[col];
        aug[col] = aug[maxRow];
        aug[maxRow] = tmp;
      }

      final pivot = aug[col][col];
      if (pivot.abs() < 1e-12) {
        throw StateError('Singular matrix in perspective transform');
      }

      for (int row = col + 1; row < n; row++) {
        final factor = aug[row][col] / pivot;
        for (int j = col; j <= n; j++) {
          aug[row][j] -= factor * aug[col][j];
        }
      }
    }

    // Back substitution
    final x = Float64List(n);
    for (int i = n - 1; i >= 0; i--) {
      x[i] = aug[i][n];
      for (int j = i + 1; j < n; j++) {
        x[i] -= aug[i][j] * x[j];
      }
      x[i] /= aug[i][i];
    }
    return x;
  }
}
