import 'dart:ui' show Offset;

import 'package:equatable/equatable.dart';

/// Value object representing the transform and clip data for an album compositing slot.
///
/// All coordinates are in source image pixel space.
class SlotData extends Equatable {
  /// 4 corners defining the perspective quad where the album cover maps to.
  /// Order: top-left, top-right, bottom-right, bottom-left (clockwise).
  final List<Offset> transform;

  /// N-point polygon defining the visible area (album art outside is clipped).
  /// Minimum 3 points.
  final List<Offset> clip;

  const SlotData({
    required this.transform,
    required this.clip,
  });

  /// Default slot data with a centered rectangle.
  factory SlotData.defaultForSize(double width, double height) {
    const margin = 0.2;
    final l = width * margin;
    final r = width * (1 - margin);
    final t = height * margin;
    final b = height * (1 - margin);
    final quad = [Offset(l, t), Offset(r, t), Offset(r, b), Offset(l, b)];
    return SlotData(transform: quad, clip: List.of(quad));
  }

  factory SlotData.fromJson(Map<String, dynamic> json) {
    return SlotData(
      transform: (json['transform'] as List)
          .map((p) => Offset(
                (p['x'] as num).toDouble(),
                (p['y'] as num).toDouble(),
              ))
          .toList(),
      clip: (json['clip'] as List)
          .map((p) => Offset(
                (p['x'] as num).toDouble(),
                (p['y'] as num).toDouble(),
              ))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'transform':
            transform.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
        'clip': clip.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
      };

  SlotData copyWith({List<Offset>? transform, List<Offset>? clip}) => SlotData(
        transform: transform ?? this.transform,
        clip: clip ?? this.clip,
      );

  bool get isValid => transform.length == 4 && clip.length >= 3;

  @override
  List<Object?> get props => [transform, clip];

  @override
  String toString() =>
      'SlotData(transform: ${transform.length} pts, clip: ${clip.length} pts)';
}
