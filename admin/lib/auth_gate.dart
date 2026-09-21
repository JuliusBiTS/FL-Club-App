import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'shell/admin_shell.dart';

enum AdminRole { none, staff, admin }

/// Minimal email/password sign-in, then a live check of what the signed-in
/// user is allowed to do: admins see the whole console, staff see Events and
/// Notifications, everyone else is turned away. (RLS and the Edge Functions
/// enforce the same limits server-side — failing fast here just beats a
/// console full of silently empty tables.) See is_admin() / is_staff() in
/// supabase/migrations/20260817000008.
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

    return FutureBuilder<AdminRole>(
      future: _role(session.user.id),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        return switch (snapshot.data!) {
          AdminRole.admin => const AdminShell(isAdmin: true),
          AdminRole.staff => const AdminShell(isAdmin: false),
          AdminRole.none => _buildNotAuthorised(),
        };
      },
    );
  }

  Future<AdminRole> _role(String userId) async {
    final client = Supabase.instance.client;
    if (await client.rpc('is_admin', params: {'p_uid': userId}) == true) return AdminRole.admin;
    if (await client.rpc('is_staff', params: {'p_uid': userId}) == true) return AdminRole.staff;
    return AdminRole.none;
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
            const Text("This account doesn't have staff or admin access."),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () async {
                await Supabase.instance.client.auth.signOut();
                if (mounted) setState(() {});
              },
              child: const Text('Sign out'),
            ),
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
