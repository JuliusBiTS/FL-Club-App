import 'package:flutter/foundation.dart';

import 'event_admin_repository.dart';
import 'event_draft.dart';

/// State + save logic for one open event editor. The draft is mutated in
/// place by the form sections, which call [touch] so the preview and
/// checklist rebuild.
class EventEditorController extends ChangeNotifier {
  EventEditorController({
    required this.repository,
    required this.isAdmin,
    required this.draft,
    this.defaultTemplate = const <TicketTypeDraft>[],
  })  : _persistedStatus = draft.isNew ? null : draft.status,
        _loggedSchedule = draft.isNew ? null : _ScheduleSnapshot.of(draft);

  final EventAdminRepository repository;
  final bool isAdmin;
  final EventDraft draft;

  /// The club's standard ticket rows, for the "add standard tickets" shortcut.
  final List<TicketTypeDraft> defaultTemplate;

  String? _persistedStatus;
  _ScheduleSnapshot? _loggedSchedule;

  bool saving = false;
  bool dirty = false;

  bool get isNew => draft.isNew;

  /// The status as stored in the database (null until first saved).
  String? get persistedStatus => _persistedStatus;
  bool get isLive => _persistedStatus == 'published';

  /// Staff can't change price or capacity once an event is live, and can't
  /// touch a cancelled event at all — mirrors the database guard rails, so
  /// the form says so up front instead of failing on save.
  bool get commercialLocked => !isAdmin && (_persistedStatus == 'published' || _persistedStatus == 'cancelled');
  bool get readOnly => !isAdmin && _persistedStatus == 'cancelled';
  bool get canAddTicketTypes => isAdmin || _persistedStatus == null || _persistedStatus == 'draft';

  /// Date, time or venue changed on an event that already has buyers — the
  /// cue to offer telling ticket holders.
  bool get logisticsChangedForBuyers =>
      _loggedSchedule != null && draft.soldTotal > 0 && !_loggedSchedule!.matches(draft);

  void touch() {
    dirty = true;
    notifyListeners();
  }

  /// Saves and moves the event to [status]. Returns an error message, or null on success.
  Future<String?> save({required String status}) async {
    saving = true;
    notifyListeners();
    try {
      final String id = await repository.save(draft, status: status);
      draft
        ..id = id
        ..status = status;
      _persistedStatus = status;
      dirty = false;
      return null;
    } catch (e) {
      return EventAdminRepository.describeError(e);
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  /// Call once the "notify ticket holders?" question has been answered, so it
  /// isn't asked again for the same change.
  void acknowledgeLogistics() {
    _loggedSchedule = _ScheduleSnapshot.of(draft);
  }

  /// Applies a status change that has already been done in the database
  /// (postpone, unpublish, archive…) to the open form.
  void statusChangedElsewhere(String status) {
    draft.status = status;
    _persistedStatus = status;
    notifyListeners();
  }
}

class _ScheduleSnapshot {
  _ScheduleSnapshot(this.startsAt, this.doorsAt, this.venue);

  factory _ScheduleSnapshot.of(EventDraft d) =>
      _ScheduleSnapshot(d.startsAt, d.doorsAt, '${d.venueName}|${d.venueRoom}|${d.venueAddress}|${d.isOnline}');

  final DateTime? startsAt;
  final DateTime? doorsAt;
  final String venue;

  bool matches(EventDraft d) => startsAt == d.startsAt && doorsAt == d.doorsAt && venue == _ScheduleSnapshot.of(d).venue;
}
