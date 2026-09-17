import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

bool isDesktopLayout(BuildContext context) {
  if (MediaQuery.sizeOf(context).width >= 900) return true;
  return switch (defaultTargetPlatform) {
    TargetPlatform.linux || TargetPlatform.macOS || TargetPlatform.windows => true,
    _ => false,
  };
}
