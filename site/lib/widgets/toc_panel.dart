import 'package:flutter/material.dart';
import 'package:synapse_runbooks/models/doc.dart';

class TocPanel extends StatelessWidget {
  final List<TocEntry> toc;
  final ValueChanged<String> onTap;

  const TocPanel({super.key, required this.toc, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (toc.isEmpty) return const SizedBox.shrink();

    return Container(
      width: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('목차',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  )),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              itemCount: toc.length,
              itemBuilder: (context, index) {
                final entry = toc[index];
                return InkWell(
                  onTap: () => onTap(entry.anchor),
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: (entry.level - 2) * 12.0,
                      top: 4,
                      bottom: 4,
                    ),
                    child: Text(
                      entry.text,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
