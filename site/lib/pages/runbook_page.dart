import 'package:flutter/material.dart';

class RunbookPage extends StatelessWidget {
  final String slug;
  const RunbookPage({super.key, required this.slug});

  @override
  Widget build(BuildContext context) {
    return Center(child: Text('Runbook: $slug'));
  }
}
