/// What the buy bar on the event detail screen hands off to checkout.
/// Deliberately NOT a deep-linkable route param — a checkout in progress
/// isn't something you should be able to bookmark or share, and the price
/// shown here is display-only anyway (briefing §8.2: the server always
/// re-reads the real price from ticket_types, never trusts the client's
/// figure).
class CheckoutArgs {
  const CheckoutArgs({
    required this.eventId,
    required this.eventTitle,
    required this.ticketTypeId,
    required this.ticketTypeName,
    required this.quantity,
    required this.pricePerUnitMinor,
    required this.currency,
  });

  final String eventId;
  final String eventTitle;
  final String ticketTypeId;
  final String ticketTypeName;
  final int quantity;
  final int pricePerUnitMinor;
  final String currency;

  int get subtotalMinor => pricePerUnitMinor * quantity;
}
