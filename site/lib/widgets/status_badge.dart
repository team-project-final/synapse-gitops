import 'package:flutter/material.dart';

const Map<String, Color> kStatusColors = {
  'healthy': Color(0xFF16A34A),
  'pending': Color(0xFF2563EB),
  'degraded': Color(0xFFD97706),
  'down': Color(0xFFDC2626),
  'planned': Color(0xFF9CA3AF),
  'na': Color(0xFFD1D5DB),
};

const Map<String, String> kStatusText = {
  'healthy': 'Healthy',
  'pending': '검증 대기',
  'degraded': 'Degraded',
  'down': 'Down',
  'planned': 'Planned',
  'na': '—',
};

class StatusBadge extends StatelessWidget {
  final String status;
  final String label;

  const StatusBadge({super.key, required this.status, required this.label});

  @override
  Widget build(BuildContext context) {
    if (status == 'na') {
      return const Text('—', style: TextStyle(color: Color(0xFF9CA3AF)));
    }
    final color = kStatusColors[status] ?? const Color(0xFF9CA3AF);
    final text = label.isEmpty ? (kStatusText[status] ?? status) : label;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
