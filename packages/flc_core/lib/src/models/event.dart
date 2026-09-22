import 'package:freezed_annotation/freezed_annotation.dart';

part 'event.freezed.dart';
part 'event.g.dart';

/// How prominently the club is promoting an event. "Selling fast" is NOT in
/// here on purpose — it is derived live from sales (events_selling_fast() in
/// the database), never something a person has to remember to switch off.
@JsonEnum(fieldRename: FieldRename.snake)
enum EventHighlight { none, fcRecommends, staffPick, specialOffer }

extension EventHighlightLabels on EventHighlight {
  /// The wire value stored in Postgres (`event_highlight` enum).
  String get wireName => switch (this) {
        EventHighlight.none => 'none',
        EventHighlight.fcRecommends => 'fc_recommends',
        EventHighlight.staffPick => 'staff_pick',
        EventHighlight.specialOffer => 'special_offer',
      };

  /// Shown on ribbons in the app and in the editor's picker. Null = no ribbon.
  String? get badgeLabel => switch (this) {
        EventHighlight.none => null,
        EventHighlight.fcRecommends => 'FC Recommends',
        EventHighlight.staffPick => 'Staff pick',
        EventHighlight.specialOffer => 'Special offer',
      };

  static EventHighlight fromWire(String? value) => EventHighlight.values.firstWhere(
        (h) => h.wireName == value,
        orElse: () => EventHighlight.none,
      );
}

/// One entry of `events.speakers` — `[{name, role, bio, photo_url}]`.
@freezed
abstract class EventSpeaker with _$EventSpeaker {
  const factory EventSpeaker({
    required String name,
    String? role,
    String? bio,
    @JsonKey(name: 'photo_url') String? photoUrl,
  }) = _EventSpeaker;

  factory EventSpeaker.fromJson(Map<String, dynamic> json) => _$EventSpeakerFromJson(json);
}

/// One entry of `events.links` — a book to buy, a film page, a reading list…
/// [kind] picks the icon; see [EventLinkKind].
@freezed
abstract class EventLink with _$EventLink {
  const factory EventLink({
    required String label,
    required String url,
    @Default('link') String kind,
  }) = _EventLink;

  factory EventLink.fromJson(Map<String, dynamic> json) => _$EventLinkFromJson(json);
}

/// The kinds of link an event can carry. Kept as plain strings in the
/// database so adding one later never needs a migration.
abstract final class EventLinkKind {
  static const String link = 'link';
  static const String book = 'book';
  static const String film = 'film';
  static const String article = 'article';
  static const String video = 'video';
  static const String donate = 'donate';

  static const List<String> all = <String>[link, book, film, article, video, donate];

  static String label(String kind) => switch (kind) {
        book => 'Book',
        film => 'Film',
        article => 'Article',
        video => 'Video',
        donate => 'Donate',
        _ => 'Link',
      };
}

/// Mirrors the `events` table (supabase/migrations/20260817000003 and
/// 20260921000001). Money stays off this model entirely — prices live only
/// on [TicketTypeModel], read live, never cached as a display string here
/// (briefing §8.2: never hard-code a price anywhere).
@freezed
abstract class EventModel with _$EventModel {
  const factory EventModel({
    required String id,
    required String slug,
    required String title,
    String? subtitle,
    String? summary,
    @JsonKey(name: 'description_html') String? descriptionHtml,
    @JsonKey(name: 'description_md') String? descriptionMd,
    String? category,
    @Default(<String>[]) List<String> tags,
    @JsonKey(name: 'starts_at') required DateTime startsAt,
    @JsonKey(name: 'ends_at') DateTime? endsAt,
    @JsonKey(name: 'doors_at') DateTime? doorsAt,
    @Default('Europe/London') String timezone,
    @JsonKey(name: 'venue_name') @Default('The Frontline Club') String venueName,
    @JsonKey(name: 'venue_room') String? venueRoom,
    @JsonKey(name: 'venue_address') @Default('13 Norfolk Place, London W2 1QJ') String venueAddress,
    @JsonKey(name: 'is_online') @Default(false) bool isOnline,
    @JsonKey(name: 'livestream_url') String? livestreamUrl,
    @JsonKey(name: 'hero_image_path') String? heroImagePath,
    @Default(<String>[]) List<String> gallery,
    @Default(<EventSpeaker>[]) List<EventSpeaker> speakers,
    @Default(<EventLink>[]) List<EventLink> links,
    @JsonKey(name: 'is_filmed') @Default(true) bool isFilmed,
    @JsonKey(name: 'members_only') @Default(false) bool membersOnly,
    @JsonKey(unknownEnumValue: EventHighlight.none) @Default(EventHighlight.none) EventHighlight highlight,
    @Default(<String>[]) List<String> perks,
    @JsonKey(name: 'loyalty_eligible') @Default(true) bool loyaltyEligible,
    @JsonKey(name: 'publish_at') DateTime? publishAt,
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

  bool get isPublished => status == 'published';

  /// A draft with a future publish time — the database flips it live.
  bool get isScheduled => status == 'draft' && publishAt != null;

  bool get isPromoted => highlight != EventHighlight.none || perks.isNotEmpty;
}
