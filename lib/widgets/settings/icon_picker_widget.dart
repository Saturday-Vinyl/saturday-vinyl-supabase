import 'package:flutter/material.dart';
import '../../config/theme.dart';

/// Icon picker dialog for selecting Material Icons for machine macros
class IconPickerWidget extends StatefulWidget {
  const IconPickerWidget({super.key});

  @override
  State<IconPickerWidget> createState() => _IconPickerWidgetState();
}

class _IconPickerWidgetState extends State<IconPickerWidget> {
  String? _selectedIconName;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Available icons for machine operations
  static const Map<String, IconData> _availableIcons = {
    // Power and control
    'power': Icons.power,
    'power_off': Icons.power_off,
    'power_settings_new': Icons.power_settings_new,

    // Playback
    'play_arrow': Icons.play_arrow,
    'pause': Icons.pause,
    'stop': Icons.stop,
    'stop_circle': Icons.stop_circle,

    // Tools and building
    'build': Icons.build,
    'construction': Icons.construction,
    'handyman': Icons.handyman,
    'settings': Icons.settings,
    'home': Icons.home,

    // Laser specific
    'flash_on': Icons.flash_on,
    'flash_off': Icons.flash_off,
    'flash_auto': Icons.flash_auto,
    'visibility': Icons.visibility,
    'visibility_off': Icons.visibility_off,

    // Fluid/coolant
    'opacity': Icons.opacity,
    'water_drop': Icons.water_drop,
    'air': Icons.air,
    'clear': Icons.clear,

    // Movement
    'refresh': Icons.refresh,
    'cached': Icons.cached,
    'rotate_right': Icons.rotate_right,
    'rotate_left': Icons.rotate_left,
    'sync': Icons.sync,

    // Directional
    'arrow_upward': Icons.arrow_upward,
    'arrow_downward': Icons.arrow_downward,
    'arrow_forward': Icons.arrow_forward,
    'arrow_back': Icons.arrow_back,
    'north': Icons.north,
    'south': Icons.south,
    'east': Icons.east,
    'west': Icons.west,

    // Actions
    'add': Icons.add,
    'remove': Icons.remove,
    'check': Icons.check,
    'close': Icons.close,
    'done': Icons.done,

    // Precision
    'speed': Icons.speed,
    'slow_motion_video': Icons.slow_motion_video,
    'fast_forward': Icons.fast_forward,
    'fast_rewind': Icons.fast_rewind,

    // Other
    'bolt': Icons.bolt,
    'electric_bolt': Icons.electric_bolt,
    'troubleshoot': Icons.troubleshoot,
    'category': Icons.category,
  };

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<MapEntry<String, IconData>> get _filteredIcons {
    if (_searchQuery.isEmpty) {
      return _availableIcons.entries.toList();
    }

    return _availableIcons.entries.where((entry) {
      return entry.key.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filteredIcons = _filteredIcons;

    return Dialog(
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 700),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: SaturdayColors.primaryDark,
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  const Text(
                    'Select Icon',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Search bar
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search icons...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            setState(() {
                              _searchController.clear();
                              _searchQuery = '';
                            });
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
              ),
            ),

            // Selected icon display
            if (_selectedIconName != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: SaturdayColors.primaryDark.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Text(
                        'Selected: ',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Icon(
                        _availableIcons[_selectedIconName],
                        color: SaturdayColors.primaryDark,
                      ),
                      const SizedBox(width: 8),
                      Text(_selectedIconName!),
                    ],
                  ),
                ),
              ),

            if (_selectedIconName != null) const SizedBox(height: 16),

            // Icon grid
            Expanded(
              child: filteredIcons.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.search_off,
                            size: 64,
                            color: SaturdayColors.secondaryGrey,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No icons found for "$_searchQuery"',
                            style: const TextStyle(
                              color: SaturdayColors.secondaryGrey,
                            ),
                          ),
                        ],
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 6,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 1,
                      ),
                      itemCount: filteredIcons.length,
                      itemBuilder: (context, index) {
                        final entry = filteredIcons[index];
                        final iconName = entry.key;
                        final iconData = entry.value;
                        final isSelected = _selectedIconName == iconName;

                        return Tooltip(
                          message: iconName,
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _selectedIconName = iconName;
                              });
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? SaturdayColors.primaryDark
                                    : SaturdayColors.light,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSelected
                                      ? SaturdayColors.primaryDark
                                      : SaturdayColors.secondaryGrey.withValues(alpha: 0.3),
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              child: Icon(
                                iconData,
                                color: isSelected
                                    ? Colors.white
                                    : SaturdayColors.primaryDark,
                                size: 32,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // Action buttons
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _selectedIconName != null
                        ? () => Navigator.pop(context, _selectedIconName)
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SaturdayColors.primaryDark,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Select'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
