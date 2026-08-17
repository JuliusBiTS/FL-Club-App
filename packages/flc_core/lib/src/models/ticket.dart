import 'package:freezed_annotation/freezed_annotation.dart';

part 'ticket.freezed.dart';

/// Shaped from supabase/functions/get-my-tickets's response, not directly
/// from the `tickets` table (§9.4) — flattened here (rather than nesting an
/// `event` object) so it maps 1:1 onto a single Drift row for offline
/// caching. `ticketSecret` is deliberately NOT part of what gets cached in
/// Drift — see app/lib/features/tickets/data/tickets_repository.dart for
/// why it lives in flutter_secure_storage instead.
@freezed
abstract class TicketModel with _$TicketModel {
  const factory TicketModel({
    required String id,
    required String code,
    required String status,
    String? attendeeName,
    String? orderReference,
    String? ticketTypeName,
    required String eventId,
    required String eventSlug,
    required String eventTitle,
    required DateTime eventStartsAt,
    required String venueName,
    String? venueRoom,
    required String venueAddress,
  }) = _TicketModel;

  const TicketModel._();

  /// `json` is one element of get-my-tickets' `tickets` array — still
  /// carrying `ticket_secret`, which the caller pulls off separately
  /// before this flattening (kept out of the model on purpose, see above).
  factory TicketModel.fromApiJson(Map<String, dynamic> json) {
    final event = json['event'] as Map<String, dynamic>?;
    return TicketModel(
      id: json['ticket_id'] as String,
      code: json['code'] as String,
      status: json['status'] as String,
      attendeeName: json['attendee_name'] as String?,
      orderReference: json['order_reference'] as String?,
      ticketTypeName: json['ticket_type_name'] as String?,
      eventId: event?['id'] as String? ?? '',
      eventSlug: event?['slug'] as String? ?? '',
      eventTitle: event?['title'] as String? ?? 'Event',
      eventStartsAt: DateTime.parse(event?['starts_at'] as String? ?? DateTime.now().toIso8601String()),
      venueName: event?['venue_name'] as String? ?? '',
      venueRoom: event?['venue_room'] as String?,
      venueAddress: event?['venue_address'] as String? ?? '',
    );
  }

  /// Flat round-trip for the Drift cache's `json` blob column — unrelated
  /// to [fromApiJson]'s nested shape, which only ever comes from the
  /// network response and is consumed once before caching.
  Map<String, dynamic> toCacheJson() => <String, dynamic>{
        'id': id,
        'code': code,
        'status': status,
        'attendeeName': attendeeName,
        'orderReference': orderReference,
        'ticketTypeName': ticketTypeName,
        'eventId': eventId,
        'eventSlug': eventSlug,
        'eventTitle': eventTitle,
        'eventStartsAt': eventStartsAt.toIso8601String(),
        'venueName': venueName,
        'venueRoom': venueRoom,
        'venueAddress': venueAddress,
      };

  factory TicketModel.fromCacheJson(Map<String, dynamic> json) => TicketModel(
        id: json['id'] as String,
        code: json['code'] as String,
        status: json['status'] as String,
        attendeeName: json['attendeeName'] as String?,
        orderReference: json['orderReference'] as String?,
        ticketTypeName: json['ticketTypeName'] as String?,
        eventId: json['eventId'] as String,
        eventSlug: json['eventSlug'] as String,
        eventTitle: json['eventTitle'] as String,
        eventStartsAt: DateTime.parse(json['eventStartsAt'] as String),
        venueName: json['venueName'] as String,
        venueRoom: json['venueRoom'] as String?,
        venueAddress: json['venueAddress'] as String,
      );
}

extension TicketModelDisplay on TicketModel {
  bool get isValid => status == 'valid';
  bool get isUpcoming => isValid && eventStartsAt.isAfter(DateTime.now().subtract(const Duration(hours: 6)));

  String get venueDisplay => venueRoom == null ? venueName : '$venueRoom, $venueName';
}
