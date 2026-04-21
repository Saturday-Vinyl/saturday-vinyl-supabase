import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/providers/slot_editor_state_provider.dart';

/// Toolbar for the WYSIWYG slot editor — mode toggle, clip controls, save button.
class SlotEditorToolbar extends ConsumerWidget {
  final VoidCallback onSave;
  final VoidCallback? onAddClipPoint;

  const SlotEditorToolbar({
    super.key,
    required this.onSave,
    this.onAddClipPoint,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(slotEditorProvider);
    final notifier = ref.read(slotEditorProvider.notifier);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: SaturdayColors.white,
        border: Border(
          bottom: BorderSide(color: SaturdayColors.light, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Mode toggle
          SegmentedButton<SlotEditorMode>(
            segments: const [
              ButtonSegment(
                value: SlotEditorMode.transform,
                label: Text('Transform'),
                icon: Icon(Icons.crop_free),
              ),
              ButtonSegment(
                value: SlotEditorMode.clip,
                label: Text('Clip'),
                icon: Icon(Icons.content_cut),
              ),
              ButtonSegment(
                value: SlotEditorMode.preview,
                label: Text('Preview'),
                icon: Icon(Icons.visibility),
              ),
            ],
            selected: {state.mode},
            onSelectionChanged: (s) => notifier.setMode(s.first),
          ),

          const SizedBox(width: 16),

          // Clip-mode controls
          if (state.mode == SlotEditorMode.clip) ...[
            TextButton.icon(
              onPressed: onAddClipPoint,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Point'),
            ),
            TextButton.icon(
              onPressed: state.clipPoints.length > 3
                  ? notifier.removeLastClipPoint
                  : null,
              icon: const Icon(Icons.remove, size: 18),
              label: const Text('Remove Last'),
            ),
            TextButton.icon(
              onPressed: notifier.copyTransformToClip,
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copy from Transform'),
            ),
          ],

          // Coordinate readout for selected point
          if (state.dragIndex != null &&
              state.mode != SlotEditorMode.preview) ...[
            const SizedBox(width: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: SaturdayColors.light,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Point ${state.dragIndex}: '
                '(${state.activePoints[state.dragIndex!].dx.toStringAsFixed(1)}, '
                '${state.activePoints[state.dragIndex!].dy.toStringAsFixed(1)})',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
          ],

          const Spacer(),

          // Dirty indicator
          if (state.isDirty)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Text(
                'Unsaved changes',
                style: TextStyle(
                  color: SaturdayColors.warning,
                  fontSize: 12,
                ),
              ),
            ),

          // Save button
          FilledButton.icon(
            onPressed: state.isDirty && !state.isSaving ? onSave : null,
            icon: state.isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save),
            label: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
