import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/profile_provider.dart';
import '../../../core/push/push_service.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../calendar_actions.dart';
import '../data/event_follow_repository.dart';

void _snack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// Saving needs an account (it follows you between phones); signed-out people
/// are taken to sign in rather than shown an error.
Future<void> toggleSaved(BuildContext context, WidgetRef ref, String eventId) async {
  if (ref.read(currentUserProvider) == null) {
    await context.push('/sign-in');
    return;
  }
  final bool nowSaved = !ref.read(eventFollowsProvider).valueOrNull!.isSaved(eventId);
  final bool ok = await ref.read(eventFollowsProvider.notifier).setSaved(eventId, nowSaved);
  if (!context.mounted) return;
  _snack(context, ok ? (nowSaved ? 'Saved to your events.' : 'Removed from saved.') : "Couldn't save that. Please try again.");
}

Future<void> toggleReminder(BuildContext context, WidgetRef ref, String eventId) async {
  if (ref.read(currentUserProvider) == null) {
    await context.push('/sign-in');
    return;
  }
  final EventFollows follows = ref.read(eventFollowsProvider).valueOrNull ?? const EventFollows();
  final bool turnOn = !follows.isNotify(eventId);

  String? extra;
  if (turnOn) {
    final bool pushOn = ref.read(currentProfileProvider).valueOrNull?.pushOptIn ?? false;
    if (!pushOn) {
      final PushEnableResult r = await ref.read(pushServiceProvider).enable();
      ref.invalidate(currentProfileProvider);
      if (r != PushEnableResult.enabled) {
        extra = 'Notifications are off on this phone, so turn them on under You → Notifications to get the reminder.';
      }
    }
  }
  final bool ok = await ref.read(eventFollowsProvider.notifier).setNotify(eventId, turnOn);
  if (!context.mounted) return;
  if (!ok) {
    _snack(context, "Couldn't update that. Please try again.");
  } else if (turnOn) {
    _snack(context, extra ?? "We'll remind you the day before and an hour before.");
  } else {
    _snack(context, 'Reminder turned off.');
  }
}

/// A heart for saving an event — used on the event page and the feed cards.
class SaveEventButton extends ConsumerWidget {
  const SaveEventButton({required this.eventId, this.onDark = false, this.compact = false, super.key});

  final String eventId;

  /// True on the green app bar, where the icon must be white.
  final bool onDark;

  /// Smaller hit area, for sitting inside a card.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool saved = ref.watch(eventFollowsProvider).valueOrNull?.isSaved(eventId) ?? false;
    return IconButton(
      visualDensity: compact ? VisualDensity.compact : null,
      padding: compact ? EdgeInsets.zero : const EdgeInsets.all(8),
      constraints: compact ? const BoxConstraints(minWidth: 36, minHeight: 36) : null,
      tooltip: saved ? 'Remove from saved' : 'Save this event',
      icon: Icon(
        saved ? Icons.favorite : Icons.favorite_border,
        color: onDark ? Colors.white : (saved ? FlcColors.accent(context) : FlcColors.secondary(context)),
      ),
      onPressed: () => toggleSaved(context, ref, eventId),
    );
  }
}

/// "Add to calendar" and "Remind me" side by side, under the event facts.
class EventActionsRow extends ConsumerWidget {
  const EventActionsRow({required this.event, super.key});

  final EventModel event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool remind = ref.watch(eventFollowsProvider).valueOrNull?.isNotify(event.id) ?? false;
    final Color accent = FlcColors.accent(context);
    final bool upcoming = event.startsAt.isAfter(DateTime.now());

    return Wrap(
      spacing: FlcSpace.xs,
      runSpacing: FlcSpace.xs,
      children: <Widget>[
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44), foregroundColor: accent),
          onPressed: () => addToCalendar(context, icsFromEvent(event)),
          icon: const Icon(Icons.event_available_outlined, size: 18),
          label: const Text('Add to calendar'),
        ),
        if (upcoming)
          remind
              ? FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: () => toggleReminder(context, ref, event.id),
                  icon: const Icon(Icons.notifications_active, size: 18),
                  label: const Text('Reminder on'),
                )
              : OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44), foregroundColor: accent),
                  onPressed: () => toggleReminder(context, ref, event.id),
                  icon: const Icon(Icons.notifications_none, size: 18),
                  label: const Text('Remind me'),
                ),
      ],
    );
  }
}

/// Shown instead of ticket options when an event is sold out: join the waiting
/// list and (if signed in with notifications on) get a push if a place opens.
class WaitlistCard extends ConsumerStatefulWidget {
  const WaitlistCard({required this.eventId, super.key});

  final String eventId;

  @override
  ConsumerState<WaitlistCard> createState() => _WaitlistCardState();
}

class _WaitlistCardState extends ConsumerState<WaitlistCard> {
  final TextEditingController _email = TextEditingController();
  bool _busy = false;
  bool _guestDone = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _joinSignedIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(eventFollowRepositoryProvider).registerInterest(widget.eventId);
      ref.invalidate(eventInterestProvider(widget.eventId));
      final bool pushOn = ref.read(currentProfileProvider).valueOrNull?.pushOptIn ?? false;
      if (!pushOn) {
        final PushEnableResult r = await ref.read(pushServiceProvider).enable();
        ref.invalidate(currentProfileProvider);
        if (mounted && r != PushEnableResult.enabled) {
          _snack(context, "You're on the list. Turn on notifications under You → Notifications to be told if a place opens.");
        }
      }
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't add you. Please try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    setState(() => _busy = true);
    try {
      await ref.read(eventFollowRepositoryProvider).removeInterest(widget.eventId);
      ref.invalidate(eventInterestProvider(widget.eventId));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _joinGuest() async {
    final String email = _email.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(eventFollowRepositoryProvider).registerGuestInterest(widget.eventId, email: email);
      if (mounted) setState(() => _guestDone = true);
    } catch (e) {
      if (mounted) setState(() => _error = "Couldn't add you just now. Please try again in a little while.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool signedIn = ref.watch(currentUserProvider) != null;
    final bool onList = signedIn && (ref.watch(eventInterestProvider(widget.eventId)).valueOrNull ?? false);
    final Color muted = FlcColors.secondary(context);

    Widget body;
    if (_guestDone) {
      body = const Text("You're on the list. The club will be in touch if a place opens.", style: FlcTextStyles.body);
    } else if (onList) {
      body = Row(
        children: <Widget>[
          Icon(Icons.check_circle_outline, color: FlcColors.successAccent(context)),
          const SizedBox(width: FlcSpace.xs),
          const Expanded(child: Text("You're on the waiting list. We'll let you know if a place opens.", style: FlcTextStyles.body)),
          TextButton(onPressed: _busy ? null : _leave, child: const Text('Leave')),
        ],
      );
    } else if (signedIn) {
      body = Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
          onPressed: _busy ? null : _joinSignedIn,
          icon: const Icon(Icons.hourglass_top_outlined, size: 18),
          label: const Text('Join the waiting list'),
        ),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Your email'),
            onSubmitted: (_) => _joinGuest(),
          ),
          const SizedBox(height: FlcSpace.sm),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: _busy ? null : _joinGuest,
            icon: const Icon(Icons.hourglass_top_outlined, size: 18),
            label: const Text('Join the waiting list'),
          ),
          TextButton(onPressed: () => context.push('/sign-in'), child: const Text('Or sign in to be notified in the app')),
        ],
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(FlcSpace.md),
      decoration: BoxDecoration(border: Border.all(color: FlcColors.line), borderRadius: BorderRadius.circular(FlcRadius.card)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('Sold out', style: FlcTextStyles.h3),
          const SizedBox(height: FlcSpace.xxs),
          Text('Places sometimes open up. Join the waiting list and we\'ll tell you.', style: FlcTextStyles.bodySmall.copyWith(color: muted)),
          const SizedBox(height: FlcSpace.sm),
          body,
          if (_error != null) ...<Widget>[
            const SizedBox(height: FlcSpace.xs),
            Text(_error!, style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.errorAccent(context))),
          ],
        ],
      ),
    );
  }
}
