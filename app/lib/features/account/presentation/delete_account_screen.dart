import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/supabase/supabase_providers.dart';

/// Briefing §9.10: "Two-step confirmation with a clear list of what is
/// deleted and what is retained." This is the first step (the list +
/// acknowledgement); the second step is the final AlertDialog before the
/// irreversible call actually fires.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  bool _acknowledged = false;
  bool _loading = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Delete account')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(FlcSpace.md),
          children: <Widget>[
            const Text('What happens immediately', style: FlcTextStyles.h3),
            const SizedBox(height: FlcSpace.sm),
            const _Bullet('You are signed out on every device.'),
            const _Bullet('Your name, photo and membership card are removed.'),
            const _Bullet('Any saved payment methods are removed.'),
            const SizedBox(height: FlcSpace.lg),
            const Text('What is kept', style: FlcTextStyles.h3),
            const SizedBox(height: FlcSpace.sm),
            const _Bullet(
              'Past orders and tickets are kept without your name attached — '
              'UK financial and charity record-keeping rules require this, '
              'typically for 6 years.',
            ),
            const _Bullet('Your account is fully and permanently removed after 30 days.'),
            const SizedBox(height: FlcSpace.lg),
            CheckboxListTile(
              value: _acknowledged,
              onChanged: (value) => setState(() => _acknowledged = value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: const Text('I understand this cannot be undone.'),
            ),
            if (_errorMessage != null) ...<Widget>[
              const SizedBox(height: FlcSpace.sm),
              Text(_errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: FlcSpace.md),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
              onPressed: (_acknowledged && !_loading) ? _confirmAndDelete : null,
              child: _loading
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Delete my account'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmAndDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text('This is permanent. Are you sure?'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Delete', style: TextStyle(color: Theme.of(dialogContext).colorScheme.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final client = ref.read(supabaseClientProvider);
      await client.functions.invoke('delete-account');
      await client.auth.signOut();
      if (mounted) {
        context.go('/events');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Your account has been deleted.')),
        );
      }
    } catch (e) {
      setState(() => _errorMessage = 'Something went wrong. Please try again or contact the club.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: FlcSpace.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('•  '),
          Expanded(child: Text(text, style: FlcTextStyles.body)),
        ],
      ),
    );
  }
}
