import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'shell/admin_shell.dart';

/// Minimal email/password sign-in, then a live check that the signed-in
/// user is actually an admin (RLS enforces this everywhere else too, but
/// failing fast here with a clear message beats a console full of silently
/// empty tables). See supabase/migrations/20260817000008 is_admin().
class AdminAuthGate extends StatefulWidget {
  const AdminAuthGate({super.key});

  @override
  State<AdminAuthGate> createState() => _AdminAuthGateState();
}

class _AdminAuthGateState extends State<AdminAuthGate> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _error;
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return _buildSignIn();

    return FutureBuilder<bool>(
      future: _isAdmin(session.user.id),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        if (snapshot.data == true) return const AdminShell();
        return _buildNotAuthorised();
      },
    );
  }

  Future<bool> _isAdmin(String userId) async {
    final result = await Supabase.instance.client.rpc('is_admin', params: {'p_uid': userId});
    return result == true;
  }

  Widget _buildSignIn() {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text('Frontline Club — Admin', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 24),
                TextField(controller: _emailController, decoration: const InputDecoration(labelText: 'Email')),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                  onSubmitted: (_) => _signIn(),
                ),
                if (_error != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _loading ? null : _signIn,
                  child: _loading ? const CircularProgressIndicator() : const Text('Sign in'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNotAuthorised() {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text("This account doesn't have admin access."),
            const SizedBox(height: 12),
            TextButton(onPressed: () => Supabase.instance.client.auth.signOut(), child: const Text('Sign out')),
          ],
        ),
      ),
    );
  }

  Future<void> _signIn() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      setState(() {});
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      setState(() => _loading = false);
    }
  }
}
