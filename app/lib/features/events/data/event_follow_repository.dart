import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';

/// What the signed-in person has saved, and which of those they want
/// reminders for. Saved is the superset: a reminder always implies saved.
class EventFollows {
  const EventFollows({this.saved = const <String>{}, this.notify = const <String>{}});

  final Set<String> saved;
  final Set<String> notify;

  bool isSaved(String eventId) => saved.contains(eventId);
  bool isNotify(String eventId) => notify.contains(eventId);

  EventFollows copyWith({Set<String>? saved, Set<String>? notify}) =>
      EventFollows(saved: saved ?? this.saved, notify: notify ?? this.notify);
}

class EventFollowRepository {
  EventFollowRepository(this._client);

  final SupabaseClient _client;

  String? get _uid => _client.auth.currentUser?.id;

  Future<EventFollows> load() async {
    final String? uid = _uid;
    if (uid == null) return const EventFollows();
    final rows = await _client.from('event_favourites').select('event_id, notify').eq('user_id', uid);
    final Set<String> saved = <String>{};
    final Set<String> notify = <String>{};
    for (final Map<String, dynamic> r in rows) {
      final String id = r['event_id'] as String;
      saved.add(id);
      if (r['notify'] == true) notify.add(id);
    }
    return EventFollows(saved: saved, notify: notify);
  }

  /// Un-saving also drops any reminder (the row goes).
  Future<void> setSaved(String eventId, bool saved) async {
    final String uid = _uid!;
    if (saved) {
      await _client.from('event_favourites').upsert(<String, dynamic>{'user_id': uid, 'event_id': eventId}, onConflict: 'user_id,event_id', ignoreDuplicates: true);
    } else {
      await _client.from('event_favourites').delete().eq('user_id', uid).eq('event_id', eventId);
    }
  }

  /// Turning a reminder on saves the event as well.
  Future<void> setNotify(String eventId, bool notify) async {
    final String uid = _uid!;
    await _client.from('event_favourites').upsert(
      <String, dynamic>{'user_id': uid, 'event_id': eventId, 'notify': notify},
      onConflict: 'user_id,event_id',
    );
  }

  // ------------------------------------------------------- waiting list

  Future<bool> hasInterest(String eventId) async {
    final String? uid = _uid;
    if (uid == null) return false;
    final row = await _client.from('event_interests').select('id').eq('event_id', eventId).eq('user_id', uid).maybeSingle();
    return row != null;
  }

  Future<void> registerInterest(String eventId) async {
    await _client.from('event_interests').upsert(
      <String, dynamic>{'event_id': eventId, 'user_id': _uid},
      onConflict: 'event_id,user_id',
      ignoreDuplicates: true,
    );
  }

  Future<void> registerGuestInterest(String eventId, {required String email, String? name}) async {
    await _client.rpc('register_event_interest', params: <String, dynamic>{
      'p_event_id': eventId,
      'p_email': email,
      'p_name': name,
    });
  }

  Future<void> removeInterest(String eventId) async {
    final String? uid = _uid;
    if (uid == null) return;
    await _client.from('event_interests').delete().eq('event_id', eventId).eq('user_id', uid);
  }
}

final Provider<EventFollowRepository> eventFollowRepositoryProvider =
    Provider<EventFollowRepository>((ref) => EventFollowRepository(ref.watch(supabaseClientProvider)));

/// Optimistic: the heart/bell flips immediately and goes back if saving fails.
class EventFollowsController extends AsyncNotifier<EventFollows> {
  @override
  Future<EventFollows> build() async {
    if (ref.watch(currentUserProvider) == null) return const EventFollows();
    try {
      return await ref.watch(eventFollowRepositoryProvider).load();
    } catch (_) {
      return const EventFollows(); // saved events are a convenience, never block the screen
    }
  }

  EventFollows get _now => state.valueOrNull ?? const EventFollows();

  Future<bool> setSaved(String eventId, bool saved) async {
    final EventFollows before = _now;
    final Set<String> s = <String>{...before.saved};
    final Set<String> n = <String>{...before.notify};
    if (saved) {
      s.add(eventId);
    } else {
      s.remove(eventId);
      n.remove(eventId);
    }
    state = AsyncData<EventFollows>(EventFollows(saved: s, notify: n));
    try {
      await ref.read(eventFollowRepositoryProvider).setSaved(eventId, saved);
      return true;
    } catch (_) {
      state = AsyncData<EventFollows>(before);
      return false;
    }
  }

  Future<bool> setNotify(String eventId, bool notify) async {
    final EventFollows before = _now;
    final Set<String> s = <String>{...before.saved, eventId};
    final Set<String> n = <String>{...before.notify};
    if (notify) {
      n.add(eventId);
    } else {
      n.remove(eventId);
    }
    state = AsyncData<EventFollows>(EventFollows(saved: s, notify: n));
    try {
      await ref.read(eventFollowRepositoryProvider).setNotify(eventId, notify);
      return true;
    } catch (_) {
      state = AsyncData<EventFollows>(before);
      return false;
    }
  }
}

final AsyncNotifierProvider<EventFollowsController, EventFollows> eventFollowsProvider =
    AsyncNotifierProvider<EventFollowsController, EventFollows>(EventFollowsController.new);

/// Whether the signed-in person is on this sold-out event's waiting list.
final eventInterestProvider = FutureProvider.autoDispose.family<bool, String>((ref, eventId) {
  if (ref.watch(currentUserProvider) == null) return Future<bool>.value(false);
  return ref.watch(eventFollowRepositoryProvider).hasInterest(eventId);
});
