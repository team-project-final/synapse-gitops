import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:synapse_runbooks/widgets/code_block.dart';

class MarkdownViewer extends StatelessWidget {
  final String data;

  const MarkdownViewer({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Markdown(
      data: data,
      selectable: true,
      padding: const EdgeInsets.all(24),
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        h1: Theme.of(context).textTheme.headlineLarge,
        h2: Theme.of(context).textTheme.headlineMedium?.copyWith(
              decoration: TextDecoration.underline,
              decorationColor: Theme.of(context).colorScheme.outlineVariant,
            ),
        h3: Theme.of(context).textTheme.titleLarge,
        blockquotePadding: const EdgeInsets.all(12),
        blockquoteDecoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          border: Border(
            left: BorderSide(
              color: Theme.of(context).colorScheme.primary,
              width: 4,
            ),
          ),
        ),
        tableBorder: TableBorder.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        tableHead: const TextStyle(fontWeight: FontWeight.bold),
        tableCellsPadding: const EdgeInsets.all(8),
      ),
      builders: {
        'code': _CodeBlockBuilder(),
      },
    );
  }
}

class _CodeBlockBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(element, preferredStyle) {
    if (element.textContent.isEmpty) return null;

    final language = element.attributes['class']?.replaceFirst('language-', '');

    if (element.textContent.contains('\n') || language != null) {
      return CodeBlockWidget(
        code: element.textContent.trimRight(),
        language: language,
      );
    }

    return null;
  }
}
