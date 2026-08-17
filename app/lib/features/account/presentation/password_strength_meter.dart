import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';

import '../domain/password_strength.dart';

class PasswordStrengthMeter extends StatelessWidget {
  const PasswordStrengthMeter({required this.password, super.key});

  final String password;

  @override
  Widget build(BuildContext context) {
    if (password.isEmpty) return const SizedBox.shrink();

    final strength = evaluatePasswordStrength(password);
    final (double fraction, Color color) = switch (strength) {
      PasswordStrength.tooShort => (0.15, FlcColors.error),
      PasswordStrength.common => (0.15, FlcColors.error),
      PasswordStrength.weak => (0.35, FlcColors.warning),
      PasswordStrength.fair => (0.55, FlcColors.warning),
      PasswordStrength.good => (0.8, FlcColors.success),
      PasswordStrength.strong => (1.0, FlcColors.success),
    };

    return Padding(
      padding: const EdgeInsets.only(top: FlcSpace.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 4,
              backgroundColor: FlcColors.line,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 4),
          Text(passwordStrengthLabel(strength), style: FlcTextStyles.caption.copyWith(color: color)),
        ],
      ),
    );
  }
}
