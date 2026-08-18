import 'package:deskconn_mobile_app/widgets/validators.dart';
import 'package:flutter/material.dart';

class PasswordRequirementItem extends StatelessWidget {
  final bool isMet;

  const PasswordRequirementItem({super.key, required this.isMet});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final inactiveColor = scheme.onSurface.withValues(alpha: 0.32);
    final activeColor = scheme.onSurface.withValues(alpha: 1.50);

    final iconColor = isMet ? activeColor : inactiveColor;
    final borderColor = isMet ? activeColor : inactiveColor;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2.5),
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.transparent,
              border: Border.all(color: borderColor),
            ),
            child: Icon(Icons.check, size: 13, color: iconColor),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            Validators.passwordRequirement,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurface),
          ),
        ),
      ],
    );
  }
}
