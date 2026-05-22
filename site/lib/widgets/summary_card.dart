import 'package:flutter/material.dart';

class SummaryCard extends StatefulWidget {
  final String summary;

  const SummaryCard({super.key, required this.summary});

  @override
  State<SummaryCard> createState() => _SummaryCardState();
}

class _SummaryCardState extends State<SummaryCard> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    if (widget.summary.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: const Color(0xFFD97706).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome,
                      size: 16, color: Color(0xFFD97706)),
                  const SizedBox(width: 8),
                  Text(
                    'TL;DR',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: const Color(0xFFD97706),
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const Spacer(),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: const Color(0xFFD97706),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                widget.summary,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF78716C),
                      height: 1.6,
                    ),
              ),
            ),
        ],
      ),
    );
  }
}
