import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';

/// The card's own wordmark — centred, flat, no boxed tag — replacing the
/// demo-only JPG pulled from the live site (see docs/OPEN_QUESTIONS.md:
/// still waiting on a real vector logo from the club). "London" plays the
/// same role Waterstones' italic "plus" does: a quiet flourish naming the
/// tier/place, not a competing logo mark.
class MembershipCardWordmark extends StatelessWidget {
  const MembershipCardWordmark({this.compact = false, super.key});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: FlcSpace.xxs + 2,
      children: <Widget>[
        Text(
          'FRONTLINE CLUB',
          style: FlcTextStyles.bodySmall.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
            fontSize: compact ? 12 : 14,
          ),
        ),
        Text(
          'London',
          style: TextStyle(
            fontFamily: FlcFontFamily.serif,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w500,
            color: const Color(0xFFB7CC6C),
            fontSize: compact ? 12 : 14,
            height: 1,
          ),
        ),
      ],
    );
  }
}
