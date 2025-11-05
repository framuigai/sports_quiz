import 'package:flutter/material.dart';

class EmptyState extends StatelessWidget {
  final String message;
  final String actionText;
  final VoidCallback onAction;

  const EmptyState({
    super.key,
    required this.message,
    required this.actionText,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(message, style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: onAction,
          icon: const Icon(Icons.refresh),
          label: Text(actionText),
        ),
      ]),
    );
  }
}
