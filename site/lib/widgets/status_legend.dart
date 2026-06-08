import 'package:flutter/material.dart';
import 'package:synapse_runbooks/widgets/status_badge.dart';

class StatusLegend extends StatelessWidget {
  const StatusLegend({super.key});

  @override
  Widget build(BuildContext context) {
    const order = ['healthy', 'pending', 'degraded', 'down', 'planned'];
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        for (final s in order)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: kStatusColors[s],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 4),
              Text(kStatusText[s] ?? s,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
            ],
          ),
      ],
    );
  }
}
