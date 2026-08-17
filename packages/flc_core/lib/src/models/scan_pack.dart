import 'package:freezed_annotation/freezed_annotation.dart';

part 'scan_pack.freezed.dart';

/// One ticket entry inside a downloaded scan pack — everything door staff
/// need to see and locally track redemption for, but never the crypto
/// secret itself (that's `event_scan_key`, shared across the whole pack,
/// not per-ticket — see ScanPackModel).
@freezed
abstract class ScanPackTicketModel with _$ScanPackTicketModel {
  const factory ScanPackTicketModel({
    required String ticketId,
    required String code,
    String? attendeeName,
    String? ticketTypeName,
    required String status,
  }) = _ScanPackTicketModel;

  const ScanPackTicketModel._();

  factory ScanPackTicketModel.fromApiJson(Map<String, dynamic> json) => ScanPackTicketModel(
        ticketId: json['ticket_id'] as String,
        code: json['code'] as String,
        attendeeName: json['attendee_name'] as String?,
        ticketTypeName: json['ticket_type_name'] as String?,
        status: json['status'] as String,
      );

  Map<String, dynamic> toCacheJson() => <String, dynamic>{
        'ticketId': ticketId,
        'code': code,
        'attendeeName': attendeeName,
        'ticketTypeName': ticketTypeName,
        'status': status,
      };

  factory ScanPackTicketModel.fromCacheJson(Map<String, dynamic> json) => ScanPackTicketModel(
        ticketId: json['ticketId'] as String,
        code: json['code'] as String,
        attendeeName: json['attendeeName'] as String?,
        ticketTypeName: json['ticketTypeName'] as String?,
        status: json['status'] as String,
      );
}

/// Briefing §13.5 — what get-scan-pack hands a staff device so it can
/// verify every ticket for one event fully offline: the derived
/// event_scan_key (never the master key) plus the current ticket list.
/// `eventScanKey` is intentionally excluded from this model's cache
/// round-trip — see EventScanKeyStore, which is where it actually lives
/// on-device (secure storage, same reasoning as TicketSecretsStore).
@freezed
abstract class ScanPackModel with _$ScanPackModel {
  const factory ScanPackModel({
    required String eventId,
    required List<ScanPackTicketModel> tickets,
    required DateTime expiresAt,
  }) = _ScanPackModel;

  factory ScanPackModel.fromApiJson(Map<String, dynamic> json) => ScanPackModel(
        eventId: json['event_id'] as String,
        tickets: (json['tickets'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(ScanPackTicketModel.fromApiJson)
            .toList(),
        expiresAt: DateTime.parse(json['expires_at'] as String),
      );
}
