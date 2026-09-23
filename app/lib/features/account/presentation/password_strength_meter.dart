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
    // The bar's own fill sits against its fixed light track (FlcColors.line
    // below), not the page background, so it doesn't need a dark-mode
    // variant — only the label text underneath, which does.
    final (double fraction, Color color, Color textColor) = switch (strength) {
      PasswordStrength.tooShort => (0.15, FlcColors.error, FlcColors.errorAccent(context)),
      PasswordStrength.common => (0.15, FlcColors.error, FlcColors.errorAccent(context)),
      PasswordStrength.weak => (0.35, FlcColors.warning, FlcColors.warning),
      PasswordStrength.fair => (0.55, FlcColors.warning, FlcColors.warning),
      PasswordStrength.good => (0.8, FlcColors.success, FlcColors.successAccent(context)),
      PasswordStrength.strong => (1.0, FlcColors.success, FlcColors.successAccent(context)),
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
          Text(passwordStrengthLabel(strength), style: FlcTextStyles.caption.copyWith(color: textColor)),
        ],
      ),
    );
  }
}
