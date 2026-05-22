import 'package:flutter/material.dart';

class TagChip extends StatelessWidget {
  final String tag;
  final bool selected;
  final VoidCallback? onTap;

  const TagChip(
      {super.key, required this.tag, this.selected = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Chip(
        label: Text(tag),
        backgroundColor: selected ? const Color(0xFFFEF3C7) : null,
        side: selected
            ? const BorderSide(color: Color(0xFFD97706))
            : BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant),
        labelStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: selected ? const Color(0xFFD97706) : null,
            ),
      ),
    );
  }
}
