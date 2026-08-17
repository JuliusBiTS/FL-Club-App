import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'auth_form.dart';

/// Standalone sign-in — reachable from the You tab. See auth_form.dart for
/// the actual form; checkout's inline Account step (M3) uses the same
/// widget so the two never drift apart.
class SignInScreen extends StatelessWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(FlcSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(FlcRadius.card),
                child: Image.asset('assets/images/brand/frontline_logo.jpg', height: 120, fit: BoxFit.cover),
              ),
              const SizedBox(height: FlcSpace.lg),
              AuthForm(onAuthenticated: () => context.pop()),
            ],
          ),
        ),
      ),
    );
  }
}
