import 'package:flutter/material.dart';

class ProgressBar extends StatelessWidget {
  final int percentage;
  final String? label;

  const ProgressBar({super.key, required this.percentage, this.label});

  Color get _color {
    if (percentage >= 70) return const Color(0xFF0D9488);
    if (percentage >= 30) return const Color(0xFFD97706);
    return const Color(0xFFDC2626);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(label!,
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                Text('$percentage%',
                    style:
                        Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: _color,
                            )),
              ],
            ),
          ),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: percentage / 100,
            backgroundColor: const Color(0xFFE7E5E4),
            color: _color,
            minHeight: 8,
          ),
        ),
      ],
    );
  }
}
