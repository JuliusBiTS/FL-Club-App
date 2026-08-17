import 'dart:async';

import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/profile_provider.dart';
import '../../core/supabase/supabase_providers.dart';

/// "Become a member" — briefing §9.7. The app never sells membership: this
/// writes a membership_applications row via membership-apply (so the club
/// has a real queue, not just a mailbox) and then opens the device's email
/// client with a prefilled draft, because a human at the club still has to
/// review, collect the fee, and activate member_status by hand (§4 hard
/// rule — no code path lets a user grant themselves membership).
///
/// Works for guests too (§9.6 — the handle shows this to everyone, not
/// just signed-in users), so email is collected in-form rather than
/// assumed from a session.
class MembershipInterestScreen extends ConsumerStatefulWidget {
  const MembershipInterestScreen({super.key});

  @override
  ConsumerState<MembershipInterestScreen> createState() => _MembershipInterestScreenState();
}

class _MembershipInterestScreenState extends ConsumerState<MembershipInterestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _occupationController = TextEditingController();
  final _messageController = TextEditingController();

  bool _submitting = false;
  bool _submitted = false;
  String? _error;

  // [CONFIRM] docs/OPEN_QUESTIONS.md flags this destination address as
  // still needing sign-off from the club — kept as a single constant so
  // it's a one-line change once confirmed.
  static const _membershipInboxEmail = 'members@frontlineclub.com';

  @override
  void initState() {
    super.initState();
    final profile = ref.read(currentProfileProvider).valueOrNull;
    final user = ref.read(currentUserProvider);
    _nameController.text = profile?.fullName ?? '';
    _emailController.text = user?.email ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _occupationController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  bool get _isGuest => ref.read(currentUserProvider) == null;

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final client = ref.read(supabaseClientProvider);
      await client.functions.invoke(
        'membership-apply',
        body: {
          'full_name': _nameController.text.trim(),
          if (_isGuest) 'email': _emailController.text.trim(),
          if (_occupationController.text.trim().isNotEmpty) 'occupation': _occupationController.text.trim(),
          if (_messageController.text.trim().isNotEmpty) 'message': _messageController.text.trim(),
        },
      );

      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitted = true;
      });
      unawaited(_openMailClient());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = _errorMessage(e);
      });
    }
  }

  String _errorMessage(Object error) {
    if (error is FunctionException) {
      final details = error.details;
      if (details is Map && details['error'] is String) return details['error'] as String;
    }
    return 'Something went wrong. Please try again.';
  }

  Future<void> _openMailClient() async {
    final name = _nameController.text.trim();
    final subject = Uri.encodeComponent('Membership application — $name');
    final bodyLines = <String>[
      'Name: $name',
      if (_occupationController.text.trim().isNotEmpty) 'Occupation: ${_occupationController.text.trim()}',
      '',
      if (_messageController.text.trim().isNotEmpty) _messageController.text.trim(),
    ];
    final body = Uri.encodeComponent(bodyLines.join('\n'));
    final uri = Uri.parse('mailto:$_membershipInboxEmail?subject=$subject&body=$body');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Become a member')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(FlcSpace.md),
        child: _submitted ? _SubmittedState(onEmailAgain: _openMailClient) : _buildForm(),
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Membership is £365/year and is never sold in-app. Tell us a bit '
            'about yourself and the club will follow up to arrange payment '
            'and activate your card.',
            style: FlcTextStyles.body,
          ),
          const SizedBox(height: FlcSpace.lg),
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Full name'),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: FlcSpace.md),
          if (_isGuest) ...<Widget>[
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                if (!v.contains('@')) return 'Enter a valid email';
                return null;
              },
            ),
            const SizedBox(height: FlcSpace.md),
          ],
          TextFormField(
            controller: _occupationController,
            decoration: const InputDecoration(labelText: 'Occupation (optional)'),
          ),
          const SizedBox(height: FlcSpace.md),
          TextFormField(
            controller: _messageController,
            decoration: const InputDecoration(labelText: 'Anything else? (optional)'),
            maxLines: 4,
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: FlcSpace.md),
            Text(_error!, style: FlcTextStyles.body.copyWith(color: FlcColors.error)),
          ],
          const SizedBox(height: FlcSpace.lg),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Submit application'),
          ),
        ],
      ),
    );
  }
}

class _SubmittedState extends StatelessWidget {
  const _SubmittedState({required this.onEmailAgain});

  final VoidCallback onEmailAgain;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Icon(Icons.check_circle_outline, color: FlcColors.success, size: 40),
        const SizedBox(height: FlcSpace.md),
        const Text('Application sent', style: FlcTextStyles.h3),
        const SizedBox(height: FlcSpace.xs),
        const Text(
          'The club will be in touch to arrange payment and activate your card. '
          "We've also opened an email draft with your details — send it if it "
          "didn't open automatically.",
          style: FlcTextStyles.body,
        ),
        const SizedBox(height: FlcSpace.md),
        OutlinedButton(onPressed: onEmailAgain, child: const Text('Open email draft again')),
      ],
    );
  }
}
