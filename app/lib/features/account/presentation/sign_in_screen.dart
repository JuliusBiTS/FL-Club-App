import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'auth_form.dart';

/// Standalone sign-in — reachable from the You tab. See auth_form.dart for
/// the actual form; checkout's inline Account step (M3) uses the same
/// widget so the two never drift apart.
///
/// The success state is shown IN PLACE (swapping this screen's own body),
/// not by navigating to a new route — a bug fix: this route sits in
/// go_router's own declarative Navigator, and go_router rebuilds/
/// reconciles that Navigator's page stack the moment auth state changes
/// (via _ProfileRefreshListenable in app_router.dart, which fires right
/// after a sign-in), which was silently discarding an imperatively
/// Navigator.push-ed screen underneath it. Same reasoning as
/// MembershipInterestScreen's own _SubmittedState.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool _signedIn = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(FlcSpace.md),
          child: _signedIn ? const _SignedInBody() : _buildForm(),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(FlcRadius.card),
          child: Image.asset('assets/images/brand/frontline_logo.jpg', height: 120, fit: BoxFit.cover),
        ),
        const SizedBox(height: FlcSpace.lg),
        AuthForm(onAuthenticated: () => setState(() => _signedIn = true)),
      ],
    );
  }
}

class _SignedInBody extends StatelessWidget {
  const _SignedInBody();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const SizedBox(height: FlcSpace.xl),
        Icon(Icons.check_circle, color: FlcColors.successAccent(context), size: 56),
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
          onPressed: () => context.pop(),
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
