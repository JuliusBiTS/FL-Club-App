import '../models/event.dart';
import '../models/ticket_type.dart';
import '../util/event_text.dart';
import '../util/london_time.dart';

/// Everything below is *editing state*, deliberately mutable and plain Dart
/// (no freezed): the editor mutates one draft as the person types and
/// validates it on demand. Times are London wall-clock values ("floating"
/// [DateTime]s, see [LondonTime]) and are converted to UTC only when a row is
/// built for the database.

const List<String> kAudienceKinds = <String>['public', 'member', 'concession', 'student', 'press', 'guest_of_speaker'];

String audienceLabel(String audience) => switch (audience) {
      'public' => 'Public',
      'member' => 'Member',
      'concession' => 'Concession',
      'student' => 'Student',
      'press' => 'Press / freelance',
      'guest_of_speaker' => 'Guest of speaker',
      _ => audience,
    };

/// Categories match how the club already titles its events
/// ("Panel discussion:", "Book talk:", "Screening + Q&A:").
const List<String> kEventCategories = <String>[
  'Panel discussion',
  'Book talk',
  'Screening + Q&A',
  'Online talk',
  'Workshop / training',
  'Members\' social',
  'Exhibition',
  'Awards & fundraising',
  'Private hire',
];

const int kMaxPerks = 4;
const int kMaxPerkLength = 40;
const int kMaxContentWarnings = 5;
const int kMaxContentWarningLength = 70;

/// One-tap starting points for the warnings field — staff can still type
/// their own.
const List<String> kContentWarningSuggestions = <String>[
  'May include distressing footage',
  'Contains flashing images',
  'Graphic descriptions of violence',
  'Strong language',
];

class SpeakerDraft {
  SpeakerDraft({this.name = '', this.role = '', this.bio = '', this.photoUrl});

  String name;
  String role;
  String bio;
  String? photoUrl;

  factory SpeakerDraft.fromModel(EventSpeaker s) =>
      SpeakerDraft(name: s.name, role: s.role ?? '', bio: s.bio ?? '', photoUrl: s.photoUrl);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name.trim(),
        if (role.trim().isNotEmpty) 'role': role.trim(),
        if (bio.trim().isNotEmpty) 'bio': bio.trim(),
        if (photoUrl != null && photoUrl!.isNotEmpty) 'photo_url': photoUrl,
      };
}

class LinkDraft {
  LinkDraft({this.label = '', this.url = '', this.kind = EventLinkKind.link});

  String label;
  String url;
  String kind;

  factory LinkDraft.fromModel(EventLink l) => LinkDraft(label: l.label, url: l.url, kind: l.kind);

  Map<String, dynamic> toJson() => <String, dynamic>{'label': label.trim(), 'url': url.trim(), 'kind': kind};
}

class TicketTypeDraft {
  TicketTypeDraft({
    this.id,
    this.name = '',
    this.audience = 'public',
    this.priceMinor = 0,
    this.quantity = 0,
    this.maxPerOrder = 4,
    this.requiresMember = false,
    this.requiresProof = false,
    this.salesStart,
    this.salesEnd,
    this.isActive = true,
    this.sold = 0,
  });

  String? id;
  String name;
  String audience;
  int priceMinor;
  int quantity;
  int maxPerOrder;
  bool requiresMember;
  bool requiresProof;
  DateTime? salesStart; // London wall clock
  DateTime? salesEnd; // London wall clock
  bool isActive;

  /// Tickets already issued against this type (read-only, from the database).
  int sold;

  bool get hasSales => sold > 0;

  factory TicketTypeDraft.fromModel(TicketTypeModel t, {int sold = 0}) => TicketTypeDraft(
        id: t.id,
        name: t.name,
        audience: t.audience,
        priceMinor: t.priceMinor,
        quantity: t.quantity,
        maxPerOrder: t.maxPerOrder,
        requiresMember: t.requiresMember,
        requiresProof: t.requiresProof,
        salesStart: t.salesStartAt == null ? null : LondonTime.fromUtc(t.salesStartAt!),
        salesEnd: t.salesEndAt == null ? null : LondonTime.fromUtc(t.salesEndAt!),
        isActive: t.isActive,
        sold: sold,
      );

  /// From a `club_settings.default_ticket_template` entry.
  factory TicketTypeDraft.fromTemplate(Map<String, dynamic> json) => TicketTypeDraft(
        name: json['name'] as String? ?? '',
        audience: json['audience'] as String? ?? 'public',
        priceMinor: (json['price_minor'] as num?)?.toInt() ?? 0,
        requiresMember: json['requires_member'] as bool? ?? false,
        requiresProof: json['requires_proof'] as bool? ?? false,
      );

  Map<String, dynamic> toRow({required String eventId, required int sortOrder}) => <String, dynamic>{
        'event_id': eventId,
        'name': name.trim(),
        'audience': audience,
        'price_minor': priceMinor,
        'currency': 'GBP',
        'quantity': quantity,
        'max_per_order': maxPerOrder,
        'requires_member': requiresMember,
        'requires_proof': requiresProof,
        'sales_start_at': salesStart == null ? null : LondonTime.toUtc(salesStart!).toIso8601String(),
        'sales_end_at': salesEnd == null ? null : LondonTime.toUtc(salesEnd!).toIso8601String(),
        'sort_order': sortOrder,
        'is_active': isActive,
      };
}

class EventIssues {
  const EventIssues({this.errors = const <String>[], this.warnings = const <String>[]});

  /// Block saving/publishing.
  final List<String> errors;

  /// Worth a second look, but don't block.
  final List<String> warnings;

  bool get ok => errors.isEmpty;
}

class EventDraft {
  EventDraft({
    this.id,
    this.slug,
    this.status = 'draft',
    this.title = '',
    this.subtitle = '',
    this.summary = '',
    this.descriptionMd = '',
    this.category,
    List<String>? tags,
    this.startsAt,
    this.endsAt,
    this.doorsAt,
    this.publishAt,
    this.venueName = 'The Frontline Club',
    this.venueRoom = '',
    this.venueAddress = '13 Norfolk Place, London W2 1QJ',
    this.isOnline = false,
    this.livestreamUrl = '',
    this.heroImageUrl,
    List<String>? gallery,
    List<SpeakerDraft>? speakers,
    List<LinkDraft>? links,
    this.isFilmed = true,
    this.membersOnly = false,
    this.loyaltyEligible = true,
    this.highlight = EventHighlight.none,
    List<String>? perks,
    List<String>? contentWarnings,
    this.pickByName = '',
    this.pickByPhotoUrl,
    this.pickQuote = '',
    this.capacityTotal = 0,
    this.capacityApp = 0,
    this.capacityEventbrite = 0,
    this.eventbriteUrl = '',
    List<TicketTypeDraft>? ticketTypes,
    this.issuedTickets = 0,
    this.eventbriteSold = 0,
  })  : tags = tags ?? <String>[],
        gallery = gallery ?? <String>[],
        speakers = speakers ?? <SpeakerDraft>[],
        links = links ?? <LinkDraft>[],
        perks = perks ?? <String>[],
        contentWarnings = contentWarnings ?? <String>[],
        ticketTypes = ticketTypes ?? <TicketTypeDraft>[];

  String? id;
  String? slug;
  String status;

  String title;
  String subtitle;
  String summary;
  String descriptionMd;
  String? category;
  List<String> tags;

  DateTime? startsAt; // London wall clock
  DateTime? endsAt;
  DateTime? doorsAt;
  DateTime? publishAt;

  String venueName;
  String venueRoom;
  String venueAddress;
  bool isOnline;
  String livestreamUrl;

  String? heroImageUrl;
  List<String> gallery;
  List<SpeakerDraft> speakers;
  List<LinkDraft> links;

  bool isFilmed;
  bool membersOnly;
  bool loyaltyEligible;
  EventHighlight highlight;
  List<String> perks;
  List<String> contentWarnings;

  /// A staff member's personal quote, shown as a speech bubble — independent
  /// of [highlight]. Blank [pickQuote] means no bubble, whatever the ribbon.
  String pickByName;
  String? pickByPhotoUrl;
  String pickQuote;

  int capacityTotal;
  int capacityApp;
  int capacityEventbrite;
  String eventbriteUrl;
  List<TicketTypeDraft> ticketTypes;

  /// Read-only, from the database — used to stop capacity being cut below
  /// what has already been sold.
  int issuedTickets;
  int eventbriteSold;

  /// Copies over the "how this kind of event is normally run" fields from
  /// a previous event — feedback: "copy settings from last event". Never
  /// touches title, dates, description, speakers, links, capacity or
  /// ticket types/pricing: those need a deliberate look at every single
  /// event, so copying them silently would be the wrong kind of shortcut.
  /// Also skips pickQuote — a quote is written fresh for each event, only
  /// who it's from and their photo carry over (see recentStaffPickPeople).
  void applyRecurringSettingsFrom(EventModel other) {
    venueName = other.venueName;
    venueRoom = other.venueRoom ?? '';
    venueAddress = other.venueAddress;
    isOnline = other.isOnline;
    category = other.category;
    isFilmed = other.isFilmed;
    membersOnly = other.membersOnly;
    loyaltyEligible = other.loyaltyEligible;
    highlight = other.highlight;
    perks = List<String>.of(other.perks);
    pickByName = other.pickByName ?? '';
    pickByPhotoUrl = other.pickByPhotoUrl;
  }

  bool get isNew => id == null;
  bool get isPublished => status == 'published';
  bool get isCancelled => status == 'cancelled';
  int get soldTotal => issuedTickets + eventbriteSold;

  factory EventDraft.fromModel(
    EventModel e,
    List<TicketTypeModel> types, {
    Map<String, int> soldByType = const <String, int>{},
  }) {
    return EventDraft(
      id: e.id,
      slug: e.slug,
      status: e.status,
      title: e.title,
      subtitle: e.subtitle ?? '',
      summary: e.summary ?? '',
      // Events made before the editor existed have HTML only; give the
      // person plain text to start from rather than an empty box.
      descriptionMd: e.descriptionMd ?? (e.descriptionHtml == null ? '' : EventText.stripHtml(e.descriptionHtml!)),
      category: e.category,
      tags: List<String>.of(e.tags),
      startsAt: LondonTime.fromUtc(e.startsAt),
      endsAt: e.endsAt == null ? null : LondonTime.fromUtc(e.endsAt!),
      doorsAt: e.doorsAt == null ? null : LondonTime.fromUtc(e.doorsAt!),
      publishAt: e.publishAt == null ? null : LondonTime.fromUtc(e.publishAt!),
      venueName: e.venueName,
      venueRoom: e.venueRoom ?? '',
      venueAddress: e.venueAddress,
      isOnline: e.isOnline,
      livestreamUrl: e.livestreamUrl ?? '',
      heroImageUrl: e.heroImagePath,
      gallery: List<String>.of(e.gallery),
      speakers: e.speakers.map(SpeakerDraft.fromModel).toList(),
      links: e.links.map(LinkDraft.fromModel).toList(),
      isFilmed: e.isFilmed,
      membersOnly: e.membersOnly,
      loyaltyEligible: e.loyaltyEligible,
      highlight: e.highlight,
      perks: List<String>.of(e.perks),
      contentWarnings: List<String>.of(e.contentWarnings),
      pickByName: e.pickByName ?? '',
      pickByPhotoUrl: e.pickByPhotoUrl,
      pickQuote: e.pickQuote ?? '',
      capacityTotal: e.capacityTotal,
      capacityApp: e.capacityApp,
      capacityEventbrite: e.capacityEventbrite,
      eventbriteUrl: e.eventbriteUrl ?? '',
      ticketTypes: types.map((t) => TicketTypeDraft.fromModel(t, sold: soldByType[t.id] ?? 0)).toList(),
      issuedTickets: soldByType.values.fold<int>(0, (int a, int b) => a + b),
      eventbriteSold: e.eventbriteSold,
    );
  }

  /// A copy for "Duplicate" — same format, new draft, one week later, with
  /// no sales history carried over.
  EventDraft duplicated() {
    final DateTime? nextStart = startsAt?.add(const Duration(days: 7));
    return EventDraft(
      status: 'draft',
      title: title,
      subtitle: subtitle,
      summary: summary,
      descriptionMd: descriptionMd,
      category: category,
      tags: List<String>.of(tags),
      startsAt: nextStart,
      endsAt: endsAt?.add(const Duration(days: 7)),
      doorsAt: doorsAt?.add(const Duration(days: 7)),
      venueName: venueName,
      venueRoom: venueRoom,
      venueAddress: venueAddress,
      isOnline: isOnline,
      livestreamUrl: livestreamUrl,
      heroImageUrl: heroImageUrl,
      gallery: List<String>.of(gallery),
      speakers: speakers.map((s) => SpeakerDraft(name: s.name, role: s.role, bio: s.bio, photoUrl: s.photoUrl)).toList(),
      links: links.map((l) => LinkDraft(label: l.label, url: l.url, kind: l.kind)).toList(),
      isFilmed: isFilmed,
      membersOnly: membersOnly,
      loyaltyEligible: loyaltyEligible,
      highlight: EventHighlight.none,
      perks: List<String>.of(perks),
      contentWarnings: List<String>.of(contentWarnings),
      capacityTotal: capacityTotal,
      capacityApp: capacityApp,
      capacityEventbrite: 0,
      ticketTypes: ticketTypes
          .where((t) => t.isActive)
          .map((t) => TicketTypeDraft(
                name: t.name,
                audience: t.audience,
                priceMinor: t.priceMinor,
                quantity: t.quantity,
                maxPerOrder: t.maxPerOrder,
                requiresMember: t.requiresMember,
                requiresProof: t.requiresProof,
              ))
          .toList(),
    );
  }

  /// The `events` row for an insert/update. [status] is passed explicitly so
  /// "Save draft" and "Publish" can share this.
  Map<String, dynamic> toEventRow({required String forStatus}) {
    String? nullIfBlank(String s) => s.trim().isEmpty ? null : s.trim();
    return <String, dynamic>{
      'title': title.trim(),
      'subtitle': nullIfBlank(subtitle),
      'summary': nullIfBlank(summary),
      'description_md': nullIfBlank(descriptionMd),
      'description_html': descriptionMd.trim().isEmpty ? null : EventText.markdownToHtml(descriptionMd),
      'category': category,
      'tags': tags,
      'starts_at': LondonTime.toUtc(startsAt!).toIso8601String(),
      'ends_at': endsAt == null ? null : LondonTime.toUtc(endsAt!).toIso8601String(),
      'doors_at': doorsAt == null ? null : LondonTime.toUtc(doorsAt!).toIso8601String(),
      'publish_at': publishAt == null ? null : LondonTime.toUtc(publishAt!).toIso8601String(),
      'timezone': 'Europe/London',
      'venue_name': venueName.trim().isEmpty ? 'The Frontline Club' : venueName.trim(),
      'venue_room': nullIfBlank(venueRoom),
      'venue_address': venueAddress.trim().isEmpty ? '13 Norfolk Place, London W2 1QJ' : venueAddress.trim(),
      'is_online': isOnline,
      'livestream_url': nullIfBlank(livestreamUrl),
      'hero_image_path': heroImageUrl,
      'gallery': gallery,
      'speakers': speakers.where((s) => s.name.trim().isNotEmpty).map((s) => s.toJson()).toList(),
      'links': links.where((l) => l.url.trim().isNotEmpty).map((l) => l.toJson()).toList(),
      'is_filmed': isFilmed,
      'members_only': membersOnly,
      'loyalty_eligible': loyaltyEligible,
      'highlight': highlight.wireName,
      'perks': perks,
      'content_warnings': contentWarnings.map((String w) => w.trim()).where((String w) => w.isNotEmpty).toList(),
      'pick_by_name': nullIfBlank(pickByName),
      'pick_by_photo_url': pickByPhotoUrl,
      'pick_quote': nullIfBlank(pickQuote),
      'capacity_total': capacityTotal,
      'capacity_app': capacityApp,
      'capacity_eventbrite': capacityEventbrite,
      'eventbrite_url': nullIfBlank(eventbriteUrl),
      'status': forStatus,
    };
  }

  static final RegExp _urlPattern = RegExp(r'^https?://[^\s/$.?#][^\s]*$', caseSensitive: false);
  static bool isValidUrl(String s) => _urlPattern.hasMatch(s.trim());

  /// [publishing] = this save will leave the event live (or scheduled).
  EventIssues validate({required bool publishing}) {
    final List<String> errors = <String>[];
    final List<String> warnings = <String>[];

    if (title.trim().isEmpty) errors.add('Give the event a title.');
    if (title.trim().length > 120) errors.add('The title is too long (120 characters max).');

    if (startsAt == null) {
      errors.add('Pick a start date and time.');
    } else {
      if (endsAt != null && !endsAt!.isAfter(startsAt!)) errors.add('The end time must be after the start time.');
      if (doorsAt != null && doorsAt!.isAfter(startsAt!)) errors.add('Doors should open before the event starts.');
      if (publishing && isNew && startsAt!.isBefore(LondonTime.fromUtc(DateTime.now()))) {
        warnings.add('This event starts in the past.');
      }
    }

    if (publishAt != null && publishAt!.isBefore(LondonTime.fromUtc(DateTime.now())) && !isPublished) {
      warnings.add('The scheduled publish time has already passed, so it will go live within a minute of saving.');
    }

    if (isOnline && livestreamUrl.trim().isEmpty) {
      (publishing ? errors : warnings).add('Add the livestream link for this online event.');
    }
    if (livestreamUrl.trim().isNotEmpty && !isValidUrl(livestreamUrl)) {
      errors.add('The livestream link must start with https://');
    }
    if (eventbriteUrl.trim().isNotEmpty && !isValidUrl(eventbriteUrl)) {
      errors.add('The Eventbrite link must start with https://');
    }

    if (capacityTotal < 0 || capacityApp < 0 || capacityEventbrite < 0) errors.add('Capacity can\'t be negative.');
    if (capacityApp + capacityEventbrite > capacityTotal) {
      errors.add('App + Eventbrite capacity ($capacityApp + $capacityEventbrite) is more than the total ($capacityTotal).');
    }
    if (!isNew && capacityTotal < soldTotal) {
      errors.add('Total capacity can\'t be below the $soldTotal tickets already sold.');
    }

    final Iterable<TicketTypeDraft> live = ticketTypes.where((t) => t.isActive);
    final int allocated = live.fold<int>(0, (int a, TicketTypeDraft t) => a + t.quantity);
    if (allocated > capacityApp) {
      errors.add('Ticket quantities add up to $allocated, but only $capacityApp are allocated to the app.');
    }
    for (final TicketTypeDraft t in ticketTypes) {
      final String label = t.name.trim().isEmpty ? 'A ticket type' : '"${t.name.trim()}"';
      if (t.name.trim().isEmpty) errors.add('Every ticket type needs a name.');
      if (t.priceMinor < 0) errors.add('$label can\'t have a negative price.');
      if (t.quantity < 0) errors.add('$label can\'t have a negative quantity.');
      if (t.quantity < t.sold) errors.add('$label has ${t.sold} sold — quantity can\'t go below that.');
      if (t.maxPerOrder < 1) errors.add('$label must allow at least 1 ticket per order.');
      if (t.salesStart != null && t.salesEnd != null && !t.salesEnd!.isAfter(t.salesStart!)) {
        errors.add('$label: sales must close after they open.');
      }
    }

    for (final SpeakerDraft s in speakers) {
      if (s.name.trim().isEmpty && (s.role.trim().isNotEmpty || s.bio.trim().isNotEmpty)) {
        errors.add('A speaker has a role or bio but no name.');
        break;
      }
    }
    for (final LinkDraft l in links) {
      if (l.url.trim().isEmpty && l.label.trim().isEmpty) continue;
      if (l.label.trim().isEmpty) errors.add('Every link needs a label (what the button says).');
      if (!isValidUrl(l.url)) errors.add('"${l.label.trim().isEmpty ? l.url : l.label}" needs a link starting with https://');
    }

    if (pickQuote.trim().isNotEmpty && pickByName.trim().isEmpty) {
      errors.add('Add the staff member\'s name for the quote, or remove the quote.');
    }
    if (pickQuote.trim().length > 280) errors.add('Keep the staff quote under 280 characters.');

    if (perks.length > kMaxPerks) errors.add('Add at most $kMaxPerks perks.');
    for (final String p in perks) {
      if (p.length > kMaxPerkLength) errors.add('Keep each perk under $kMaxPerkLength characters.');
    }

    if (contentWarnings.length > kMaxContentWarnings) errors.add('Add at most $kMaxContentWarnings content warnings.');
    for (final String w in contentWarnings) {
      if (w.length > kMaxContentWarningLength) errors.add('Keep each content warning under $kMaxContentWarningLength characters.');
    }

    if (publishing) {
      if (summary.trim().isEmpty) warnings.add('There\'s no short summary — it\'s what shows on the event card.');
      if (heroImageUrl == null) warnings.add('There\'s no picture yet.');
      if (category == null) warnings.add('Pick a category so the event shows up under the right filter.');
      if (capacityApp > 0 && live.isEmpty) warnings.add('No ticket types are on sale in the app.');
      if (speakers.isEmpty) warnings.add('No speakers listed.');
    }

    return EventIssues(errors: errors, warnings: warnings);
  }
}
