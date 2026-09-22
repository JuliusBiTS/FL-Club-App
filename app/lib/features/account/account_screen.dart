import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_repository.dart';
import '../../core/auth/profile_provider.dart';
import '../../core/preferences/membership_card_preferences.dart';
import '../../core/push/push_service.dart';
import '../../core/supabase/supabase_providers.dart';
import '../membership/presentation/membership_card_sheet.dart';

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
        const Padding(
          padding: EdgeInsets.fromLTRB(FlcSpace.md, 0, FlcSpace.md, FlcSpace.sm),
          child: _MembershipCardTile(),
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
          onTap: () => context.push('/you/notifications'),
        ),
        if (profileAsync.valueOrNull?.isStaff ?? false) ...<Widget>[
          const Divider(height: 1),
          const Padding(
            padding: EdgeInsets.fromLTRB(FlcSpace.md, FlcSpace.md, FlcSpace.md, FlcSpace.xxs),
            child: Text('STAFF', style: FlcTextStyles.overline),
          ),
          ListTile(
            leading: const Icon(Icons.edit_calendar_outlined),
            title: const Text('Manage events'),
            subtitle: const Text('Create, edit, publish and promote events'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/manage/events'),
          ),
          ListTile(
            leading: const Icon(Icons.campaign_outlined),
            title: const Text('Send a notification'),
            subtitle: const Text('Announcements, and what has gone out'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/manage/notifications'),
          ),
        ],
        const Divider(height: 1),
        SwitchListTile(
          secondary: const Icon(Icons.circle_outlined),
          title: const Text('Minimise the membership button'),
          subtitle: const Text('Show it as a small dot instead of the full bar'),
          value: ref.watch(alwaysShowDotProvider),
          onChanged: (value) => setAlwaysShowDot(ref, value),
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
          onTap: () async {
            // Detach this phone from the account first, so the next person to use it
            // doesn't receive this person's notifications.
            await ref.read(pushServiceProvider).forgetThisDevice();
            await ref.read(authRepositoryProvider).signOut();
          },
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

/// A hardcoded, always-there entry point to the membership card — briefing
/// feedback: "include a hard coded membership slide / card in the user
/// menu that is always there and can be clicked on." Unlike the drag
/// handle (which can be minimised to a dot, or hidden while a pushed
/// screen claims the strip), this tile never moves and never disappears —
/// it's the one guaranteed way in, from a tab that's never mid-animation.
class _MembershipCardTile extends StatelessWidget {
  const _MembershipCardTile();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: FlcColors.brand,
      borderRadius: BorderRadius.circular(FlcRadius.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(FlcRadius.card),
        onTap: () => MembershipCardSheet.showModal(context),
        child: Container(
          padding: const EdgeInsets.all(FlcSpace.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(FlcRadius.card),
            border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1.2),
          ),
          child: Row(
            children: <Widget>[
              const Icon(Icons.qr_code_2, color: Colors.white, size: 28),
              const SizedBox(width: FlcSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Membership card',
                      style: FlcTextStyles.body.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      'Tap to show your QR, barcode and loyalty stamps',
                      style: FlcTextStyles.caption.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white70),
            ],
          ),
        ),
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
