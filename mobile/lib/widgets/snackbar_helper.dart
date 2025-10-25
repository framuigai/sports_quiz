// lib/widgets/snackbar_helper.dart
import 'package:flutter/material.dart';

class SnackbarHelper {
  static void showInfo(BuildContext context, String message) {
    _show(context, message, Colors.indigo);
  }

  static void showSuccess(BuildContext context, String message) {
    _show(context, message, Colors.green);
  }

  static void showError(BuildContext context, String message) {
    _show(context, message, Colors.red);
  }

  static void _show(BuildContext context, String message, Color color) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color.withOpacity(0.9),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
