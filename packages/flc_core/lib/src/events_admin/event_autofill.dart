import '../models/event.dart' show EventLinkKind;
import 'event_draft.dart';

/// A single label the "Paste details" dialog reports back — e.g. "Title",
/// "3 speakers". Used to tell a producer what the auto-fill actually did.
typedef FieldLabel = String;

/// What applying an [ExtractedEventFields] to a draft actually did — shown to
/// the person right after they use "Paste details", so they know what to
/// double-check rather than trusting it blindly.
class AutoFillResult {
  const AutoFillResult({this.filled = const <FieldLabel>[], this.keptExisting = const <FieldLabel>[], this.notes = const <String>[]});

  /// Fields that were blank and are now filled in.
  final List<FieldLabel> filled;

  /// Fields the pasted text had an answer for, but the draft already had
  /// something in it — left alone, so nothing typed by hand is overwritten.
  final List<FieldLabel> keptExisting;

  /// The model's own notes on anything it wasn't confident about.
  final List<String> notes;

  bool get isEmpty => filled.isEmpty && keptExisting.isEmpty && notes.isEmpty;
}

/// One row of `events.links`/`events.speakers` shape, before it becomes a
/// [LinkDraft]/[SpeakerDraft] — kept separate so a malformed row from the
/// extractor (missing name/url) is simply skipped, not a parse failure for
/// the whole response.
class ExtractedSpeaker {
  ExtractedSpeaker({required this.name, this.role, this.bio});
  final String name;
  final String? role;
  final String? bio;
}

class ExtractedLink {
  ExtractedLink({required this.label, required this.url, required this.kind});
  final String label;
  final String url;
  final String kind;
}

/// The server's best-effort guess at an event's fields, parsed from whatever
/// free text a producer pasted in. Deliberately carries no price, capacity,
/// or ticket-type fields — those are never something to auto-fill.
class ExtractedEventFields {
  ExtractedEventFields({
    this.title,
    this.subtitle,
    this.summary,
    this.descriptionMd,
    this.category,
    this.tags = const <String>[],
    this.startsAt,
    this.endsAt,
    this.doorsAt,
    this.venueRoom,
    this.venueAddress,
    this.isOnline = false,
    this.livestreamUrl,
    List<ExtractedSpeaker>? speakers,
    List<ExtractedLink>? links,
    this.perks = const <String>[],
    this.notes = const <String>[],
  })  : speakers = speakers ?? const <ExtractedSpeaker>[],
        links = links ?? const <ExtractedLink>[];

  final String? title;
  final String? subtitle;
  final String? summary;
  final String? descriptionMd;
  final String? category;
  final List<String> tags;

  /// London wall-clock, same convention as [EventDraft] — the string from the
  /// server carries no timezone offset, so parsing it takes the digits at
  /// face value rather than shifting by whatever zone this device is in.
  final DateTime? startsAt;
  final DateTime? endsAt;
  final DateTime? doorsAt;

  final String? venueRoom;
  final String? venueAddress;
  final bool isOnline;
  final String? livestreamUrl;

  final List<ExtractedSpeaker> speakers;
  final List<ExtractedLink> links;
  final List<String> perks;
  final List<String> notes;

  static String? _str(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;
  static List<String> _strList(Object? v) => v is List ? <String>[for (final Object? e in v) if (_str(e) != null) _str(e)!] : <String>[];
  static DateTime? _dateTime(Object? v) => v is String ? DateTime.tryParse(v) : null;

  factory ExtractedEventFields.fromJson(Map<String, dynamic> json) {
    return ExtractedEventFields(
      title: _str(json['title']),
      subtitle: _str(json['subtitle']),
      summary: _str(json['summary']),
      descriptionMd: _str(json['description_md']),
      category: _str(json['category']),
      tags: _strList(json['tags']),
      startsAt: _dateTime(json['starts_at']),
      endsAt: _dateTime(json['ends_at']),
      doorsAt: _dateTime(json['doors_at']),
      venueRoom: _str(json['venue_room']),
      venueAddress: _str(json['venue_address']),
      isOnline: json['is_online'] == true,
      livestreamUrl: _str(json['livestream_url']),
      speakers: json['speakers'] is List
          ? <ExtractedSpeaker>[
              for (final Object? s in json['speakers'] as List)
                if (s is Map && _str(s['name']) != null) ExtractedSpeaker(name: _str(s['name'])!, role: _str(s['role']), bio: _str(s['bio'])),
            ]
          : const <ExtractedSpeaker>[],
      links: json['links'] is List
          ? <ExtractedLink>[
              for (final Object? l in json['links'] as List)
                if (l is Map && _str(l['label']) != null && _str(l['url']) != null)
                  ExtractedLink(label: _str(l['label'])!, url: _str(l['url'])!, kind: _str(l['kind']) ?? EventLinkKind.link),
            ]
          : const <ExtractedLink>[],
      perks: _strList(json['perks']),
      notes: _strList(json['notes']),
    );
  }

  bool get isEmpty =>
      title == null &&
      subtitle == null &&
      summary == null &&
      descriptionMd == null &&
      category == null &&
      tags.isEmpty &&
      startsAt == null &&
      endsAt == null &&
      doorsAt == null &&
      venueRoom == null &&
      venueAddress == null &&
      !isOnline &&
      livestreamUrl == null &&
      speakers.isEmpty &&
      links.isEmpty &&
      perks.isEmpty;

  /// Fills only what's currently blank on [draft] — nothing already typed by
  /// hand is ever overwritten. Returns a summary for the "here's what I did"
  /// message the editor shows afterwards.
  AutoFillResult applyTo(EventDraft draft) {
    final List<FieldLabel> filled = <FieldLabel>[];
    final List<FieldLabel> keptExisting = <FieldLabel>[];

    void text(String label, String? value, String Function() get, void Function(String) set) {
      if (value == null) return;
      if (get().trim().isNotEmpty) {
        keptExisting.add(label);
      } else {
        set(value);
        filled.add(label);
      }
    }

    text('Title', title, () => draft.title, (String v) => draft.title = v);
    text('Subtitle', subtitle, () => draft.subtitle, (String v) => draft.subtitle = v);
    text('Summary', summary, () => draft.summary, (String v) => draft.summary = v);
    text('Description', descriptionMd, () => draft.descriptionMd, (String v) => draft.descriptionMd = v);
    text('Venue room', venueRoom, () => draft.venueRoom, (String v) => draft.venueRoom = v);
    text('Venue address', venueAddress, () => draft.venueAddress, (String v) => draft.venueAddress = v);
    text('Livestream link', livestreamUrl, () => draft.livestreamUrl, (String v) => draft.livestreamUrl = v);

    if (category != null) {
      if (draft.category != null) {
        keptExisting.add('Category');
      } else if (kEventCategories.contains(category)) {
        draft.category = category;
        filled.add('Category');
      } else {
        // The model returned something outside the enum somehow (or the
        // category list has drifted) — note it rather than silently drop it.
        keptExisting.add('Category (unrecognised: "$category")');
      }
    }

    void dateField(String label, DateTime? value, DateTime? Function() get, void Function(DateTime) set) {
      if (value == null) return;
      if (get() != null) {
        keptExisting.add(label);
      } else {
        set(value);
        filled.add(label);
      }
    }

    dateField('Start date & time', startsAt, () => draft.startsAt, (DateTime v) => draft.startsAt = v);
    dateField('End time', endsAt, () => draft.endsAt, (DateTime v) => draft.endsAt = v);
    dateField('Doors time', doorsAt, () => draft.doorsAt, (DateTime v) => draft.doorsAt = v);

    if (isOnline && !draft.isOnline) {
      draft.isOnline = true;
      filled.add('Online / livestream');
    }

    final List<String> newTags = tags.where((String t) => !draft.tags.contains(t)).toList();
    if (newTags.isNotEmpty) {
      draft.tags = <String>[...draft.tags, ...newTags];
      filled.add(newTags.length == 1 ? '1 tag' : '${newTags.length} tags');
    }

    if (speakers.isNotEmpty) {
      if (draft.speakers.isNotEmpty) {
        keptExisting.add('Speakers');
      } else {
        draft.speakers = <SpeakerDraft>[for (final ExtractedSpeaker s in speakers) SpeakerDraft(name: s.name, role: s.role ?? '', bio: s.bio ?? '')];
        filled.add(speakers.length == 1 ? '1 speaker' : '${speakers.length} speakers');
      }
    }

    if (links.isNotEmpty) {
      if (draft.links.isNotEmpty) {
        keptExisting.add('Links');
      } else {
        draft.links = <LinkDraft>[for (final ExtractedLink l in links) LinkDraft(label: l.label, url: l.url, kind: EventLinkKind.all.contains(l.kind) ? l.kind : EventLinkKind.link)];
        filled.add(links.length == 1 ? '1 link' : '${links.length} links');
      }
    }

    if (perks.isNotEmpty) {
      final int room = kMaxPerks - draft.perks.length;
      if (room <= 0) {
        keptExisting.add('Perks');
      } else {
        final List<String> newPerks = perks.where((String p) => !draft.perks.contains(p)).take(room).toList();
        if (newPerks.isNotEmpty) {
          draft.perks = <String>[...draft.perks, ...newPerks];
          filled.add(newPerks.length == 1 ? '1 perk' : '${newPerks.length} perks');
        }
      }
    }

    return AutoFillResult(filled: filled, keptExisting: keptExisting, notes: notes);
  }
}
