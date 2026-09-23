import 'package:flutter/material.dart';

import '../../theme/flc_colors.dart';
import '../../theme/flc_spacing.dart';
import '../../theme/flc_typography.dart';
import '../event_draft.dart';
import '../event_editor_controller.dart';
import '../widgets/editor_widgets.dart';

/// Capacity split and ticket types.
class TicketsSection extends StatelessWidget {
  const TicketsSection({required this.controller, super.key});

  final EventEditorController controller;

  @override
  Widget build(BuildContext context) {
    final EventDraft d = controller.draft;
    final bool locked = controller.commercialLocked;
    final bool enabled = !controller.readOnly;
    final int allocated = d.ticketTypes.where((TicketTypeDraft t) => t.isActive).fold<int>(0, (int a, TicketTypeDraft t) => a + t.quantity);

    return SectionCard(
      title: 'Tickets & capacity',
      subtitle: 'How many seats there are, and what each kind of ticket costs.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (locked)
            const _Notice(
              icon: Icons.lock_outline,
              text: 'This event is live, so price and capacity are locked. An admin can change them — you can still edit names, sales windows and what\'s on sale.',
            ),
          if (d.soldTotal > 0)
            _Notice(icon: Icons.confirmation_number_outlined, text: '${d.soldTotal} tickets sold so far (${d.issuedTickets} in the app, ${d.eventbriteSold} on Eventbrite).'),
          ResponsiveRow(
            children: <Widget>[
              IntField(
                label: 'Total capacity',
                value: d.capacityTotal,
                enabled: enabled && !locked,
                onChanged: (int v) {
                  d.capacityTotal = v;
                  controller.touch();
                },
              ),
              IntField(
                label: 'Sold in the app',
                value: d.capacityApp,
                enabled: enabled && !locked,
                helper: 'Seats you sell through this app',
                onChanged: (int v) {
                  d.capacityApp = v;
                  controller.touch();
                },
              ),
              IntField(
                label: 'Held for Eventbrite',
                value: d.capacityEventbrite,
                enabled: enabled && !locked,
                onChanged: (int v) {
                  d.capacityEventbrite = v;
                  controller.touch();
                },
              ),
            ],
          ),
          if (d.capacityEventbrite > 0 || d.eventbriteUrl.isNotEmpty) ...<Widget>[
            const SizedBox(height: FlcSpace.sm),
            TextFormField(
              initialValue: d.eventbriteUrl,
              enabled: enabled,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Eventbrite link',
                hintText: 'https://www.eventbrite.co.uk/e/…',
                helperText: 'Sold counts are pulled from Eventbrite every 5 minutes.',
              ),
              onChanged: (String v) {
                d.eventbriteUrl = v;
                controller.touch();
              },
            ),
          ],
          const SizedBox(height: FlcSpace.md),
          Row(
            children: <Widget>[
              Expanded(child: Text('Ticket types', style: FlcTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600))),
              Text(
                '$allocated of ${d.capacityApp} app seats assigned',
                style: FlcTextStyles.caption.copyWith(color: allocated > d.capacityApp ? FlcColors.error : FlcColors.secondary(context)),
              ),
            ],
          ),
          const SizedBox(height: FlcSpace.xs),
          for (final TicketTypeDraft t in d.ticketTypes)
            _TicketTypeCard(key: ObjectKey(t), controller: controller, ticket: t),
          if (controller.canAddTicketTypes && enabled)
            Wrap(
              spacing: FlcSpace.xs,
              children: <Widget>[
                OutlinedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Add ticket type'),
                  onPressed: () {
                    d.ticketTypes.add(TicketTypeDraft(name: '', quantity: 0));
                    controller.touch();
                  },
                ),
                if (controller.defaultTemplate.isNotEmpty && d.ticketTypes.isEmpty)
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.auto_awesome_outlined),
                    label: const Text('Use the club\'s standard tickets'),
                    onPressed: () {
                      for (final TicketTypeDraft t in controller.defaultTemplate) {
                        d.ticketTypes.add(TicketTypeDraft(
                          name: t.name,
                          audience: t.audience,
                          priceMinor: t.priceMinor,
                          requiresMember: t.requiresMember,
                          requiresProof: t.requiresProof,
                        ));
                      }
                      controller.touch();
                    },
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: FlcSpace.sm),
      padding: const EdgeInsets.all(FlcSpace.sm),
      decoration: BoxDecoration(color: FlcColors.brand.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(FlcRadius.input)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: FlcColors.accent(context)),
          const SizedBox(width: FlcSpace.xs),
          Expanded(child: Text(text, style: FlcTextStyles.bodySmall)),
        ],
      ),
    );
  }
}

class _TicketTypeCard extends StatelessWidget {
  const _TicketTypeCard({required this.controller, required this.ticket, super.key});

  final EventEditorController controller;
  final TicketTypeDraft ticket;

  @override
  Widget build(BuildContext context) {
    final EventDraft d = controller.draft;
    final bool locked = controller.commercialLocked;
    final bool enabled = !controller.readOnly;

    return Container(
      margin: const EdgeInsets.only(bottom: FlcSpace.sm),
      padding: const EdgeInsets.all(FlcSpace.sm),
      decoration: BoxDecoration(
        border: Border.all(color: ticket.isActive ? FlcColors.line : FlcColors.line.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(FlcRadius.card),
        color: ticket.isActive ? null : FlcColors.line.withValues(alpha: 0.25),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (ticket.hasSales)
                Padding(
                  padding: const EdgeInsets.only(right: FlcSpace.xs),
                  child: Chip(label: Text('${ticket.sold} sold'), visualDensity: VisualDensity.compact),
                ),
              if (!ticket.isActive) const Chip(label: Text('Not on sale'), visualDensity: VisualDensity.compact),
              const Spacer(),
              if (enabled && !ticket.hasSales && controller.canAddTicketTypes)
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Remove ticket type',
                  onPressed: () {
                    d.ticketTypes.remove(ticket);
                    controller.touch();
                  },
                ),
            ],
          ),
          ResponsiveRow(
            breakpoint: 620,
            children: <Widget>[
              TextFormField(
                initialValue: ticket.name,
                enabled: enabled,
                decoration: const InputDecoration(labelText: 'Name', hintText: 'Standard', isDense: true),
                onChanged: (String v) {
                  ticket.name = v;
                  controller.touch();
                },
              ),
              DropdownButtonFormField<String>(
                initialValue: ticket.audience,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Who it\'s for', isDense: true),
                items: <DropdownMenuItem<String>>[
                  for (final String a in kAudienceKinds) DropdownMenuItem<String>(value: a, child: Text(audienceLabel(a))),
                ],
                onChanged: enabled && !locked
                    ? (String? v) {
                        ticket.audience = v ?? 'public';
                        ticket.requiresMember = ticket.audience == 'member';
                        controller.touch();
                      }
                    : null,
              ),
            ],
          ),
          const SizedBox(height: FlcSpace.xs),
          ResponsiveRow(
            breakpoint: 620,
            children: <Widget>[
              MoneyField(
                label: 'Price',
                valueMinor: ticket.priceMinor,
                enabled: enabled && !locked,
                onChanged: (int v) {
                  ticket.priceMinor = v;
                  controller.touch();
                },
              ),
              IntField(
                label: 'Quantity',
                value: ticket.quantity,
                enabled: enabled && !locked,
                onChanged: (int v) {
                  ticket.quantity = v;
                  controller.touch();
                },
              ),
              IntField(
                label: 'Max per order',
                value: ticket.maxPerOrder,
                enabled: enabled,
                onChanged: (int v) {
                  ticket.maxPerOrder = v;
                  controller.touch();
                },
              ),
            ],
          ),
          Wrap(
            spacing: FlcSpace.md,
            children: <Widget>[
              _MiniSwitch(
                label: 'Members only',
                value: ticket.requiresMember,
                onChanged: enabled && !locked
                    ? (bool v) {
                        ticket.requiresMember = v;
                        controller.touch();
                      }
                    : null,
              ),
              _MiniSwitch(
                label: 'ID checked at the door',
                value: ticket.requiresProof,
                onChanged: enabled
                    ? (bool v) {
                        ticket.requiresProof = v;
                        controller.touch();
                      }
                    : null,
              ),
              _MiniSwitch(
                label: 'On sale',
                value: ticket.isActive,
                onChanged: enabled
                    ? (bool v) {
                        ticket.isActive = v;
                        controller.touch();
                      }
                    : null,
              ),
            ],
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Sales window (optional)', style: FlcTextStyles.bodySmall),
            children: <Widget>[
              ResponsiveRow(
                breakpoint: 620,
                children: <Widget>[
                  DateTimeField(
                    label: 'Sales open',
                    value: ticket.salesStart,
                    enabled: enabled,
                    clearable: true,
                    onChanged: (DateTime? v) {
                      ticket.salesStart = v;
                      controller.touch();
                    },
                  ),
                  DateTimeField(
                    label: 'Sales close',
                    value: ticket.salesEnd,
                    enabled: enabled,
                    clearable: true,
                    onChanged: (DateTime? v) {
                      ticket.salesEnd = v;
                      controller.touch();
                    },
                  ),
                ],
              ),
              const SizedBox(height: FlcSpace.xs),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniSwitch extends StatelessWidget {
  const _MiniSwitch({required this.label, required this.value, required this.onChanged});

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Switch(value: value, onChanged: onChanged),
        Text(label, style: FlcTextStyles.bodySmall),
      ],
    );
  }
}

/// How this event interacts with membership and the loyalty scheme, with a
/// live summary so nobody has to remember the rules.
class MembershipLoyaltySection extends StatelessWidget {
  const MembershipLoyaltySection({required this.controller, super.key});

  final EventEditorController controller;

  @override
  Widget build(BuildContext context) {
    final EventDraft d = controller.draft;
    final bool enabled = !controller.readOnly;
    final List<TicketTypeDraft> active = d.ticketTypes.where((TicketTypeDraft t) => t.isActive).toList();
    final List<TicketTypeDraft> memberTickets = active.where((TicketTypeDraft t) => t.requiresMember || t.audience == 'member').toList();
    final List<TicketTypeDraft> openTickets = active.where((TicketTypeDraft t) => !t.requiresMember && t.audience != 'member').toList();

    String price(TicketTypeDraft t) => t.priceMinor == 0 ? 'Free' : '£${minorToPounds(t.priceMinor)}';

    return SectionCard(
      title: 'Membership & loyalty',
      subtitle: 'Who can come, and whether tickets count towards free tickets.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Members only'),
            subtitle: Text(
              'Only active members can book. Non-members see the event but can\'t buy.',
              style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.secondary(context)),
            ),
            value: d.membersOnly,
            onChanged: enabled
                ? (bool v) {
                    d.membersOnly = v;
                    controller.touch();
                  }
                : null,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Counts towards loyalty'),
            subtitle: Text(
              'Buying a ticket earns a loyalty point — one per person per event, however many tickets. Free tickets never earn a point. Turn off for private, partner or fundraising events.',
              style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.secondary(context)),
            ),
            value: d.loyaltyEligible,
            onChanged: enabled
                ? (bool v) {
                    d.loyaltyEligible = v;
                    controller.touch();
                  }
                : null,
          ),
          const Divider(),
          Text('How this will read to people', style: FlcTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: FlcSpace.xs),
          if (active.isEmpty)
            Text('Add ticket types above to see the pricing summary.', style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.secondary(context)))
          else ...<Widget>[
            for (final TicketTypeDraft t in memberTickets)
              _SummaryLine(icon: Icons.badge_outlined, text: 'Members: ${t.name.isEmpty ? 'Member ticket' : t.name} — ${price(t)}'),
            for (final TicketTypeDraft t in openTickets)
              _SummaryLine(
                icon: Icons.person_outline,
                text: '${audienceLabel(t.audience)}: ${t.name.isEmpty ? 'Ticket' : t.name} — ${price(t)}${t.requiresProof ? ' · ID at the door' : ''}',
              ),
            if (d.membersOnly && openTickets.isNotEmpty)
              const _SummaryLine(
                icon: Icons.warning_amber_outlined,
                text: 'This is a members-only event but some tickets aren\'t restricted to members. Non-members still won\'t be able to buy — consider removing them.',
                warn: true,
              ),
            if (!d.membersOnly && memberTickets.isEmpty)
              const _SummaryLine(icon: Icons.info_outline, text: 'There\'s no member ticket, so members pay the same as everyone.'),
          ],
          const SizedBox(height: FlcSpace.xs),
          _SummaryLine(
            icon: Icons.loyalty_outlined,
            text: d.loyaltyEligible ? 'Paid tickets earn a loyalty point.' : 'Tickets to this event do not earn loyalty points.',
          ),
        ],
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.icon, required this.text, this.warn = false});

  final IconData icon;
  final String text;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: FlcSpace.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: warn ? FlcColors.warning : FlcColors.secondary(context)),
          const SizedBox(width: FlcSpace.xs),
          Expanded(child: Text(text, style: FlcTextStyles.bodySmall)),
        ],
      ),
    );
  }
}
