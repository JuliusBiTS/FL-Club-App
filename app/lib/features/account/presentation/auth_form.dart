import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_repository.dart';
import '../domain/password_strength.dart';
import 'password_strength_meter.dart';

/// The actual sign-in/register form — briefing §9.3 step 2: "Register and
/// sign-in are the same screen with a segmented toggle." Shared between
/// the standalone SignInScreen and checkout's inline Account step (§9.3:
/// account creation happens inline mid-checkout, not as a separate detour)
/// so the two never drift apart.
class AuthForm extends ConsumerStatefulWidget {
  const AuthForm({required this.onAuthenticated, super.key});

  final VoidCallback onAuthenticated;

  @override
  ConsumerState<AuthForm> createState() => _AuthFormState();
}

class _AuthFormState extends ConsumerState<AuthForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isRegisterMode = false;
  bool _obscurePassword = true;
  bool _loading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SegmentedButton<bool>(
            segments: const <ButtonSegment<bool>>[
              ButtonSegment(value: false, label: Text('Sign in')),
              ButtonSegment(value: true, label: Text('Register')),
            ],
            selected: <bool>{_isRegisterMode},
            onSelectionChanged: (selection) => setState(() {
              _isRegisterMode = selection.first;
              _errorMessage = null;
            }),
          ),
          const SizedBox(height: FlcSpace.lg),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const <String>[AutofillHints.email],
            decoration: const InputDecoration(labelText: 'Email'),
            validator: (value) {
              if (value == null || !value.contains('@')) return 'Enter a valid email address';
              return null;
            },
          ),
          const SizedBox(height: FlcSpace.sm),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            autofillHints: <String>[_isRegisterMode ? AutofillHints.newPassword : AutofillHints.password],
            decoration: InputDecoration(
              labelText: 'Password',
              suffixIcon: IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                tooltip: _obscurePassword ? 'Show password' : 'Hide password',
              ),
            ),
            onChanged: (_) => setState(() {}),
            validator: (value) {
              if (value == null || value.isEmpty) return 'Enter your password';
              if (_isRegisterMode && !isPasswordAcceptable(value)) {
                return passwordStrengthLabel(evaluatePasswordStrength(value));
              }
              return null;
            },
          ),
          if (_isRegisterMode) PasswordStrengthMeter(password: _passwordController.text),
          if (!_isRegisterMode)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: _loading ? null : _handleForgotPassword, child: const Text('Forgot password?')),
            ),
          if (_errorMessage != null) ...<Widget>[
            const SizedBox(height: FlcSpace.sm),
            Text(_errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: FlcSpace.md),
          FilledButton(
            onPressed: _loading ? null : _handleSubmit,
            child: _loading
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_isRegisterMode ? 'Create account' : 'Sign in'),
          ),
          const SizedBox(height: FlcSpace.md),
          const Row(children: <Widget>[
            Expanded(child: Divider()),
            Padding(padding: EdgeInsets.symmetric(horizontal: FlcSpace.sm), child: Text('or', style: FlcTextStyles.caption)),
            Expanded(child: Divider()),
          ]),
          const SizedBox(height: FlcSpace.md),
          OutlinedButton.icon(
            onPressed: _loading ? null : _handleGoogleSignIn,
            icon: const Icon(Icons.g_mobiledata),
            label: const Text('Continue with Google'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSubmit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    final auth = ref.read(authRepositoryProvider);
    try {
      if (_isRegisterMode) {
        await auth.signUpWithPassword(email: _emailController.text.trim(), password: _passwordController.text);
      } else {
        await auth.signInWithPassword(email: _emailController.text.trim(), password: _passwordController.text);
      }
      if (mounted) widget.onAuthenticated();
    } on AuthException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleForgotPassword() async {
    final email = _emailController.text.trim();
    if (!email.contains('@')) {
      setState(() => _errorMessage = 'Enter your email above first, then tap "Forgot password?"');
      return;
    }
    try {
      await ref.read(authRepositoryProvider).sendPasswordResetEmail(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("If that email has an account, we've sent a reset link.")),
        );
      }
    } on AuthException catch (e) {
      setState(() => _errorMessage = e.message);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _loading = true);
    try {
      await ref.read(authRepositoryProvider).signInWithGoogle();
    } on AuthException catch (e) {
      setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}
