import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_repository.dart';
import '../../core/auth/profile_provider.dart';
import '../../core/supabase/supabase_providers.dart';

/// The "You" tab — briefing §9.10. Signed out: a sign-in prompt, never a
/// wall. Signed in: header, tickets/loyalty/membership, and the settings/
/// legal/delete-account list. Most rows are stubs pointing at their real
/// milestone (M3 payment methods, M9 notifications/help) — sign-in,
/// sign-out and delete-account are real now.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('You')),
      body: user == null ? const _SignedOutBody() : const _SignedInBody(),
    );
  }
}

class _SignedOutBody extends StatelessWidget {
  const _SignedOutBody();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FlcSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.person_outline, size: 40, color: FlcColors.slate),
            const SizedBox(height: FlcSpace.md),
            const Text(
              'Sign in to buy tickets, track your loyalty progress, and access your membership card.',
              textAlign: TextAlign.center,
              style: FlcTextStyles.body,
            ),
            const SizedBox(height: FlcSpace.md),
            FilledButton(onPressed: () => context.push('/sign-in'), child: const Text('Sign in')),
            const SizedBox(height: FlcSpace.sm),
            TextButton(
              onPressed: () => context.push('/you/become-a-member'),
              child: const Text('Become a member'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignedInBody extends ConsumerWidget {
  const _SignedInBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentProfileProvider);
    final user = ref.watch(currentUserProvider)!;

    return ListView(
      children: <Widget>[
        profileAsync.when(
          loading: () => const Padding(padding: EdgeInsets.all(FlcSpace.lg), child: LinearProgressIndicator()),
          error: (error, stackTrace) => Padding(
            padding: const EdgeInsets.all(FlcSpace.md),
            child: Text("Couldn't load your profile.", style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
          data: (profile) => _ProfileHeader(name: profile?.displayName ?? profile?.fullName, email: user.email ?? '', isMember: profile?.isActiveMember ?? false),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.confirmation_number_outlined),
          title: const Text('My tickets'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/you/tickets'),
        ),
        ListTile(
          leading: const Icon(Icons.loyalty_outlined),
          title: const Text('Loyalty'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/you/loyalty'),
        ),
        ListTile(
          leading: const Icon(Icons.credit_card_outlined),
          title: const Text('Payment methods'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Coming in M3.'))),
        ),
        ListTile(
          leading: const Icon(Icons.notifications_outlined),
          title: const Text('Notifications'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Coming in M9.'))),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.help_outline),
          title: const Text('Help'),
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Coming later.'))),
        ),
        ListTile(
          leading: const Icon(Icons.description_outlined),
          title: const Text('Legal'),
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Coming later.'))),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Sign out'),
          onTap: () => ref.read(authRepositoryProvider).signOut(),
        ),
        ListTile(
          leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
          title: Text('Delete account', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          onTap: () => context.push('/you/delete-account'),
        ),
      ],
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.name, required this.email, required this.isMember});

  final String? name;
  final String email;
  final bool isMember;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(FlcSpace.md),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 28,
            backgroundColor: FlcColors.ink,
            child: Text(
              (name?.isNotEmpty == true ? name![0] : email[0]).toUpperCase(),
              style: const TextStyle(color: Colors.white, fontSize: 20),
            ),
          ),
          const SizedBox(width: FlcSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(name?.isNotEmpty == true ? name! : email, style: FlcTextStyles.h3),
                Text(email, style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.slate)),
                const SizedBox(height: FlcSpace.xxs),
                _MembershipChip(isMember: isMember),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MembershipChip extends StatelessWidget {
  const _MembershipChip({required this.isMember});

  final bool isMember;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: FlcSpace.xs, vertical: 2),
      decoration: BoxDecoration(
        color: (isMember ? FlcColors.success : FlcColors.slate).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(FlcRadius.input),
      ),
      child: Text(
        isMember ? 'Member' : 'Not a member',
        style: FlcTextStyles.caption.copyWith(color: isMember ? FlcColors.success : FlcColors.slate, fontWeight: FontWeight.w600),
      ),
    );
  }
}
