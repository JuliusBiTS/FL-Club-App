import 'dart:math' as math;

import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';

/// The club's olive and its two companion tones, shared with the membership
/// card so the loyalty page reads as part of the same family.
const Color kLoyaltyDeep = Color(0xFF202B08);
const Color kLoyaltyLime = Color(0xFFB7CC6C);
const Color kLoyaltyCream = Color(0xFFFBF9F2);

/// A stamp card: one circle per event, filled as you go, with a free ticket
/// waiting at the end. Stamps pop in one after another when the page opens.
class PunchCard extends StatefulWidget {
  const PunchCard({required this.balance, required this.threshold, this.rewardsReady = 0, super.key});

  /// Events counted toward the next free ticket (0 .. threshold-1).
  final int balance;
  final int threshold;

  /// Free tickets already earned and waiting to be used.
  final int rewardsReady;

  @override
  State<PunchCard> createState() => _PunchCardState();
}

class _PunchCardState extends State<PunchCard> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int threshold = math.max(1, widget.threshold);
    final int stamped = widget.balance.clamp(0, threshold);
    final int toGo = threshold - stamped;
    final int perRow = threshold <= 5 ? threshold : (threshold <= 10 ? 5 : 6);

    final String headline = widget.rewardsReady > 0 && stamped == 0 ? 'Free ticket ready' : '$stamped of $threshold';
    final String sub = toGo == threshold
        ? 'Your next free ticket starts with your next event.'
        : toGo == 1
            ? 'One more event and your next ticket is free.'
            : '$toGo more events and your next ticket is free.';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(FlcRadius.card + 6),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: <Color>[FlcColors.brand, kLoyaltyDeep]),
        boxShadow: <BoxShadow>[BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: <Widget>[
          // A big, faint ticket in the corner — texture, not content.
          Positioned(
            right: -28,
            top: -22,
            child: Transform.rotate(angle: -0.35, child: Icon(Icons.confirmation_number_outlined, size: 190, color: Colors.white.withValues(alpha: 0.05))),
          ),
          Padding(
            padding: const EdgeInsets.all(FlcSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // A Wrap, not a Row: on a narrow phone the three pieces drop
                // onto a second line instead of overflowing the card.
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    Text('FRONTLINE CLUB', style: FlcTextStyles.overline.copyWith(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
                    const Text(
                      'London',
                      style: TextStyle(fontFamily: FlcFontFamily.serif, fontStyle: FontStyle.italic, color: kLoyaltyLime, fontSize: 13, height: 1),
                    ),
                    Text('· LOYALTY', style: FlcTextStyles.overline.copyWith(color: Colors.white60, letterSpacing: 1.6)),
                  ],
                ),
                const SizedBox(height: FlcSpace.lg),
                Text(headline, style: const TextStyle(fontFamily: FlcFontFamily.serif, fontSize: 40, fontWeight: FontWeight.w700, color: Colors.white, height: 1.05)),
                const SizedBox(height: FlcSpace.xs),
                Text(sub, style: FlcTextStyles.body.copyWith(color: Colors.white70)),
                const SizedBox(height: FlcSpace.lg),
                LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints c) {
                    const double gap = 10;
                    final double size = math.min(52, (c.maxWidth - gap * (perRow - 1)) / perRow);
                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: <Widget>[
                        for (int i = 0; i < threshold; i++)
                          _Stamp(
                            size: size,
                            state: i < stamped ? _StampState.earned : (i == stamped && i != threshold - 1 ? _StampState.next : _StampState.empty),
                            isReward: i == threshold - 1,
                            animation: CurvedAnimation(
                              parent: _controller,
                              curve: Interval(math.min(0.85, i / (threshold + 2)), math.min(1, i / (threshold + 2) + 0.25), curve: Curves.elasticOut),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: FlcSpace.md),
                Text(
                  'One stamp per event, however many tickets you buy for it.',
                  style: FlcTextStyles.caption.copyWith(color: Colors.white60),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _StampState { earned, next, empty }

class _Stamp extends StatelessWidget {
  const _Stamp({required this.size, required this.state, required this.isReward, required this.animation});

  final double size;
  final _StampState state;
  final bool isReward;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final bool earned = state == _StampState.earned;
    final bool next = state == _StampState.next;

    final Widget circle = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: earned ? kLoyaltyLime : Colors.white.withValues(alpha: isReward ? 0.06 : 0.08),
        border: Border.all(
          color: earned
              ? kLoyaltyLime
              : isReward
                  ? FlcColors.warning
                  : (next ? Colors.white70 : Colors.white24),
          width: next || isReward ? 2 : 1.4,
        ),
      ),
      child: Center(
        child: isReward && !earned
            ? Icon(Icons.card_giftcard, size: size * 0.5, color: const Color(0xFFE8B84A))
            : Icon(
                earned ? Icons.check_rounded : Icons.confirmation_number_outlined,
                size: size * (earned ? 0.58 : 0.42),
                color: earned ? kLoyaltyDeep : Colors.white24,
              ),
      ),
    );

    // Only earned stamps pop in; the rest are simply there.
    if (!earned) return circle;
    return ScaleTransition(scale: animation, child: circle);
  }
}

/// A free ticket as a coupon: notches at the sides, a dashed tear line.
class RewardTicket extends StatelessWidget {
  const RewardTicket({required this.earnedAt, this.expiresAt, super.key});

  final DateTime earnedAt;
  final DateTime? expiresAt;

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Color paper = dark ? const Color(0xFF26301A) : kLoyaltyCream;
    final Color edge = dark ? Colors.white24 : const Color(0xFFD8D2BE);
    final Color ink = dark ? Colors.white : kLoyaltyDeep;
    final Color muted = dark ? Colors.white70 : FlcColors.slate;

    return CustomPaint(
      painter: _TicketPainter(color: paper, edge: edge, notch: Theme.of(context).scaffoldBackgroundColor),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(FlcSpace.lg, FlcSpace.md, FlcSpace.lg, FlcSpace.md),
        child: Row(
          children: <Widget>[
            Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(color: FlcColors.brand, shape: BoxShape.circle),
              child: const Icon(Icons.card_giftcard, color: kLoyaltyLime),
            ),
            const SizedBox(width: FlcSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Free ticket', style: TextStyle(fontFamily: FlcFontFamily.serif, fontSize: 20, fontWeight: FontWeight.w700, color: ink)),
                  const SizedBox(height: 2),
                  Text('Apply it at checkout on any event', style: FlcTextStyles.bodySmall.copyWith(color: muted)),
                ],
              ),
            ),
            const SizedBox(width: FlcSpace.sm),
            Text(
              expiresAt == null ? 'No expiry' : 'Use by ${_short(expiresAt!)}',
              style: FlcTextStyles.caption.copyWith(color: muted, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  static String _short(DateTime d) {
    const List<String> m = <String>['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }
}

class _TicketPainter extends CustomPainter {
  _TicketPainter({required this.color, required this.edge, required this.notch});

  final Color color;
  final Color edge;
  final Color notch;

  @override
  void paint(Canvas canvas, Size size) {
    const double r = 11; // notch radius
    final Path body = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(FlcRadius.card)));
    final Path cutouts = Path()
      ..addOval(Rect.fromCircle(center: Offset(0, size.height / 2), radius: r))
      ..addOval(Rect.fromCircle(center: Offset(size.width, size.height / 2), radius: r));
    final Path ticket = Path.combine(PathOperation.difference, body, cutouts);

    canvas.drawShadow(ticket, Colors.black.withValues(alpha: 0.35), 4, false);
    canvas.drawPath(ticket, Paint()..color = color);
    canvas.drawPath(ticket, Paint()..color = edge..style = PaintingStyle.stroke..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(_TicketPainter old) => old.color != color || old.edge != edge || old.notch != notch;
}

/// "How it works", in three short lines.
class LoyaltyHowItWorks extends StatelessWidget {
  const LoyaltyHowItWorks({required this.threshold, super.key});

  final int threshold;

  @override
  Widget build(BuildContext context) {
    final Color muted = FlcColors.secondary(context);
    Widget line(IconData icon, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, size: 20, color: FlcColors.accent(context)),
              const SizedBox(width: FlcSpace.sm),
              Expanded(child: Text(text, style: FlcTextStyles.body)),
            ],
          ),
        );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(FlcSpace.md),
      decoration: BoxDecoration(border: Border.all(color: muted.withValues(alpha: 0.35)), borderRadius: BorderRadius.circular(FlcRadius.card)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('HOW IT WORKS', style: FlcTextStyles.overline.copyWith(color: muted)),
          const SizedBox(height: FlcSpace.xs),
          line(Icons.confirmation_number_outlined, 'Every event you book earns one stamp — however many tickets you buy for it.'),
          line(Icons.card_giftcard, 'Collect $threshold stamps and your next ticket is free.'),
          line(Icons.shopping_bag_outlined, 'Your free ticket appears here. Apply it at checkout on any event.'),
          Padding(
            padding: const EdgeInsets.only(top: FlcSpace.xs),
            child: Text('Free tickets and some special events don\'t earn a stamp.', style: FlcTextStyles.caption.copyWith(color: muted)),
          ),
        ],
      ),
    );
  }
}
