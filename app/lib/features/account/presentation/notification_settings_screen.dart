import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/profile_provider.dart';
import '../../../core/push/push_service.dart';
import '../../../core/supabase/supabase_providers.dart';

class _NotificationPrefs {
  const _NotificationPrefs({this.newEvents = true, this.recommendations = true, this.loyalty = true});

  final bool newEvents;
  final bool recommendations;
  final bool loyalty;

  _NotificationPrefs copyWith({bool? newEvents, bool? recommendations, bool? loyalty}) => _NotificationPrefs(
        newEvents: newEvents ?? this.newEvents,
        recommendations: recommendations ?? this.recommendations,
        loyalty: loyalty ?? this.loyalty,
      );
}

/// A person with no saved row hasn't chosen anything: every topic is on.
final AutoDisposeFutureProvider<_NotificationPrefs> _prefsProvider = FutureProvider.autoDispose<_NotificationPrefs>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const _NotificationPrefs();
  final row = await ref.watch(supabaseClientProvider).from('notification_preferences').select().eq('user_id', user.id).maybeSingle();
  if (row == null) return const _NotificationPrefs();
  return _NotificationPrefs(
    newEvents: row['new_events'] as bool? ?? true,
    recommendations: row['recommendations'] as bool? ?? true,
    loyalty: row['loyalty'] as bool? ?? true,
  );
});

/// You → Notifications. One master switch (which asks the phone for
/// permission at this moment, not at launch), then per-topic choices.
/// Anything about a ticket you hold — cancelled, moved — is always sent while
/// the master switch is on, because missing it would cost you an evening.
class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends ConsumerState<NotificationSettingsScreen> {
  bool _busy = false;

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _setMaster(bool on) async {
    final push = ref.read(pushServiceProvider);
    setState(() => _busy = true);
    try {
      if (on) {
        switch (await push.enable()) {
          case PushEnableResult.enabled:
            _say('Notifications are on.');
          case PushEnableResult.denied:
            _say('Notifications are blocked for this app. Turn them on in your phone\'s settings, then try again.');
          case PushEnableResult.signedOut:
            _say('Sign in first.');
          case PushEnableResult.unavailable:
            _say('Notifications aren\'t available in this version of the app yet.');
          case PushEnableResult.failed:
            _say('Couldn\'t turn notifications on. Check your connection and try again.');
        }
      } else {
        await push.disable();
        _say('Notifications are off.');
      }
      ref.invalidate(currentProfileProvider);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _savePrefs(_NotificationPrefs prefs) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    try {
      await ref.read(supabaseClientProvider).from('notification_preferences').upsert(<String, dynamic>{
        'user_id': user.id,
        'new_events': prefs.newEvents,
        'recommendations': prefs.recommendations,
        'loyalty': prefs.loyalty,
      });
      ref.invalidate(_prefsProvider);
    } catch (_) {
      _say('Couldn\'t save that. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final push = ref.watch(pushServiceProvider);
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final prefs = ref.watch(_prefsProvider).valueOrNull ?? const _NotificationPrefs();
    final on = profile?.pushOptIn ?? false;

    Widget body;
    if (user == null) {
      body = _Centered(
        icon: Icons.notifications_none,
        text: 'Sign in to choose which notifications you get.',
        action: FilledButton(onPressed: () => context.push('/sign-in'), child: const Text('Sign in')),
      );
    } else if (!push.isAvailable) {
      body = const _Centered(
        icon: Icons.notifications_off_outlined,
        text: 'Notifications aren\'t switched on in this version of the app yet. Nothing is lost — we\'ll switch them on soon.',
      );
    } else {
      body = ListView(
        children: <Widget>[
          SwitchListTile(
            title: const Text('Notifications'),
            subtitle: const Text('New events, recommendations, and news about events you\'ve booked.'),
            value: on,
            onChanged: _busy ? null : _setMaster,
          ),
          const Divider(height: 1),
          _TopicTile(
            title: 'New events',
            subtitle: 'When the club announces something new.',
            value: prefs.newEvents,
            enabled: on,
            onChanged: (v) => _savePrefs(prefs.copyWith(newEvents: v)),
          ),
          _TopicTile(
            title: 'Recommendations & offers',
            subtitle: 'FC Recommends, special offers and club news.',
            value: prefs.recommendations,
            enabled: on,
            onChanged: (v) => _savePrefs(prefs.copyWith(recommendations: v)),
          ),
          _TopicTile(
            title: 'Loyalty rewards',
            subtitle: 'When you\'ve earned a free ticket.',
            value: prefs.loyalty,
            enabled: on,
            onChanged: (v) => _savePrefs(prefs.copyWith(loyalty: v)),
          ),
          const Padding(
            padding: EdgeInsets.all(FlcSpace.md),
            child: Text(
              'If an event you hold a ticket for is cancelled or changes, we\'ll always tell you while notifications are on.',
              style: FlcTextStyles.bodySmall,
            ),
          ),
        ],
      );
    }

    return Scaffold(appBar: AppBar(title: const Text('Notifications')), body: body);
  }
}

class _TopicTile extends StatelessWidget {
  const _TopicTile({required this.title, required this.subtitle, required this.value, required this.enabled, required this.onChanged});

  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(title: Text(title), subtitle: Text(subtitle), value: value, onChanged: enabled ? onChanged : null);
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FlcSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 40, color: FlcColors.slate),
            const SizedBox(height: FlcSpace.sm),
            Text(text, textAlign: TextAlign.center, style: FlcTextStyles.body),
            if (action != null) ...<Widget>[const SizedBox(height: FlcSpace.md), action!],
          ],
        ),
      ),
    );
  }
}
