// mobile/lib/widgets/option_tile.dart
//
// A reusable option tile used in the Player:
// - Neutral state before answering
// - When showFeedback=true:
//     * Selected & correct  → check icon
//     * Selected & wrong    → close icon
//     * Non-selected correct (optional) could be styled differently later
//
// Keep colors minimal; rely on Material defaults so it fits your theme.

import 'package:flutter/material.dart';

class OptionTile extends StatelessWidget {
  final String text;
  final bool isSelected;
  final bool isCorrect; // whether THIS option is the correct one
  final bool showFeedback;
  final VoidCallback? onTap;

  const OptionTile({
    super.key,
    required this.text,
    required this.isSelected,
    required this.isCorrect,
    required this.showFeedback,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = _borderColor(context);
    final icon = _trailingIcon();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        title: Text(text),
        trailing: icon,
        onTap: onTap,
      ),
    );
  }

  // Visual rule:
  // - If showFeedback:
  //    * Selected & correct → green check
  //    * Selected & wrong   → red close
  // - Otherwise neutral radio style when selected/not selected
  Widget? _trailingIcon() {
    if (!showFeedback) {
      return Icon(isSelected
          ? Icons.radio_button_checked
          : Icons.radio_button_unchecked);
    }
    if (isSelected && isCorrect) {
      return const Icon(Icons.check_circle, color: Colors.green);
    }
    if (isSelected && !isCorrect) {
      return const Icon(Icons.cancel, color: Colors.red);
    }
    return null; // keep others neutral
  }

  Color _borderColor(BuildContext context) {
    if (!showFeedback) return Colors.black12;
    if (isSelected && isCorrect) return Colors.green;
    if (isSelected && !isCorrect) return Colors.red;
    // Neutral for non-selected
    return Colors.black12;
  }
}
