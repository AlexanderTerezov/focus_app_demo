import 'package:flutter/material.dart';

class SettingRow extends StatelessWidget {
  final String title;
  final int value;
  final int min;
  final int max;
  final List<int> presets;
  final String unit;
  final ValueChanged<int> onValueChanged;

  const SettingRow({
    super.key,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.presets,
    required this.unit,
    required this.onValueChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final textColor = isDark ? Colors.white : const Color(0xFF263746);

    final secondaryColor = isDark ? Colors.white70 : const Color(0xAA34495E);

    final inactiveChipColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.05);

    final activeChipColor = isDark ? Colors.white : const Color(0xFF34495E);

    final activeChipTextColor = isDark ? Colors.black : Colors.white;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(color: secondaryColor, fontSize: 16),
              ),
              Text(
                '$value $unit',
                style: TextStyle(
                  color: textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: value.toDouble().clamp(min.toDouble(), max.toDouble()),
              min: min.toDouble(),
              max: max.toDouble(),
              divisions: max - min,
              onChanged: (newValue) {
                onValueChanged(newValue.round());
              },
            ),
          ),

          const SizedBox(height: 4),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: presets.map((preset) {
              final isSelected = value == preset;

              return GestureDetector(
                onTap: () => onValueChanged(preset),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected ? activeChipColor : inactiveChipColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '$preset',
                    style: TextStyle(
                      color: isSelected ? activeChipTextColor : secondaryColor,
                      fontSize: 13,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
