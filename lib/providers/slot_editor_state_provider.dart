import 'dart:ui' show Offset;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/models/slot_data.dart';

/// The active editing mode in the slot editor
enum SlotEditorMode { transform, clip, preview }

/// Immutable state for the WYSIWYG slot editor
class SlotEditorState {
  final SlotEditorMode mode;
  final List<Offset> transformCorners; // always length 4
  final List<Offset> clipPoints; // length >= 3
  final int? dragIndex; // which point is being dragged (null = none)
  final bool isDirty;
  final bool isSaving;

  const SlotEditorState({
    this.mode = SlotEditorMode.transform,
    required this.transformCorners,
    required this.clipPoints,
    this.dragIndex,
    this.isDirty = false,
    this.isSaving = false,
  });

  List<Offset> get activePoints =>
      mode == SlotEditorMode.transform ? transformCorners : clipPoints;

  SlotData toSlotData() => SlotData(
        transform: transformCorners,
        clip: clipPoints,
      );

  SlotEditorState copyWith({
    SlotEditorMode? mode,
    List<Offset>? transformCorners,
    List<Offset>? clipPoints,
    int? Function()? dragIndex,
    bool? isDirty,
    bool? isSaving,
  }) {
    return SlotEditorState(
      mode: mode ?? this.mode,
      transformCorners: transformCorners ?? this.transformCorners,
      clipPoints: clipPoints ?? this.clipPoints,
      dragIndex: dragIndex != null ? dragIndex() : this.dragIndex,
      isDirty: isDirty ?? this.isDirty,
      isSaving: isSaving ?? this.isSaving,
    );
  }
}

/// StateNotifier managing the interactive editor state
class SlotEditorNotifier extends StateNotifier<SlotEditorState> {
  SlotEditorNotifier(SlotData initial)
      : super(SlotEditorState(
          transformCorners: List.of(initial.transform),
          clipPoints: List.of(initial.clip),
        ));

  void setMode(SlotEditorMode mode) =>
      state = state.copyWith(mode: mode, dragIndex: () => null);

  /// Find the nearest point within hit radius and start dragging it
  void onPointerDown(Offset position, {double hitRadius = 20.0}) {
    final points = state.activePoints;
    int? nearest;
    double nearestDist = hitRadius;
    for (int i = 0; i < points.length; i++) {
      final d = (points[i] - position).distance;
      if (d < nearestDist) {
        nearestDist = d;
        nearest = i;
      }
    }
    if (nearest != null) {
      state = state.copyWith(dragIndex: () => nearest);
    }
  }

  /// Move the currently-dragged point
  void onPointerMove(Offset position) {
    if (state.dragIndex == null) return;
    final idx = state.dragIndex!;

    if (state.mode == SlotEditorMode.transform) {
      final updated = List<Offset>.of(state.transformCorners);
      updated[idx] = position;
      state = state.copyWith(transformCorners: updated, isDirty: true);
    } else if (state.mode == SlotEditorMode.clip) {
      final updated = List<Offset>.of(state.clipPoints);
      updated[idx] = position;
      state = state.copyWith(clipPoints: updated, isDirty: true);
    }
  }

  /// Release the drag
  void onPointerUp() => state = state.copyWith(dragIndex: () => null);

  /// Add a new clip point at the given position
  void addClipPoint(Offset position) {
    if (state.mode != SlotEditorMode.clip) return;
    final updated = [...state.clipPoints, position];
    state = state.copyWith(clipPoints: updated, isDirty: true);
  }

  /// Remove the last clip point (minimum 3)
  void removeLastClipPoint() {
    if (state.clipPoints.length <= 3) return;
    final updated = state.clipPoints.sublist(0, state.clipPoints.length - 1);
    state = state.copyWith(clipPoints: updated, isDirty: true);
  }

  /// Copy the transform quad to the clip polygon as a starting point
  void copyTransformToClip() {
    state = state.copyWith(
      clipPoints: List.of(state.transformCorners),
      isDirty: true,
    );
  }

  void setSaving(bool saving) => state = state.copyWith(isSaving: saving);

  void markClean() => state = state.copyWith(isDirty: false);
}

/// Provider for the slot editor state.
/// Must be overridden with initial SlotData when the editor screen mounts.
final slotEditorProvider =
    StateNotifierProvider.autoDispose<SlotEditorNotifier, SlotEditorState>(
  (ref) => throw UnimplementedError('Must override with initial SlotData'),
);
