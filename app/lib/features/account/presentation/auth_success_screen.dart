import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';

/// Shown once, right after a successful sign-in or registration, instead of
/// silently popping straight back to whatever screen asked for it —
/// feedback: a login shouldn't just "send you back to the last screen" with
/// no acknowledgement that it worked. "Continue" pops this screen only;
/// SignInScreen pushed it as a replacement, so that lands the person
/// exactly where they were before they tapped "Sign in".
class AuthSuccessScreen extends StatelessWidget {
  const AuthSuccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(FlcSpace.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.check_circle, color: FlcColors.success, size: 56),
                const SizedBox(height: FlcSpace.md),
                const Text("You're signed in", style: FlcTextStyles.h2, textAlign: TextAlign.center),
                const SizedBox(height: FlcSpace.xs),
                const Text(
                  'Your tickets, loyalty points and membership card are ready.',
                  style: FlcTextStyles.body,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: FlcSpace.lg),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Continue'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
