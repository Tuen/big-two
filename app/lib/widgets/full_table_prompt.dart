import "package:flutter/material.dart";

/// Shown when a code belongs to a table that already has four players.
class FullTablePrompt extends StatelessWidget {
  final String message;
  const FullTablePrompt({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text("Watch this game")),
      ],
    );
  }
}
