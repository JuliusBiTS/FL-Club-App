import 'package:freezed_annotation/freezed_annotation.dart';

part 'event.freezed.dart';
part 'event.g.dart';

/// Mirrors the `events` table (supabase/migrations/20260817000003). Money
/// stays off this model entirely — prices live only on [TicketTypeModel],
/// read live, never cached as a display string here (briefing §8.2: never
/// hard-code a price anywhere).
@freezed
abstract class EventModel with _$EventModel {
  const factory EventModel({
    required String id,
    required String slug,
    required String title,
    String? subtitle,
    String? summary,
    @JsonKey(name: 'description_html') String? descriptionHtml,
    String? category,
    @Default(<String>[]) List<String> tags,
    @JsonKey(name: 'starts_at') required DateTime startsAt,
    @JsonKey(name: 'ends_at') DateTime? endsAt,
    @JsonKey(name: 'doors_at') DateTime? doorsAt,
    @Default('Europe/London') String timezone,
    @JsonKey(name: 'venue_name') @Default('The Frontline Club') String venueName,
    @JsonKey(name: 'venue_room') String? venueRoom,
    @JsonKey(name: 'venue_address') @Default('13 Norfolk Place, London W2 1QJ') String venueAddress,
    @JsonKey(name: 'hero_image_path') String? heroImagePath,
    @JsonKey(name: 'is_filmed') @Default(true) bool isFilmed,
    @JsonKey(name: 'members_only') @Default(false) bool membersOnly,
    @Default('draft') String status,
    @JsonKey(name: 'capacity_total') @Default(0) int capacityTotal,
    @JsonKey(name: 'capacity_app') @Default(0) int capacityApp,
    @JsonKey(name: 'capacity_eventbrite') @Default(0) int capacityEventbrite,
    @JsonKey(name: 'eventbrite_sold') @Default(0) int eventbriteSold,
    @JsonKey(name: 'eventbrite_url') String? eventbriteUrl,
    @JsonKey(name: 'eventbrite_synced_at') DateTime? eventbriteSyncedAt,
  }) = _EventModel;

  factory EventModel.fromJson(Map<String, dynamic> json) => _$EventModelFromJson(json);
}

extension EventModelAvailability on EventModel {
  /// A sync older than 30 minutes must never be treated as authoritative —
  /// briefing §11.2's "Sync stale" row: show app availability only, never
  /// claim "sold out" from stale Eventbrite data.
  bool get eventbriteSyncIsStale =>
      eventbriteSyncedAt == null ||
      DateTime.now().toUtc().difference(eventbriteSyncedAt!.toUtc()) > const Duration(minutes: 30);

  int get eventbriteRemaining => (capacityEventbrite - eventbriteSold).clamp(0, capacityEventbrite);
}
