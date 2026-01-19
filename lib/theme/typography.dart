import 'package:flutter/material.dart';

class DeskconnTypography {
  static TextStyle title(BuildContext context) {
    return Theme.of(context).textTheme.headlineSmall!.copyWith(
      fontWeight: FontWeight.w600,
    );
  }

  static TextStyle body(BuildContext context) {
    return Theme.of(context).textTheme.bodyMedium!;
  }

  static TextStyle error(BuildContext context) {
    return Theme.of(context)
        .textTheme
        .bodySmall!
        .copyWith(color: Theme.of(context).colorScheme.error);
  }
}
